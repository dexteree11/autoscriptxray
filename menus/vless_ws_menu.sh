#!/bin/bash
# ==========================================================
# menus/vless_ws_menu.sh — VLESS + WebSocket + TLS
# Imagitech XRAY Suite
# Nginx proxies public port 443 → internal 10001
# ==========================================================
source /opt/imagitech-xray/lib/colors.sh
source /opt/imagitech-xray/lib/ui.sh
source /opt/imagitech-xray/lib/xray_utils.sh
source /opt/imagitech-xray/lib/qr.sh
source /opt/imagitech-xray/lib/port_check.sh

PROTO_LABEL="VLESS + WS + TLS"
INBOUND_TAG="vless-ws-tls"
USERS_PROTO="vless-ws-tls"
LOCAL_PORT=10001          # Nginx → Xray internal port
NGINX_PORT=443            # Public-facing port Nginx listens on
WS_PATH="/vless"

CONF_FILE="/opt/imagitech-xray/core/imagitech-xray.conf"
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

# ==========================================================
# draw_header — Sub-menu box with live status
# ==========================================================
draw_header() {
    local svc
    svc=$(service_status "xray")
    local users_count
    users_count=$(users_count "$USERS_PROTO")

    # Reload conf for DOMAIN each time header is drawn
    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

    clear
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    printf  "${CYAN}  ║${NC}${BOLD}  ✦ %-53s${NC}${CYAN}║${NC}\n" "${PROTO_LABEL}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf  "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Domain   : ${DOMAIN:-not configured}"
    printf  "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Port     : ${NGINX_PORT} (Nginx) → 127.0.0.1:${LOCAL_PORT} (Xray)"
    printf  "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Path     : ${WS_PATH}"
    printf  "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Users    : ${users_count}   Xray: ${svc}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf  "${CYAN}  ║${NC}  ${CYAN}[01]${NC} %-52s${CYAN}║${NC}\n" "Add User"
    printf  "${CYAN}  ║${NC}  ${CYAN}[02]${NC} %-52s${CYAN}║${NC}\n" "Delete User"
    printf  "${CYAN}  ║${NC}  ${CYAN}[03]${NC} %-52s${CYAN}║${NC}\n" "List Users"
    printf  "${CYAN}  ║${NC}  ${CYAN}[04]${NC} %-52s${CYAN}║${NC}\n" "Show User Link + QR"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf  "${CYAN}  ║${NC}  ${MAGENTA}[05]${NC} %-52s${CYAN}║${NC}\n" "Install / Configure Protocol"
    printf  "${CYAN}  ║${NC}  ${MAGENTA}[06]${NC} %-52s${CYAN}║${NC}\n" "Start / Stop / Restart Inbound"
    printf  "${CYAN}  ║${NC}  ${MAGENTA}[07]${NC} %-52s${CYAN}║${NC}\n" "Show Config Info"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf  "${CYAN}  ║${NC}  ${RED}[00]${NC} %-52s${CYAN}║${NC}\n" "Back to Main Menu"
    echo -e "${CYAN}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ==========================================================
# [01] ADD USER
# ==========================================================
add_user() {
    clear
    draw_line
    echo -e "  ${BOLD}ADD USER — ${PROTO_LABEL}${NC}"
    draw_line

    # Prompt for remark
    while true; do
        read -p "$(echo -e "  ${ORANGE}Remark / Account Name: ${NC}")" remark
        [[ -z "$remark" ]] && { error "Remark cannot be empty."; continue; }
        users_remark_exists "$USERS_PROTO" "$remark" && {
            error "Remark '${remark}' already exists. Choose another."
            continue
        }
        break
    done

    # Generate UUID (VLESS uses UUID, no flow needed for WS)
    local uuid
    uuid=$(xray_gen_uuid)
    success "Generated UUID: ${BWHITE}${uuid}${NC}"

    # Persist to user file
    users_add "$USERS_PROTO" "$uuid" "$remark"

    # Inject into Xray config if inbound already exists
    if jq -e --arg t "$INBOUND_TAG" \
        '.inbounds[] | select(.tag == $t)' \
        /usr/local/etc/xray/config.json &>/dev/null; then
        # No flow for WS transport
        xray_add_vless_client "$INBOUND_TAG" "$uuid" "$remark" ""
        xray_reload
    else
        warn "Protocol not yet installed. User saved — install first with option [05]."
    fi

    echo ""
    success "User '${remark}' created successfully!"
    pause
}

# ==========================================================
# [02] DELETE USER
# ==========================================================
del_user() {
    clear
    draw_line
    echo -e "  ${BOLD}DELETE USER — ${PROTO_LABEL}${NC}"
    draw_line

    if ! select_user "$USERS_PROTO"; then
        pause; return
    fi

    confirm "Delete user '${SELECTED_USER_REMARK}'?" || return

    users_del_by_id "$USERS_PROTO" "$SELECTED_USER_ID"
    xray_del_vless_client "$INBOUND_TAG" "$SELECTED_USER_ID"
    xray_reload

    success "User '${SELECTED_USER_REMARK}' deleted."
    pause
}

# ==========================================================
# [03] LIST USERS
# ==========================================================
list_users() {
    clear
    draw_line
    echo -e "  ${BOLD}USERS — ${PROTO_LABEL}${NC}"
    draw_line

    local count
    count=$(users_count "$USERS_PROTO")
    if [[ "$count" -eq 0 ]]; then
        warn "No users found."
        pause; return
    fi

    printf "\n  ${DIM}%-4s  %-28s  %-36s  %-12s${NC}\n" "No." "Remark" "UUID" "Created"
    echo -e "  ${DIM}──────────────────────────────────────────────────────────────────────────────${NC}"
    local i=1
    while IFS='|' read -r id remark date; do
        printf "  ${CYAN}%-4s${NC}  ${BWHITE}%-28s${NC}  ${DIM}%-36s${NC}  ${DIM}%-12s${NC}\n" \
            "$i" "$remark" "$id" "$date"
        ((i++))
    done < "$(users_file "$USERS_PROTO")"
    echo ""
    pause
}

# ==========================================================
# [04] SHOW USER LINK + QR
# ==========================================================
show_user_link() {
    clear
    draw_line
    echo -e "  ${BOLD}SHOW USER LINK — ${PROTO_LABEL}${NC}"
    draw_line

    if ! select_user "$USERS_PROTO"; then
        pause; return
    fi

    # Reload conf to get domain & cert paths
    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

    if [[ -z "$DOMAIN" ]]; then
        error "Domain not configured. Run the certificate/domain setup first."
        pause; return
    fi

    local link
    link=$(build_vless_ws_link \
        "$SELECTED_USER_ID" \
        "$DOMAIN" \
        "$NGINX_PORT" \
        "$WS_PATH" \
        "$SELECTED_USER_REMARK")

    echo ""
    kv "Remark"  "$SELECTED_USER_REMARK"
    kv "UUID"    "$SELECTED_USER_ID"
    kv "Domain"  "$DOMAIN"
    kv "Port"    "$NGINX_PORT"
    kv "Path"    "$WS_PATH"
    kv "TLS"     "yes"

    show_link "Share Link" "$link"
    show_qr "$link"
    pause
}

# ==========================================================
# [05] INSTALL / CONFIGURE PROTOCOL
# ==========================================================
install_protocol() {
    clear
    draw_line
    echo -e "  ${BOLD}INSTALL — ${PROTO_LABEL}${NC}"
    draw_line
    echo ""

    # Reload conf for domain & cert info
    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

    # Warn if domain / certs not configured
    if [[ -z "$DOMAIN" ]] || [[ -z "$CERT_PATH" ]] || [[ -z "$KEY_PATH" ]]; then
        warn "Domain or TLS certificates are not configured."
        warn "Please run the Certificate / Domain setup menu first."
        echo ""
        pause; return
    fi

    if [[ ! -f "$CERT_PATH" ]] || [[ ! -f "$KEY_PATH" ]]; then
        error "Certificate files not found on disk:"
        error "  CERT : ${CERT_PATH}"
        error "  KEY  : ${KEY_PATH}"
        warn "Obtain certificates first via the cert menu."
        echo ""
        pause; return
    fi

    # The inbound listens on 127.0.0.1:LOCAL_PORT; Nginx terminates TLS and proxies here
    info "Xray will listen on 127.0.0.1:${LOCAL_PORT} (Nginx → ${NGINX_PORT})."
    info "Checking for port conflicts on internal port ${LOCAL_PORT}..."
    check_ports_conflict "$LOCAL_PORT" || return

    # Build inbound JSON — security:none because Nginx handles TLS
    local inbound_json
    inbound_json=$(cat <<EOF
{
  "tag": "${INBOUND_TAG}",
  "listen": "127.0.0.1",
  "port": ${LOCAL_PORT},
  "protocol": "vless",
  "settings": {
    "clients": [],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "ws",
    "security": "none",
    "wsSettings": {
      "path": "${WS_PATH}",
      "headers": {
        "Host": "${DOMAIN}"
      }
    }
  },
  "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
}
EOF
)

    local config="/usr/local/etc/xray/config.json"
    if [[ ! -f "$config" ]]; then
        cp /opt/imagitech-xray/configs/xray_base.json "$config"
        mkdir -p /opt/imagitech-xray/core/logs
    fi

    step "Removing existing '${INBOUND_TAG}' inbound (if present)..."
    jq --arg t "$INBOUND_TAG" \
        '.inbounds |= map(select(.tag != $t))' \
        "$config" > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json "$config"

    step "Injecting new inbound..."
    jq --argjson inbound "$inbound_json" \
        '.inbounds += [$inbound]' \
        "$config" > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json "$config"

    # Re-add all existing users
    local uf
    uf=$(users_file "$USERS_PROTO")
    if [[ -f "$uf" && -s "$uf" ]]; then
        step "Re-adding ${BOLD}$(wc -l < "$uf")${NC} existing user(s)..."
        while IFS='|' read -r uid uremark _; do
            xray_add_vless_client "$INBOUND_TAG" "$uid" "$uremark" ""
        done < "$uf"
    fi

    xray_reload
    echo ""
    success "${PROTO_LABEL} installed and configured!"
    kv "Internal Port"  "127.0.0.1:${LOCAL_PORT}"
    kv "Public Port"    "${NGINX_PORT} (via Nginx)"
    kv "WS Path"        "${WS_PATH}"
    kv "Domain"         "${DOMAIN}"
    kv "Cert"           "${CERT_PATH}"
    echo ""
    info "Ensure Nginx proxies wss://${DOMAIN}${WS_PATH} → 127.0.0.1:${LOCAL_PORT}"
    echo ""
    pause
}

# ==========================================================
# [06] START / STOP / RESTART
# ==========================================================
manage_service() {
    clear
    draw_line
    echo -e "  ${BOLD}SERVICE MANAGER — Xray${NC}"
    draw_line
    echo ""
    echo -e "  ${CYAN}[1]${NC} Start Xray"
    echo -e "  ${CYAN}[2]${NC} Stop Xray"
    echo -e "  ${CYAN}[3]${NC} Restart Xray"
    echo -e "  ${CYAN}[4]${NC} View Status"
    echo -e "  ${RED}[0]${NC} Back"
    echo ""
    read -p "$(echo -e "  ${ORANGE}Choose: ${NC}")" ch
    case "$ch" in
        1) xray_start;   success "Xray started." ;;
        2) xray_stop;    success "Xray stopped." ;;
        3) xray_restart; success "Xray restarted." ;;
        4) xray_status ;;
        0) return ;;
        *) error "Invalid option." ;;
    esac
    pause
}

# ==========================================================
# [07] SHOW CONFIG INFO
# ==========================================================
show_config_info() {
    clear
    draw_line
    echo -e "  ${BOLD}CONFIG INFO — ${PROTO_LABEL}${NC}"
    draw_line
    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
    echo ""
    kv "Inbound Tag"    "$INBOUND_TAG"
    kv "Protocol"       "VLESS"
    kv "Transport"      "WebSocket (WS)"
    kv "Security"       "TLS"
    kv "Listen"         "127.0.0.1:${LOCAL_PORT}"
    kv "Public Port"    "${NGINX_PORT} (Nginx proxy)"
    kv "WS Path"        "${WS_PATH}"
    kv "Domain"         "${DOMAIN:-not set}"
    kv "Cert File"      "${CERT_PATH:-not set}"
    kv "Key File"       "${KEY_PATH:-not set}"
    kv "Flow"           "none"
    kv "Users"          "$(users_count "$USERS_PROTO")"
    echo ""
    pause
}

# ==========================================================
# MAIN LOOP
# ==========================================================
main() {
    while true; do
        draw_header
        read -p "$(echo -e "  ${ORANGE}Select Option : ${NC}")" opt
        case "$opt" in
            1|01) add_user ;;
            2|02) del_user ;;
            3|03) list_users ;;
            4|04) show_user_link ;;
            5|05) install_protocol ;;
            6|06) manage_service ;;
            7|07) show_config_info ;;
            0|00) return ;;
            *) error "Invalid option"; sleep 1 ;;
        esac
    done
}

main
