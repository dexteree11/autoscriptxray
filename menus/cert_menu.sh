#!/bin/bash
# ==========================================================
# menus/cert_menu.sh — Certificate Manager (acme.sh + CF)
# Imagitech XRAY Suite
# ==========================================================
source /opt/imagitech-xray/lib/colors.sh
source /opt/imagitech-xray/lib/ui.sh
source /opt/imagitech-xray/lib/xray_utils.sh

CONF_FILE="/opt/imagitech-xray/core/imagitech-xray.conf"
KEYS_DIR="/opt/imagitech-xray/core/keys"
ACME_BIN="${HOME}/.acme.sh/acme.sh"

[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

draw_header() {
    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

    local cert_status
    if [[ -f "${KEYS_DIR}/fullchain.pem" ]]; then
        local expiry
        expiry=$(openssl x509 -enddate -noout -in "${KEYS_DIR}/fullchain.pem" 2>/dev/null | cut -d= -f2)
        if openssl x509 -checkend 604800 -noout -in "${KEYS_DIR}/fullchain.pem" &>/dev/null; then
            cert_status="${BGREEN}Valid${NC} (expires: ${expiry})"
        else
            cert_status="${BRED}EXPIRING SOON${NC} (${expiry})"
        fi
    else
        cert_status="${BRED}Not Issued${NC}"
    fi

    clear
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║${NC}${BOLD}${BCYAN}         ✦  CERTIFICATE MANAGER  ✦                      ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Domain : ${DOMAIN:-not configured}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Status : ${cert_status}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  acme.sh: $([[ -f "$ACME_BIN" ]] && echo "Installed" || echo "Not installed")"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${CYAN}[01]${NC} %-52s${CYAN}║${NC}\n" "Install acme.sh"
    printf "${CYAN}  ║${NC}  ${CYAN}[02]${NC} %-52s${CYAN}║${NC}\n" "Issue Certificate (Cloudflare DNS)"
    printf "${CYAN}  ║${NC}  ${CYAN}[03]${NC} %-52s${CYAN}║${NC}\n" "Check Certificate Validity"
    printf "${CYAN}  ║${NC}  ${CYAN}[04]${NC} %-52s${CYAN}║${NC}\n" "Renew Certificate (Force)"
    printf "${CYAN}  ║${NC}  ${CYAN}[05]${NC} %-52s${CYAN}║${NC}\n" "Show Certificate Details"
    printf "${CYAN}  ║${NC}  ${RED}[06]${NC} %-52s${CYAN}║${NC}\n" "Remove Certificate"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${RED}[00]${NC} %-52s${CYAN}║${NC}\n" "Back to Main Menu"
    echo -e "${CYAN}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

do_install_acme() {
    clear; draw_line
    echo -e "  ${BOLD}INSTALL acme.sh${NC}"; draw_line; echo ""
    bash /opt/imagitech-xray/installers/install_acme.sh install
    pause
}

do_issue_cert() {
    clear; draw_line
    echo -e "  ${BOLD}ISSUE CERTIFICATE — Cloudflare DNS${NC}"; draw_line; echo ""

    if [[ ! -f "$ACME_BIN" ]]; then
        error "acme.sh is not installed. Please install it first (option [01])."
        pause; return
    fi

    # Collect inputs
    read -p "$(echo -e "  ${ORANGE}Domain (e.g. vpn.example.com): ${NC}")" input_domain
    [[ -z "$input_domain" ]] && { error "Domain cannot be empty."; pause; return; }

    read -p "$(echo -e "  ${ORANGE}Cloudflare API Token: ${NC}")" input_cf_key
    [[ -z "$input_cf_key" ]] && { error "CF API Token cannot be empty."; pause; return; }

    read -p "$(echo -e "  ${ORANGE}Cloudflare Account Email: ${NC}")" input_cf_email
    [[ -z "$input_cf_email" ]] && { error "CF Email cannot be empty."; pause; return; }

    bash /opt/imagitech-xray/installers/install_acme.sh issue "$input_domain" "$input_cf_key" "$input_cf_email"
    pause
}

do_check_cert() {
    clear; draw_line
    echo -e "  ${BOLD}CHECK CERTIFICATE${NC}"; draw_line; echo ""

    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
    bash /opt/imagitech-xray/installers/install_acme.sh check "${DOMAIN:-}"
    pause
}

do_renew_cert() {
    clear; draw_line
    echo -e "  ${BOLD}RENEW CERTIFICATE${NC}"; draw_line; echo ""

    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
    if [[ -z "$DOMAIN" ]]; then
        error "No domain configured. Issue a certificate first."
        pause; return
    fi

    confirm "Force renew certificate for ${DOMAIN}?" || return
    bash /opt/imagitech-xray/installers/install_acme.sh renew "$DOMAIN"
    pause
}

do_show_cert_details() {
    clear; draw_line
    echo -e "  ${BOLD}CERTIFICATE DETAILS${NC}"; draw_line; echo ""

    if [[ ! -f "${KEYS_DIR}/fullchain.pem" ]]; then
        warn "No certificate found at ${KEYS_DIR}/fullchain.pem"
        pause; return
    fi

    echo ""
    openssl x509 -in "${KEYS_DIR}/fullchain.pem" -noout \
        -subject -issuer -dates -fingerprint -sha256 2>/dev/null
    echo ""
    kv "Cert Path" "${KEYS_DIR}/fullchain.pem"
    kv "Key Path"  "${KEYS_DIR}/privkey.pem"
    echo ""
    pause
}

do_remove_cert() {
    clear; draw_line
    echo -e "  ${BOLD}REMOVE CERTIFICATE${NC}"; draw_line; echo ""

    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
    confirm "Remove certificate for ${DOMAIN:-unknown}? This is irreversible!" || return

    bash /opt/imagitech-xray/installers/install_acme.sh remove "${DOMAIN:-}"
    pause
}

main() {
    while true; do
        draw_header
        read -p "$(echo -e "  ${ORANGE}Select Option : ${NC}")" opt
        case "$opt" in
            1|01) do_install_acme ;;
            2|02) do_issue_cert ;;
            3|03) do_check_cert ;;
            4|04) do_renew_cert ;;
            5|05) do_show_cert_details ;;
            6|06) do_remove_cert ;;
            0|00) return ;;
            *) error "Invalid option"; sleep 1 ;;
        esac
    done
}

main
