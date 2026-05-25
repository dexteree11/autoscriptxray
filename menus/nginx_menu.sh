#!/bin/bash
# ==========================================================
# menus/nginx_menu.sh — Nginx Manager
# Imagitech XRAY Suite
# ==========================================================
source /opt/imagitech-xray/lib/colors.sh
source /opt/imagitech-xray/lib/ui.sh
source /opt/imagitech-xray/lib/xray_utils.sh

CONF_FILE="/opt/imagitech-xray/core/imagitech-xray.conf"
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

draw_header() {
    local nginx_svc
    nginx_svc=$(service_status "nginx")
    local nginx_ver
    nginx_ver=$(nginx -v 2>&1 | grep -oP 'nginx/\K[\d.]+' || echo "not installed")
    clear
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║${NC}${BOLD}${BCYAN}             ✦  NGINX MANAGER  ✦                        ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Nginx  v${nginx_ver}  —  ${nginx_svc}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Domain : ${DOMAIN:-not configured}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${CYAN}[01]${NC} %-52s${CYAN}║${NC}\n" "Install Nginx"
    printf "${CYAN}  ║${NC}  ${CYAN}[02]${NC} %-52s${CYAN}║${NC}\n" "Configure Nginx (WS Proxy)"
    printf "${CYAN}  ║${NC}  ${CYAN}[03]${NC} %-52s${CYAN}║${NC}\n" "Test Nginx Config"
    printf "${CYAN}  ║${NC}  ${CYAN}[04]${NC} %-52s${CYAN}║${NC}\n" "Reload Nginx Config"
    printf "${CYAN}  ║${NC}  ${CYAN}[05]${NC} %-52s${CYAN}║${NC}\n" "View Nginx Access Log (last 30)"
    printf "${CYAN}  ║${NC}  ${CYAN}[06]${NC} %-52s${CYAN}║${NC}\n" "View Nginx Error Log (last 30)"
    printf "${CYAN}  ║${NC}  ${RED}[07]${NC} %-52s${CYAN}║${NC}\n" "Remove Nginx"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${RED}[00]${NC} %-52s${CYAN}║${NC}\n" "Back to Main Menu"
    echo -e "${CYAN}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

do_install_nginx() {
    clear; draw_line
    echo -e "  ${BOLD}INSTALL NGINX${NC}"; draw_line
    bash /opt/imagitech-xray/installers/install_nginx.sh install
    pause
}

do_configure_nginx() {
    clear; draw_line
    echo -e "  ${BOLD}CONFIGURE NGINX${NC}"; draw_line; echo ""

    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

    if [[ -z "$DOMAIN" ]]; then
        error "No domain set. Please issue a TLS certificate first (Certificate Manager)."
        pause; return
    fi

    if [[ ! -f "/opt/imagitech-xray/core/keys/fullchain.pem" ]]; then
        error "Certificate not found. Please issue a TLS certificate first."
        pause; return
    fi

    info "Configuring Nginx for domain: ${BWHITE}${DOMAIN}${NC}"
    bash /opt/imagitech-xray/installers/install_nginx.sh configure \
        "$DOMAIN" \
        "/opt/imagitech-xray/core/keys/fullchain.pem" \
        "/opt/imagitech-xray/core/keys/privkey.pem"
    pause
}

do_test_nginx() {
    clear; draw_line
    echo -e "  ${BOLD}TEST NGINX CONFIG${NC}"; draw_line; echo ""
    nginx -t 2>&1
    echo ""
    pause
}

do_reload_nginx() {
    step "Reloading Nginx..."
    nginx -t &>/dev/null && {
        systemctl reload nginx
        success "Nginx configuration reloaded."
    } || {
        error "Config test failed. Nginx not reloaded."
        nginx -t
    }
    pause
}

view_log() {
    local logfile="$1"
    local label="$2"
    clear; draw_line
    echo -e "  ${BOLD}NGINX ${label} (last 30 lines)${NC}"; draw_line; echo ""
    if [[ -f "$logfile" ]]; then
        tail -30 "$logfile"
    else
        journalctl -u nginx --no-pager -n 30 2>/dev/null || warn "Log file not found: $logfile"
    fi
    echo ""
    pause
}

do_remove_nginx() {
    clear; draw_line
    echo -e "  ${BOLD}REMOVE NGINX${NC}"; draw_line; echo ""
    confirm "Remove Nginx and its configuration?" || return
    bash /opt/imagitech-xray/installers/install_nginx.sh remove
    pause
}

main() {
    while true; do
        draw_header
        read -p "$(echo -e "  ${ORANGE}Select Option : ${NC}")" opt
        case "$opt" in
            1|01) do_install_nginx ;;
            2|02) do_configure_nginx ;;
            3|03) do_test_nginx ;;
            4|04) do_reload_nginx ;;
            5|05) view_log "/var/log/nginx/access.log" "ACCESS LOG" ;;
            6|06) view_log "/var/log/nginx/error.log" "ERROR LOG" ;;
            7|07) do_remove_nginx ;;
            0|00) return ;;
            *) error "Invalid option"; sleep 1 ;;
        esac
    done
}

main
