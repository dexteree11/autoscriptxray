#!/bin/bash
# ==========================================================
# menus/settings_menu.sh — Settings & Configuration Viewer
# Imagitech XRAY Suite
# ==========================================================
source /opt/imagitech-xray/lib/colors.sh
source /opt/imagitech-xray/lib/ui.sh
source /opt/imagitech-xray/lib/xray_utils.sh

CONF_FILE="/opt/imagitech-xray/core/imagitech-xray.conf"
XRAY_CONFIG="/usr/local/etc/xray/config.json"

draw_header() {
    clear
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║${NC}${BOLD}${BCYAN}        ✦  SETTINGS & CONFIGURATION  ✦                  ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${CYAN}[01]${NC} %-52s${CYAN}║${NC}\n" "View Panel Configuration"
    printf "${CYAN}  ║${NC}  ${CYAN}[02]${NC} %-52s${CYAN}║${NC}\n" "Edit Panel Configuration"
    printf "${CYAN}  ║${NC}  ${CYAN}[03]${NC} %-52s${CYAN}║${NC}\n" "View Xray config.json"
    printf "${CYAN}  ║${NC}  ${CYAN}[04]${NC} %-52s${CYAN}║${NC}\n" "Show System Info"
    printf "${CYAN}  ║${NC}  ${CYAN}[05]${NC} %-52s${CYAN}║${NC}\n" "Show User Summary (all protocols)"
    printf "${CYAN}  ║${NC}  ${CYAN}[06]${NC} %-52s${CYAN}║${NC}\n" "Reset Xray Config (DANGER)"
    printf "${CYAN}  ║${NC}  ${CYAN}[07]${NC} %-52s${CYAN}║${NC}\n" "Update Panel Scripts"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${RED}[00]${NC} %-52s${CYAN}║${NC}\n" "Back to Main Menu"
    echo -e "${CYAN}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

view_panel_conf() {
    clear; draw_line
    echo -e "  ${BOLD}PANEL CONFIGURATION${NC}"; draw_line; echo ""
    if [[ -f "$CONF_FILE" ]]; then
        while IFS='=' read -r key val; do
            [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
            # Mask CF API key
            if [[ "$key" == *"KEY"* || "$key" == *"key"* ]]; then
                val="****${val: -4}"
            fi
            kv "$key" "$(echo "$val" | tr -d '"')"
        done < "$CONF_FILE"
    else
        warn "Configuration file not found: $CONF_FILE"
    fi
    echo ""
    pause
}

edit_panel_conf() {
    clear; draw_line
    echo -e "  ${BOLD}EDIT PANEL CONFIGURATION${NC}"; draw_line; echo ""
    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

    echo -e "  ${DIM}Leave blank to keep current value${NC}"
    echo ""

    read -p "$(echo -e "  ${ORANGE}Domain [${DOMAIN:-not set}]: ${NC}")" val
    [[ -n "$val" ]] && sed -i "s|^DOMAIN=.*|DOMAIN=\"${val}\"|" "$CONF_FILE" \
        || echo "DOMAIN=\"${val}\"" >> "$CONF_FILE" 2>/dev/null

    read -p "$(echo -e "  ${ORANGE}Cloudflare Email [${CF_Email:-not set}]: ${NC}")" val
    [[ -n "$val" ]] && {
        grep -q "^CF_Email=" "$CONF_FILE" 2>/dev/null \
            && sed -i "s|^CF_Email=.*|CF_Email=\"${val}\"|" "$CONF_FILE" \
            || echo "CF_Email=\"${val}\"" >> "$CONF_FILE"
    }

    read -p "$(echo -e "  ${ORANGE}Cloudflare API Key [****]: ${NC}")" val
    [[ -n "$val" ]] && {
        grep -q "^CF_Key=" "$CONF_FILE" 2>/dev/null \
            && sed -i "s|^CF_Key=.*|CF_Key=\"${val}\"|" "$CONF_FILE" \
            || echo "CF_Key=\"${val}\"" >> "$CONF_FILE"
    }

    success "Configuration saved."
    pause
}

view_xray_config() {
    clear; draw_line
    echo -e "  ${BOLD}XRAY config.json${NC}"; draw_line; echo ""
    if [[ -f "$XRAY_CONFIG" ]]; then
        jq . "$XRAY_CONFIG" 2>/dev/null | head -80
        echo ""
        warn "Showing first 80 lines. Full path: ${XRAY_CONFIG}"
    else
        warn "Xray config not found: ${XRAY_CONFIG}"
    fi
    echo ""
    pause
}

show_system_info() {
    clear; draw_line
    echo -e "  ${BOLD}SYSTEM INFORMATION${NC}"; draw_line; echo ""
    get_server_info
    kv "Server IP"      "${SERVER_IP:-N/A}"
    kv "Country"        "${SERVER_COUNTRY:-N/A}"
    kv "ISP"            "${SERVER_ISP:-N/A}"
    kv "OS"             "$(grep -w PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"
    kv "Kernel"         "$(uname -r)"
    kv "Uptime"         "$(uptime -p | sed 's/up //')"
    kv "CPU Cores"      "$(nproc)"
    kv "RAM"            "$(free -h | awk 'NR==2{print $3"/"$2}')"
    kv "Disk"           "$(df -h / | awk 'NR==2{print $3"/"$2" ("$5" used)"}')"
    kv "Xray Version"   "$(get_xray_version)"
    kv "Nginx Version"  "$(nginx -v 2>&1 | grep -oP 'nginx/[\d.]+')"
    kv "Panel Path"     "/opt/imagitech-xray"
    kv "Xray Config"    "$XRAY_CONFIG"
    echo ""
    pause
}

show_user_summary() {
    clear; draw_line
    echo -e "  ${BOLD}USER SUMMARY — ALL PROTOCOLS${NC}"; draw_line; echo ""

    local protos=(
        "vless-reality-xhttp:VLESS+REALITY+xHTTP"
        "vless-reality-tcp:VLESS+REALITY+TCP"
        "vless-ws-tls:VLESS+WS+TLS"
        "trojan-ws-tls:Trojan+WS+TLS"
        "trojan-tcp-tls:Trojan+TCP+TLS"
        "vmess-ws-tls:VMess+WS+TLS"
    )

    local total=0
    for entry in "${protos[@]}"; do
        local proto label count
        proto="${entry%%:*}"
        label="${entry##*:}"
        count=$(users_count "$proto")
        printf "  ${CYAN}%-28s${NC} ${BWHITE}%d users${NC}\n" "$label" "$count"
        total=$((total + count))
    done

    echo ""
    echo -e "  ${DIM}─────────────────────────────────────────────────────────${NC}"
    printf "  ${BOLD}%-28s ${BGREEN}%d users total${NC}\n" "TOTAL" "$total"
    echo ""
    pause
}

reset_xray_config() {
    clear; draw_line
    echo -e "  ${BRED}${BOLD}DANGER: RESET XRAY CONFIG${NC}"; draw_line; echo ""
    warn "This will WIPE all inbounds from the Xray config.json!"
    warn "All protocol configurations will be lost (user files are preserved)."
    echo ""
    confirm "Are you absolutely sure you want to reset?" || return
    confirm "SECOND CONFIRMATION — really reset Xray config?" || return

    cp /opt/imagitech-xray/configs/xray_base.json "$XRAY_CONFIG"
    xray_reload
    success "Xray config reset to base template."
    warn "You will need to reinstall each protocol from their menus."
    pause
}

update_panel() {
    clear; draw_line
    echo -e "  ${BOLD}UPDATE PANEL SCRIPTS${NC}"; draw_line; echo ""

    local REPO_URL="https://raw.githubusercontent.com/dexteree11/autoscriptxray/main"
    info "Fetching latest scripts from GitHub..."

    local scripts=(
        "menus/main_menu.sh"
        "menus/vless_reality_menu.sh"
        "menus/vless_ws_menu.sh"
        "menus/trojan_ws_menu.sh"
        "menus/trojan_tcp_menu.sh"
        "menus/vmess_ws_menu.sh"
        "menus/service_menu.sh"
        "menus/cert_menu.sh"
        "menus/nginx_menu.sh"
        "menus/settings_menu.sh"
        "lib/colors.sh"
        "lib/ui.sh"
        "lib/xray_utils.sh"
        "lib/qr.sh"
        "lib/port_check.sh"
        "installers/install_xray.sh"
        "installers/install_nginx.sh"
        "installers/install_acme.sh"
    )

    local fail=0
    for script in "${scripts[@]}"; do
        local dest="/opt/imagitech-xray/${script}"
        local http_code
        http_code=$(curl -sL -o "$dest.tmp" -w "%{http_code}" "${REPO_URL}/${script}")
        if [[ "$http_code" == "200" ]]; then
            mv "$dest.tmp" "$dest"
            chmod +x "$dest"
            step "Updated: $script"
        else
            rm -f "$dest.tmp"
            error "Failed: $script (HTTP ${http_code})"
            fail=1
        fi
    done

    echo ""
    if [[ $fail -eq 0 ]]; then
        success "All scripts updated successfully!"
    else
        warn "Some scripts failed to update. Check your GitHub repo structure."
    fi
    pause
}

main() {
    while true; do
        draw_header
        read -p "$(echo -e "  ${ORANGE}Select Option : ${NC}")" opt
        case "$opt" in
            1|01) view_panel_conf ;;
            2|02) edit_panel_conf ;;
            3|03) view_xray_config ;;
            4|04) show_system_info ;;
            5|05) show_user_summary ;;
            6|06) reset_xray_config ;;
            7|07) update_panel ;;
            0|00) return ;;
            *) error "Invalid option"; sleep 1 ;;
        esac
    done
}

main
