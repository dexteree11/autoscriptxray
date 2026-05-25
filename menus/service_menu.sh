#!/bin/bash
# ==========================================================
# menus/service_menu.sh — Xray & Nginx Service Manager
# Imagitech XRAY Suite
# ==========================================================
source /opt/imagitech-xray/lib/colors.sh
source /opt/imagitech-xray/lib/ui.sh
source /opt/imagitech-xray/lib/xray_utils.sh

draw_header() {
    local xray_svc nginx_svc xray_ver
    xray_svc=$(service_status "xray")
    nginx_svc=$(service_status "nginx")
    xray_ver=$(get_xray_version)
    clear
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║${NC}${BOLD}${BCYAN}           ✦  XRAY SERVICE MANAGER  ✦                   ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Xray   v${xray_ver}  —  ${xray_svc}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Nginx  —  ${nginx_svc}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}  ║${NC}  ${BOLD}── XRAY ─────────────────────────────────────────────${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${CYAN}[01]${NC} %-52s${CYAN}║${NC}\n" "Start Xray"
    printf "${CYAN}  ║${NC}  ${CYAN}[02]${NC} %-52s${CYAN}║${NC}\n" "Stop Xray"
    printf "${CYAN}  ║${NC}  ${CYAN}[03]${NC} %-52s${CYAN}║${NC}\n" "Restart Xray"
    printf "${CYAN}  ║${NC}  ${CYAN}[04]${NC} %-52s${CYAN}║${NC}\n" "View Xray Status"
    printf "${CYAN}  ║${NC}  ${CYAN}[05]${NC} %-52s${CYAN}║${NC}\n" "View Xray Logs (last 50 lines)"
    printf "${CYAN}  ║${NC}  ${CYAN}[06]${NC} %-52s${CYAN}║${NC}\n" "Validate Config"
    printf "${CYAN}  ║${NC}  ${CYAN}[07]${NC} %-52s${CYAN}║${NC}\n" "Update Xray Core"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}  ║${NC}  ${BOLD}── NGINX ────────────────────────────────────────────${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${MAGENTA}[08]${NC} %-52s${CYAN}║${NC}\n" "Start Nginx"
    printf "${CYAN}  ║${NC}  ${MAGENTA}[09]${NC} %-52s${CYAN}║${NC}\n" "Stop Nginx"
    printf "${CYAN}  ║${NC}  ${MAGENTA}[10]${NC} %-52s${CYAN}║${NC}\n" "Restart Nginx"
    printf "${CYAN}  ║${NC}  ${MAGENTA}[11]${NC} %-52s${CYAN}║${NC}\n" "View Nginx Status"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${RED}[00]${NC} %-52s${CYAN}║${NC}\n" "Back to Main Menu"
    echo -e "${CYAN}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

view_xray_logs() {
    clear
    draw_line
    echo -e "  ${BOLD}XRAY LOGS (last 50 lines)${NC}"
    draw_line
    echo ""
    if [[ -f /opt/imagitech-xray/core/logs/error.log ]]; then
        tail -50 /opt/imagitech-xray/core/logs/error.log
    else
        journalctl -u xray --no-pager -n 50 2>/dev/null || warn "No logs found."
    fi
    echo ""
    pause
}

validate_config() {
    clear
    draw_line
    echo -e "  ${BOLD}CONFIG VALIDATION${NC}"
    draw_line
    echo ""
    local result
    result=$(xray_validate_config 2>&1)
    if echo "$result" | grep -q "Configuration OK"; then
        success "Configuration is valid!"
    else
        error "Configuration has errors:"
        echo "$result"
    fi
    echo ""
    pause
}

main() {
    while true; do
        draw_header
        read -p "$(echo -e "  ${ORANGE}Select Option : ${NC}")" opt
        case "$opt" in
            1|01) xray_start;   success "Xray started."; pause ;;
            2|02) xray_stop;    success "Xray stopped."; pause ;;
            3|03) xray_restart; success "Xray restarted."; pause ;;
            4|04) clear; xray_status; pause ;;
            5|05) view_xray_logs ;;
            6|06) validate_config ;;
            7|07) bash /opt/imagitech-xray/installers/install_xray.sh update ;;
            8|08) systemctl start nginx;   success "Nginx started."; pause ;;
            9|09) systemctl stop nginx;    success "Nginx stopped."; pause ;;
            10)   systemctl restart nginx; success "Nginx restarted."; pause ;;
            11)   clear; systemctl status nginx --no-pager | head -25; pause ;;
            0|00) return ;;
            *) error "Invalid option"; sleep 1 ;;
        esac
    done
}

main
