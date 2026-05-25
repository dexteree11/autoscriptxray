#!/bin/bash
# ==========================================================
# menus/main_menu.sh — Imagitech XRAY Main Dashboard
# Imagitech XRAY Suite
# ==========================================================
source /opt/imagitech-xray/lib/colors.sh
source /opt/imagitech-xray/lib/ui.sh
source /opt/imagitech-xray/lib/xray_utils.sh

MENU_DIR="/opt/imagitech-xray/menus"

# --- Root check ---
if [[ "${EUID}" -ne 0 ]]; then
    echo -e "\033[0;31m[FATAL] You must be root to access the Imagitech XRAY Panel.\033[0m"
    echo -e "\033[0;33mType: sudo su -\033[0m"
    exit 1
fi

# --- Live system stats ---
get_stats() {
    OS_INFO=$(grep -w PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    UPTIME_STR=$(uptime -p 2>/dev/null | sed 's/up //' || echo "N/A")
    RAM_USED=$(free -m 2>/dev/null | awk 'NR==2{print $3}')
    RAM_TOTAL=$(free -m 2>/dev/null | awk 'NR==2{print $2}')
    CPU_USAGE=$(top -bn1 2>/dev/null | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{printf "%.1f%%", 100-$1}')
    XRAY_VER=$(get_xray_version)
    get_server_info  # sets SERVER_IP, SERVER_COUNTRY, SERVER_ISP
}

# --- Check if inbound tag is configured (returns ON/OFF string) ---
proto_status() {
    local tag="$1"
    if [[ -f /usr/local/etc/xray/config.json ]]; then
        if jq -e --arg t "$tag" '.inbounds[] | select(.tag == $t)' /usr/local/etc/xray/config.json &>/dev/null; then
            echo -e "${BGREEN}[ON] ${NC}"
        else
            echo -e "${BRED}[OFF]${NC}"
        fi
    else
        echo -e "${BRED}[OFF]${NC}"
    fi
}

draw_main_menu() {
    get_stats

    local xray_svc
    xray_svc=$(service_status "xray")
    local nginx_svc
    nginx_svc=$(service_status "nginx")

    local s1 s2 s3 s4 s5 s6
    s1=$(proto_status "vless-reality-xhttp")
    s2=$(proto_status "vless-reality-tcp")
    s3=$(proto_status "vless-ws-tls")
    s4=$(proto_status "trojan-ws-tls")
    s5=$(proto_status "trojan-tcp-tls")
    s6=$(proto_status "vmess-ws-tls")

    clear
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║${NC}${BOLD}${BCYAN}          ✦  IMAGITECH XRAY PANEL  v1.0  ✦              ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  IP  : ${SERVER_IP:-N/A}   ${SERVER_COUNTRY:-}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  ISP : ${SERVER_ISP:-N/A}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  OS  : ${OS_INFO:-N/A}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Up  : ${UPTIME_STR}   CPU: ${CPU_USAGE}   RAM: ${RAM_USED}/${RAM_TOTAL} MB"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Xray: v${XRAY_VER}   Service: ${xray_svc}   Nginx: ${nginx_svc}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}  ║${NC}  ${BOLD}── XRAY PROTOCOLS ──────────────────────────────────${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${CYAN}[01]${NC} %-42s %s  ${CYAN}║${NC}\n" "VLESS + REALITY + xHTTP" "${s1}"
    printf "${CYAN}  ║${NC}  ${CYAN}[02]${NC} %-42s %s  ${CYAN}║${NC}\n" "VLESS + REALITY + TCP" "${s2}"
    printf "${CYAN}  ║${NC}  ${CYAN}[03]${NC} %-42s %s  ${CYAN}║${NC}\n" "VLESS + WS + TLS" "${s3}"
    printf "${CYAN}  ║${NC}  ${CYAN}[04]${NC} %-42s %s  ${CYAN}║${NC}\n" "Trojan + WS + TLS" "${s4}"
    printf "${CYAN}  ║${NC}  ${CYAN}[05]${NC} %-42s %s  ${CYAN}║${NC}\n" "Trojan + TCP + TLS" "${s5}"
    printf "${CYAN}  ║${NC}  ${CYAN}[06]${NC} %-42s %s  ${CYAN}║${NC}\n" "VMess + WS + TLS" "${s6}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}  ║${NC}  ${BOLD}── MANAGEMENT ──────────────────────────────────────${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${MAGENTA}[07]${NC} %-54s${CYAN}║${NC}\n" "Xray Service Manager"
    printf "${CYAN}  ║${NC}  ${MAGENTA}[08]${NC} %-54s${CYAN}║${NC}\n" "Certificate Manager (acme.sh + Cloudflare)"
    printf "${CYAN}  ║${NC}  ${MAGENTA}[09]${NC} %-54s${CYAN}║${NC}\n" "Nginx Manager"
    printf "${CYAN}  ║${NC}  ${MAGENTA}[10]${NC} %-54s${CYAN}║${NC}\n" "Settings & Configuration"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${RED}[00]${NC} %-54s${CYAN}║${NC}\n" "Exit"
    echo -e "${CYAN}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

main() {
    while true; do
        draw_main_menu
        read -p "$(echo -e "  ${ORANGE}Select Option : ${NC}")" opt

        case "$opt" in
            1|01) bash "${MENU_DIR}/vless_reality_menu.sh" xhttp ;;
            2|02) bash "${MENU_DIR}/vless_reality_menu.sh" tcp ;;
            3|03) bash "${MENU_DIR}/vless_ws_menu.sh" ;;
            4|04) bash "${MENU_DIR}/trojan_ws_menu.sh" ;;
            5|05) bash "${MENU_DIR}/trojan_tcp_menu.sh" ;;
            6|06) bash "${MENU_DIR}/vmess_ws_menu.sh" ;;
            7|07) bash "${MENU_DIR}/service_menu.sh" ;;
            8|08) bash "${MENU_DIR}/cert_menu.sh" ;;
            9|09) bash "${MENU_DIR}/nginx_menu.sh" ;;
            10)   bash "${MENU_DIR}/settings_menu.sh" ;;
            0|00)
                echo -e "\n  ${CYAN}Goodbye! — Imagitech XRAY Panel${NC}\n"
                exit 0
                ;;
            *)
                error "Invalid option. Please select a valid menu item."
                sleep 1
                ;;
        esac
    done
}

main
