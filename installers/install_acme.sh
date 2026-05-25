#!/bin/bash
# =============================================================================
#  IMAGITECH XRAY — TLS Certificate Manager via acme.sh
#  File   : installers/install_acme.sh
#  Purpose: Install acme.sh, issue/renew/remove TLS certs
#           Supports: standalone HTTP-01 and manual DNS verification
# =============================================================================

source /opt/imagitech-xray/lib/colors.sh 2>/dev/null
source /opt/imagitech-xray/lib/ui.sh 2>/dev/null

readonly ACME_HOME="${HOME}/.acme.sh"
readonly ACME_BIN="${ACME_HOME}/acme.sh"
readonly KEYS_DIR="/opt/imagitech-xray/core/keys"
readonly PANEL_CONF="/opt/imagitech-xray/core/imagitech-xray.conf"
readonly FULLCHAIN_DEST="${KEYS_DIR}/fullchain.pem"
readonly PRIVKEY_DEST="${KEYS_DIR}/privkey.pem"
readonly RENEWAL_HOOK="systemctl reload nginx 2>/dev/null; systemctl restart xray"

# =============================================================================
# install_acme — Install acme.sh to ~/.acme.sh
# =============================================================================
install_acme() {
    draw_top
    echo -e "  ${BOLD}INSTALL acme.sh${NC}"
    draw_mid

    if [[ -x "${ACME_BIN}" ]]; then
        info "acme.sh already installed at ${ACME_BIN}"
        step "Upgrading..."
        "${ACME_BIN}" --upgrade --auto-upgrade 0 &>/dev/null \
            && success "acme.sh upgraded." \
            || warn "Upgrade failed (non-fatal)."
        draw_bot
        return 0
    fi

    step "Downloading acme.sh from https://get.acme.sh ..."

    local tmp_installer="/tmp/install_acme_$$.sh"

    if command -v curl &>/dev/null; then
        curl -fsSL https://get.acme.sh -o "$tmp_installer" 2>/dev/null
    elif command -v wget &>/dev/null; then
        wget -qO "$tmp_installer" https://get.acme.sh 2>/dev/null
    else
        error "Neither curl nor wget is installed."
        draw_bot; return 1
    fi

    if [[ ! -s "$tmp_installer" ]]; then
        error "Download failed. Check internet connectivity."
        draw_bot; return 1
    fi

    chmod +x "$tmp_installer"
    bash "$tmp_installer" email="admin@imagitech.online" --force 2>&1 | grep -E "Installing|OK|error|Error"
    local rc=$?
    rm -f "$tmp_installer"

    if [[ $rc -ne 0 ]] || [[ ! -x "${ACME_BIN}" ]]; then
        error "acme.sh installation failed."
        draw_bot; return 1
    fi

    success "acme.sh installed at ${ACME_BIN}"
    draw_bot
    return 0
}

# =============================================================================
# issue_cert_standalone <DOMAIN> <EMAIL>
# Uses HTTP-01 challenge on port 80 (stop nginx first if running)
# =============================================================================
issue_cert_standalone() {
    local DOMAIN="$1"
    local EMAIL="$2"

    [[ -z "$DOMAIN" || -z "$EMAIL" ]] && { error "Usage: issue_cert_standalone <DOMAIN> <EMAIL>"; return 1; }

    draw_top
    echo -e "  ${BOLD}ISSUE CERT — HTTP Standalone${NC}"
    draw_mid

    if [[ ! -x "${ACME_BIN}" ]]; then
        warn "acme.sh not found — installing first..."
        install_acme || { draw_bot; return 1; }
    fi

    mkdir -p "${KEYS_DIR}"

    # Register account
    step "Registering Let's Encrypt account..."
    "${ACME_BIN}" --register-account -m "$EMAIL" --server letsencrypt &>/dev/null || true

    # Stop nginx temporarily for port 80 challenge
    local nginx_was_running=false
    if systemctl is-active --quiet nginx 2>/dev/null; then
        nginx_was_running=true
        step "Stopping Nginx temporarily for HTTP challenge..."
        systemctl stop nginx
        sleep 1
    fi

    step "Requesting certificate for ${DOMAIN} (HTTP-01)..."
    "${ACME_BIN}" --issue \
        --standalone \
        -d "$DOMAIN" \
        --server letsencrypt \
        --keylength ec-256 2>&1
    local issue_rc=$?

    # Restart nginx if we stopped it
    if $nginx_was_running; then
        step "Restarting Nginx..."
        systemctl start nginx 2>/dev/null
    fi

    if [[ $issue_rc -ne 0 && $issue_rc -ne 2 ]]; then
        error "Certificate issuance failed (exit code: ${issue_rc})."
        error "Ensure port 80 is open and ${DOMAIN} DNS points to this server."
        draw_bot; return 1
    fi

    [[ $issue_rc -eq 2 ]] && warn "Certificate already issued and up-to-date."

    _install_cert "$DOMAIN"
    local install_rc=$?

    if [[ $install_rc -eq 0 ]]; then
        _save_conf "$DOMAIN" "$EMAIL"
        success "Certificate ready for ${DOMAIN}"
        info "  Fullchain : ${FULLCHAIN_DEST}"
        info "  Key       : ${PRIVKEY_DEST}"
    fi

    draw_bot
    return $install_rc
}

# =============================================================================
# issue_cert_dns_manual <DOMAIN> <EMAIL>
# Uses DNS-01 manual challenge — user adds TXT record themselves
# =============================================================================
issue_cert_dns_manual() {
    local DOMAIN="$1"
    local EMAIL="$2"

    [[ -z "$DOMAIN" || -z "$EMAIL" ]] && { error "Usage: issue_cert_dns_manual <DOMAIN> <EMAIL>"; return 1; }

    draw_top
    echo -e "  ${BOLD}ISSUE CERT — Manual DNS${NC}"
    draw_mid

    if [[ ! -x "${ACME_BIN}" ]]; then
        warn "acme.sh not found — installing first..."
        install_acme || { draw_bot; return 1; }
    fi

    mkdir -p "${KEYS_DIR}"

    step "Registering Let's Encrypt account..."
    "${ACME_BIN}" --register-account -m "$EMAIL" --server letsencrypt &>/dev/null || true

    step "Starting manual DNS challenge for ${DOMAIN}..."
    echo ""
    warn "You will need to add a DNS TXT record to prove domain ownership."
    warn "acme.sh will tell you the exact record to add. After adding it,"
    warn "wait a few minutes for DNS propagation, then press Enter."
    echo ""

    "${ACME_BIN}" --issue \
        --dns \
        -d "$DOMAIN" \
        --server letsencrypt \
        --keylength ec-256 \
        --yes-I-know-dns-manual-mode-enough-go-ahead-please 2>&1
    local issue_rc=$?

    if [[ $issue_rc -ne 0 ]]; then
        echo ""
        info "Above you should see a TXT record to add to your DNS."
        info "Add it at dash.cloudflare.com → DNS → Add record:"
        info "  Type: TXT"
        info "  Name: _acme-challenge.${DOMAIN}"
        info "  Value: (the value shown above)"
        echo ""
        read -p "$(echo -e "  ${ORANGE}Press Enter after DNS TXT record is set and propagated... ${NC}")"

        # Renew to complete the challenge
        "${ACME_BIN}" --renew \
            -d "$DOMAIN" \
            --server letsencrypt \
            --yes-I-know-dns-manual-mode-enough-go-ahead-please 2>&1
        issue_rc=$?
    fi

    if [[ $issue_rc -ne 0 && $issue_rc -ne 2 ]]; then
        error "Certificate issuance failed (exit code: ${issue_rc})."
        draw_bot; return 1
    fi

    _install_cert "$DOMAIN"
    local install_rc=$?

    if [[ $install_rc -eq 0 ]]; then
        _save_conf "$DOMAIN" "$EMAIL"
        success "Certificate ready for ${DOMAIN}"
        info "  Fullchain : ${FULLCHAIN_DEST}"
        info "  Key       : ${PRIVKEY_DEST}"
    fi

    draw_bot
    return $install_rc
}

# =============================================================================
# _install_cert <DOMAIN> — internal: copy cert files into panel keys dir
# =============================================================================
_install_cert() {
    local DOMAIN="$1"
    step "Installing certificate files to ${KEYS_DIR}..."

    "${ACME_BIN}" --install-cert \
        -d "$DOMAIN" \
        --ecc \
        --fullchain-file "${FULLCHAIN_DEST}" \
        --key-file       "${PRIVKEY_DEST}" \
        --reloadcmd      "${RENEWAL_HOOK}" 2>&1
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        error "Certificate file install failed (exit code: ${rc})."
        return 1
    fi

    chmod 640 "${PRIVKEY_DEST}" 2>/dev/null
    chmod 644 "${FULLCHAIN_DEST}" 2>/dev/null

    # Save cert paths to panel conf
    _conf_set "CERT_PATH" "${FULLCHAIN_DEST}"
    _conf_set "KEY_PATH"  "${PRIVKEY_DEST}"

    return 0
}

# =============================================================================
# check_cert_valid [DOMAIN]
# =============================================================================
check_cert_valid() {
    local DOMAIN="${1:-}"
    draw_top
    echo -e "  ${BOLD}CERTIFICATE STATUS${NC}"
    draw_mid

    if [[ ! -f "${FULLCHAIN_DEST}" ]]; then
        error "No certificate at ${FULLCHAIN_DEST}"
        warn  "Issue a certificate first."
        draw_bot; return 1
    fi

    local subject expiry
    subject=$(openssl x509 -noout -subject -in "${FULLCHAIN_DEST}" 2>/dev/null | sed 's/subject=//')
    expiry=$(openssl x509  -noout -enddate -in "${FULLCHAIN_DEST}" 2>/dev/null | sed 's/notAfter=//')

    info "Subject : ${subject}"
    info "Expires : ${expiry}"

    if openssl x509 -checkend 604800 -noout -in "${FULLCHAIN_DEST}" &>/dev/null; then
        success "Certificate is valid (more than 7 days remaining)."
        draw_bot; return 0
    else
        warn "Certificate expires within 7 days or is already expired!"
        warn "Run 'Renew Certificate' from the cert menu."
        draw_bot; return 1
    fi
}

# =============================================================================
# renew_cert [DOMAIN]
# =============================================================================
renew_cert() {
    local DOMAIN="${1:-$(conf_get DOMAIN)}"
    draw_top
    echo -e "  ${BOLD}RENEW CERTIFICATE — ${DOMAIN}${NC}"
    draw_mid

    [[ -z "$DOMAIN" ]] && { error "No domain configured."; draw_bot; return 1; }
    [[ ! -x "${ACME_BIN}" ]] && { error "acme.sh not found."; draw_bot; return 1; }

    step "Force-renewing certificate for ${DOMAIN}..."
    "${ACME_BIN}" --renew -d "$DOMAIN" --ecc --force 2>&1
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        error "Renewal failed (exit code: ${rc})."
        draw_bot; return 1
    fi

    success "Certificate renewed."
    _install_cert "$DOMAIN"
    draw_bot
    return 0
}

# =============================================================================
# remove_cert [DOMAIN]
# =============================================================================
remove_cert() {
    local DOMAIN="${1:-$(conf_get DOMAIN)}"
    draw_top
    echo -e "  ${BOLD}REMOVE CERTIFICATE${NC}"
    draw_mid

    [[ -f "${FULLCHAIN_DEST}" ]] && rm -f "${FULLCHAIN_DEST}" && success "Removed fullchain."
    [[ -f "${PRIVKEY_DEST}" ]]   && rm -f "${PRIVKEY_DEST}"   && success "Removed private key."

    if [[ -n "$DOMAIN" && -x "${ACME_BIN}" ]]; then
        step "Removing from acme.sh store..."
        "${ACME_BIN}" --remove -d "$DOMAIN" --ecc &>/dev/null \
            && success "Removed from acme.sh store." \
            || warn "Could not remove from acme.sh store."
    fi

    draw_bot
    return 0
}

# =============================================================================
# _save_conf / conf_get helpers
# =============================================================================
_save_conf() {
    local DOMAIN="$1"
    local EMAIL="$2"
    mkdir -p "$(dirname "${PANEL_CONF}")" 2>/dev/null
    _conf_set "DOMAIN"    "$DOMAIN"
    _conf_set "ACME_EMAIL" "$EMAIL"
    chmod 600 "${PANEL_CONF}"
    step "Config saved to ${PANEL_CONF}"
}

_conf_set() {
    local key="$1" val="$2"
    mkdir -p "$(dirname "${PANEL_CONF}")" 2>/dev/null
    touch "${PANEL_CONF}"
    if grep -q "^${key}=" "${PANEL_CONF}" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=\"${val}\"|" "${PANEL_CONF}"
    else
        echo "${key}=\"${val}\"" >> "${PANEL_CONF}"
    fi
}

conf_get() {
    local key="$1"
    [[ -f "${PANEL_CONF}" ]] && grep "^${key}=" "${PANEL_CONF}" 2>/dev/null | cut -d'=' -f2- | tr -d '"' | head -1
}

# =============================================================================
# Main entry point
# =============================================================================
_main() {
    local action="${1:-}"
    shift || true
    case "${action}" in
        install)   install_acme ;;
        standalone) issue_cert_standalone "${1}" "${2}" ;;
        dns-manual) issue_cert_dns_manual "${1}" "${2}" ;;
        check)     check_cert_valid "${1:-}" ;;
        renew)     renew_cert "${1:-}" ;;
        remove)    remove_cert "${1:-}" ;;
        "")
            draw_top
            info "Usage: $0 <action> [args]"
            info ""
            info "  install                           Install acme.sh"
            info "  standalone <DOMAIN> <EMAIL>       Issue cert via HTTP-01"
            info "  dns-manual <DOMAIN> <EMAIL>       Issue cert via manual DNS TXT"
            info "  check  [DOMAIN]                   Check cert validity"
            info "  renew  [DOMAIN]                   Force-renew cert"
            info "  remove [DOMAIN]                   Remove cert files"
            draw_bot ;;
        *)
            error "Unknown action: '${action}'"
            exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _main "$@"
fi
