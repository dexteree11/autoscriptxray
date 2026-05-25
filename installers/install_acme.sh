#!/bin/bash
# =============================================================================
#  IMAGITECH XRAY — TLS Certificate Installer via acme.sh + Cloudflare DNS API
#  File   : installers/install_acme.sh
#  Author : IMAGITECH XRAY Panel
#  Purpose: Install acme.sh, issue/renew/remove TLS certs for the panel domain
# =============================================================================

# ---------------------------------------------------------------------------
# Shared libraries
# ---------------------------------------------------------------------------
source /opt/imagitech-xray/lib/colors.sh
source /opt/imagitech-xray/lib/ui.sh

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly ACME_INSTALL_URL="https://get.acme.sh"
readonly ACME_HOME="${HOME}/.acme.sh"
readonly ACME_BIN="${ACME_HOME}/acme.sh"
readonly KEYS_DIR="/opt/imagitech-xray/core/keys"
readonly PANEL_CONF="/opt/imagitech-xray/core/imagitech-xray.conf"
readonly FULLCHAIN_DEST="${KEYS_DIR}/fullchain.pem"
readonly PRIVKEY_DEST="${KEYS_DIR}/privkey.pem"
# Renewal hook: reload nginx and restart xray after each successful renewal
readonly RENEWAL_HOOK="systemctl reload nginx && systemctl restart xray"
# Warn if cert expires within 7 days (604800 seconds)
readonly CERT_WARN_SECONDS=604800

# =============================================================================
#  install_acme
#  Installs acme.sh to ~/.acme.sh if not already present.
#  Uses the official installer from https://get.acme.sh
# =============================================================================
install_acme() {
    draw_top "IMAGITECH XRAY — Install acme.sh"

    if [[ -x "${ACME_BIN}" ]]; then
        info "acme.sh is already installed at ${ACME_BIN}"
        info "Checking for updates..."
        step "Upgrading acme.sh"
        "${ACME_BIN}" --upgrade --auto-upgrade 0 \
            && success "acme.sh upgraded successfully." \
            || warn "acme.sh upgrade failed (non-fatal — existing version will be used)."
        draw_bot
        return 0
    fi

    step "Downloading and installing acme.sh from ${ACME_INSTALL_URL}"

    # Prefer curl; fall back to wget
    if command -v curl &>/dev/null; then
        spinner "Fetching installer" \
            curl -fsSL "${ACME_INSTALL_URL}" -o /tmp/install_acme.sh
    elif command -v wget &>/dev/null; then
        spinner "Fetching installer" \
            wget -qO /tmp/install_acme.sh "${ACME_INSTALL_URL}"
    else
        error "Neither curl nor wget is available. Cannot download acme.sh."
        draw_bot
        return 1
    fi

    if [[ ! -f /tmp/install_acme.sh ]]; then
        error "Download failed — installer script not found at /tmp/install_acme.sh."
        draw_bot
        return 1
    fi

    chmod +x /tmp/install_acme.sh
    spinner "Running acme.sh installer" \
        bash /tmp/install_acme.sh email="admin@imagitech.local" --force 2>&1
    local rc=$?
    rm -f /tmp/install_acme.sh

    if [[ $rc -ne 0 ]] || [[ ! -x "${ACME_BIN}" ]]; then
        error "acme.sh installation failed (exit code: ${rc})."
        draw_bot
        return 1
    fi

    success "acme.sh installed successfully at ${ACME_BIN}."
    draw_bot
    return 0
}

# =============================================================================
#  issue_cert_cloudflare <DOMAIN> <CF_KEY> <CF_EMAIL>
#  Issues a TLS certificate for DOMAIN using the Cloudflare DNS API.
#  Installs the cert into /opt/imagitech-xray/core/keys/ and configures
#  an auto-renewal hook to reload nginx + restart xray.
#
#  Arguments:
#    $1 - DOMAIN    : fully-qualified domain name (e.g. vpn.example.com)
#    $2 - CF_KEY    : Cloudflare Global API Key
#    $3 - CF_EMAIL  : Cloudflare account e-mail address
# =============================================================================
issue_cert_cloudflare() {
    local DOMAIN="${1}"
    local CF_KEY="${2}"
    local CF_EMAIL="${3}"

    # ---- Argument validation ------------------------------------------------
    if [[ -z "${DOMAIN}" || -z "${CF_KEY}" || -z "${CF_EMAIL}" ]]; then
        error "Usage: issue_cert_cloudflare <DOMAIN> <CF_KEY> <CF_EMAIL>"
        return 1
    fi

    draw_top "IMAGITECH XRAY — Issue TLS Certificate (Cloudflare DNS)"

    # ---- Ensure acme.sh is present ------------------------------------------
    if [[ ! -x "${ACME_BIN}" ]]; then
        warn "acme.sh not found — attempting installation first..."
        install_acme || { draw_bot; return 1; }
    fi

    # ---- Ensure keys directory exists ----------------------------------------
    if [[ ! -d "${KEYS_DIR}" ]]; then
        step "Creating keys directory: ${KEYS_DIR}"
        mkdir -p "${KEYS_DIR}" || {
            error "Failed to create ${KEYS_DIR}. Check permissions."
            draw_bot
            return 1
        }
        chmod 750 "${KEYS_DIR}"
    fi

    # ---- Export Cloudflare credentials as environment variables --------------
    export CF_Key="${CF_KEY}"
    export CF_Email="${CF_EMAIL}"

    step "Issuing certificate for domain: ${DOMAIN}"
    info  "DNS provider : Cloudflare"
    info  "Account email: ${CF_EMAIL}"
    info  "Cert store   : ${KEYS_DIR}"

    # ---- Issue the certificate -----------------------------------------------
    spinner "Requesting certificate (DNS propagation may take ~60 s)" \
        "${ACME_BIN}" --issue \
            --dns dns_cf \
            -d "${DOMAIN}" \
            --server letsencrypt \
            --keylength ec-256 2>&1
    local issue_rc=$?

    # acme.sh returns exit code 2 when the cert already exists and is not due
    # for renewal — treat this as a success.
    if [[ $issue_rc -ne 0 && $issue_rc -ne 2 ]]; then
        error "Certificate issuance failed (exit code: ${issue_rc})."
        error "Check Cloudflare credentials and DNS settings for '${DOMAIN}'."
        draw_bot
        return 1
    fi

    if [[ $issue_rc -eq 2 ]]; then
        warn "Certificate already issued and not due for renewal — installing existing cert."
    else
        success "Certificate issued successfully for ${DOMAIN}."
    fi

    # ---- Install certificate into panel keys directory -----------------------
    step "Installing certificate files to ${KEYS_DIR}"

    spinner "Installing cert" \
        "${ACME_BIN}" --install-cert \
            -d "${DOMAIN}" \
            --ecc \
            --fullchain-file "${FULLCHAIN_DEST}" \
            --key-file       "${PRIVKEY_DEST}" \
            --reloadcmd      "${RENEWAL_HOOK}" 2>&1
    local install_rc=$?

    if [[ $install_rc -ne 0 ]]; then
        error "Certificate installation failed (exit code: ${install_rc})."
        draw_bot
        return 1
    fi

    # ---- Set strict permissions on private key -------------------------------
    chmod 640 "${PRIVKEY_DEST}" 2>/dev/null
    chmod 644 "${FULLCHAIN_DEST}" 2>/dev/null

    success "Certificates installed:"
    info  "  Fullchain : ${FULLCHAIN_DEST}"
    info  "  Private key: ${PRIVKEY_DEST}"
    info  "  Renewal hook: ${RENEWAL_HOOK}"

    # ---- Save configuration to panel conf file --------------------------------
    _save_conf "${DOMAIN}" "${CF_KEY}" "${CF_EMAIL}"

    draw_mid "Auto-Renewal"
    info  "acme.sh registers a cron job for automatic renewal."
    info  "On renewal, nginx is reloaded and xray is restarted."

    draw_bot
    return 0
}

# =============================================================================
#  check_cert_valid [DOMAIN]
#  Checks whether the installed certificate files exist and are not about to
#  expire (checks against a 7-day threshold using openssl).
#
#  Arguments:
#    $1 - DOMAIN (optional): used only for display purposes
#
#  Returns:
#    0 — cert exists and is valid (> 7 days remaining)
#    1 — cert missing or expiring within 7 days
# =============================================================================
check_cert_valid() {
    local DOMAIN="${1:-$(conf_get DOMAIN)}"

    draw_top "IMAGITECH XRAY — Certificate Status"
    info "Domain: ${DOMAIN:-unknown}"
    info "Checking: ${FULLCHAIN_DEST}"

    # ---- Check file existence ------------------------------------------------
    if [[ ! -f "${FULLCHAIN_DEST}" ]]; then
        error "Certificate file not found: ${FULLCHAIN_DEST}"
        warn  "Run 'issue_cert_cloudflare' to obtain a certificate."
        draw_bot
        return 1
    fi

    if [[ ! -f "${PRIVKEY_DEST}" ]]; then
        error "Private key file not found: ${PRIVKEY_DEST}"
        draw_bot
        return 1
    fi

    # ---- Display certificate info --------------------------------------------
    local subject expiry
    subject=$(openssl x509 -noout -subject -in "${FULLCHAIN_DEST}" 2>/dev/null | sed 's/subject=//')
    expiry=$(openssl x509  -noout -enddate -in "${FULLCHAIN_DEST}" 2>/dev/null | sed 's/notAfter=//')

    info "Subject : ${subject}"
    info "Expires : ${expiry}"

    # ---- Check if cert expires within threshold ------------------------------
    if openssl x509 -checkend "${CERT_WARN_SECONDS}" -noout -in "${FULLCHAIN_DEST}" &>/dev/null; then
        success "Certificate is valid and not expiring within 7 days."
        draw_bot
        return 0
    else
        warn "Certificate WILL EXPIRE within 7 days (or is already expired)!"
        warn "Run 'renew_cert ${DOMAIN}' to renew immediately."
        draw_bot
        return 1
    fi
}

# =============================================================================
#  renew_cert <DOMAIN>
#  Manually triggers acme.sh to renew the certificate for the given domain
#  and re-installs it into the panel keys directory.
#
#  Arguments:
#    $1 - DOMAIN : the domain whose cert should be renewed
# =============================================================================
renew_cert() {
    local DOMAIN="${1:-$(conf_get DOMAIN)}"

    if [[ -z "${DOMAIN}" ]]; then
        error "Usage: renew_cert <DOMAIN>"
        error "Or ensure DOMAIN is set in ${PANEL_CONF}"
        return 1
    fi

    draw_top "IMAGITECH XRAY — Renew TLS Certificate"
    step "Renewing certificate for: ${DOMAIN}"

    if [[ ! -x "${ACME_BIN}" ]]; then
        error "acme.sh not found at ${ACME_BIN}. Cannot renew."
        draw_bot
        return 1
    fi

    # Re-load saved Cloudflare credentials if available
    local CF_KEY CF_EMAIL
    CF_KEY=$(conf_get CF_Key)
    CF_EMAIL=$(conf_get CF_Email)
    [[ -n "${CF_KEY}"   ]] && export CF_Key="${CF_KEY}"
    [[ -n "${CF_EMAIL}" ]] && export CF_Email="${CF_EMAIL}"

    spinner "Renewing certificate (force)" \
        "${ACME_BIN}" --renew \
            -d "${DOMAIN}" \
            --ecc \
            --force 2>&1
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        error "Certificate renewal failed (exit code: ${rc})."
        draw_bot
        return 1
    fi

    success "Certificate renewed for ${DOMAIN}."

    # Re-install cert and trigger reload hook
    step "Re-installing renewed certificate"
    spinner "Installing cert" \
        "${ACME_BIN}" --install-cert \
            -d "${DOMAIN}" \
            --ecc \
            --fullchain-file "${FULLCHAIN_DEST}" \
            --key-file       "${PRIVKEY_DEST}" \
            --reloadcmd      "${RENEWAL_HOOK}" 2>&1

    if [[ $? -eq 0 ]]; then
        success "Certificate successfully installed."
        info    "Fullchain : ${FULLCHAIN_DEST}"
        info    "Key       : ${PRIVKEY_DEST}"
    else
        warn "Certificate renewed but install step reported an error. Check manually."
    fi

    draw_bot
    return 0
}

# =============================================================================
#  remove_cert [DOMAIN]
#  Removes the installed certificate files from the panel keys directory
#  and optionally revokes/removes the cert from acme.sh's store.
#
#  Arguments:
#    $1 - DOMAIN (optional): if provided, also removes from acme.sh store
# =============================================================================
remove_cert() {
    local DOMAIN="${1:-$(conf_get DOMAIN)}"

    draw_top "IMAGITECH XRAY — Remove TLS Certificate"

    # ---- Remove installed cert files -----------------------------------------
    local removed=0

    if [[ -f "${FULLCHAIN_DEST}" ]]; then
        step "Removing fullchain: ${FULLCHAIN_DEST}"
        rm -f "${FULLCHAIN_DEST}" && ((removed++)) \
            || warn "Failed to remove ${FULLCHAIN_DEST}"
    else
        warn "Fullchain file not found: ${FULLCHAIN_DEST} (already removed?)"
    fi

    if [[ -f "${PRIVKEY_DEST}" ]]; then
        step "Removing private key: ${PRIVKEY_DEST}"
        rm -f "${PRIVKEY_DEST}" && ((removed++)) \
            || warn "Failed to remove ${PRIVKEY_DEST}"
    else
        warn "Private key not found: ${PRIVKEY_DEST} (already removed?)"
    fi

    # ---- Remove from acme.sh store -------------------------------------------
    if [[ -n "${DOMAIN}" && -x "${ACME_BIN}" ]]; then
        step "Removing certificate from acme.sh store for: ${DOMAIN}"
        spinner "Removing acme.sh cert entry" \
            "${ACME_BIN}" --remove -d "${DOMAIN}" --ecc 2>&1
        if [[ $? -eq 0 ]]; then
            success "Removed from acme.sh store."
        else
            warn "Could not remove from acme.sh store (may not exist)."
        fi
    fi

    if [[ $removed -gt 0 ]]; then
        success "Certificate files removed (${removed} file(s) deleted)."
    else
        warn "No certificate files were removed."
    fi

    draw_bot
    return 0
}

# =============================================================================
#  _save_conf <DOMAIN> <CF_KEY> <CF_EMAIL>  [private / internal]
#  Writes DOMAIN, CF_Key, and CF_Email to the panel config file.
#  Creates the file if it does not exist; updates existing keys in-place.
# =============================================================================
_save_conf() {
    local DOMAIN="${1}"
    local CF_KEY="${2}"
    local CF_EMAIL="${3}"

    # Ensure parent directory exists
    mkdir -p "$(dirname "${PANEL_CONF}")" 2>/dev/null

    # Helper: set or update a key=value pair in the conf file
    _conf_set() {
        local key="${1}" val="${2}"
        if grep -q "^${key}=" "${PANEL_CONF}" 2>/dev/null; then
            # Update existing line (BSD/GNU sed compatible)
            sed -i "s|^${key}=.*|${key}=${val}|" "${PANEL_CONF}"
        else
            echo "${key}=${val}" >> "${PANEL_CONF}"
        fi
    }

    _conf_set "DOMAIN"   "${DOMAIN}"
    _conf_set "CF_Key"   "${CF_KEY}"
    _conf_set "CF_Email" "${CF_EMAIL}"

    chmod 600 "${PANEL_CONF}"
    step "Credentials saved to ${PANEL_CONF}"
}

# =============================================================================
#  conf_get <KEY>  [private / internal]
#  Reads a key=value pair from the panel config file.
# =============================================================================
conf_get() {
    local key="${1}"
    if [[ -f "${PANEL_CONF}" ]]; then
        grep "^${key}=" "${PANEL_CONF}" 2>/dev/null | cut -d'=' -f2- | head -1
    fi
}

# =============================================================================
#  Main entry point — allows the script to be called directly with an action.
#  Usage: install_acme.sh <action> [args...]
#    Actions: install | issue | check | renew | remove
# =============================================================================
_main() {
    local action="${1}"
    shift || true

    case "${action}" in
        install)
            install_acme
            ;;
        issue)
            # issue <DOMAIN> <CF_KEY> <CF_EMAIL>
            issue_cert_cloudflare "${1}" "${2}" "${3}"
            ;;
        check)
            check_cert_valid "${1}"
            ;;
        renew)
            renew_cert "${1}"
            ;;
        remove)
            remove_cert "${1}"
            ;;
        "")
            draw_top "IMAGITECH XRAY — acme.sh Certificate Manager"
            info "Usage: $0 <action> [args]"
            info ""
            info "  install                         Install acme.sh"
            info "  issue  <DOMAIN> <CF_KEY> <CF_EMAIL>  Issue cert via Cloudflare"
            info "  check  [DOMAIN]                 Check cert validity"
            info "  renew  [DOMAIN]                 Force-renew cert"
            info "  remove [DOMAIN]                 Remove cert files"
            draw_bot
            ;;
        *)
            error "Unknown action: '${action}'"
            error "Valid actions: install | issue | check | renew | remove"
            exit 1
            ;;
    esac
}

# Run main only when the script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _main "$@"
fi
