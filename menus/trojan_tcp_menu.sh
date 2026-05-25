#!/bin/bash
# ==========================================================
# menus/trojan_tcp_menu.sh — Trojan + TCP + TLS
# Imagitech XRAY Suite
# Direct TCP — no Nginx needed; listens on 0.0.0.0
# Default port 8443 (avoids conflict with WS on 443)
# Users are identified by password (not UUID)
# ==========================================================
source /opt/imagitech-xray/lib/colors.sh
source /opt/imagitech-xray/lib/ui.sh
source /opt/imagitech-xray/lib/xray_utils.sh
source /opt/imagitech-xray/lib/qr.sh
source /opt/imagitech-xray/lib/port_check.sh

PROTO_LABEL="Trojan + TCP + TLS"
INBOUND_TAG="trojan-tcp-tls"
USERS_PROTO="trojan-tcp-tls"

CONF_FILE="/opt/imagitech-xray/core/imagitech-xray.conf"
PORT_CACHE="/opt/imagitech-xray/core/keys/trojan_tcp.env"

[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

# Load or initialise saved port
load_tcp_config() {
    if [[ -f "$PORT_CACHE" ]]; then
        source "$PORT_CACHE"
    else
        TROJAN_TCP_PORT=""
    fi
}

save_tcp_config() {
    mkdir -p "$(dirname "$PORT_CACHE")"
    echo "TROJAN_TCP_PORT=\"${TROJAN_TCP_PORT}\"" > "$PORT_CACHE"
}

# ==========================================================
# draw_header — Sub-menu box with live status
# ==========================================================
draw_header() {
    load_tcp_config
    local svc
    svc=$(service_status "xray")
    local users_count
    users_count=$(users_count "$USERS_PROTO")
    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

    clear
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    printf  "${CYAN}  ║${NC}${BOLD}  ✦ %-53s${NC}${CYAN}║${NC}\n" "${PROTO_LABEL}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf  "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Domain   : ${DOMAIN:-not configured}"
    printf  "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Port     : ${TROJAN_TCP_PORT:-not configured} (direct TCP, no Nginx)"
    printf  "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Listen   : 0.0.0.0 (with fallback → :80)"
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

    # Generate Trojan password
    local password
    password=$(gen_trojan_password)
    success "Generated Password: ${BWHITE}${password}${NC}"

    # Persist to user file
    users_add "$USERS_PROTO" "$password" "$remark"

    # Inject into Xray config if inbound already exists
    if jq -e --arg t "$INBOUND_TAG" \
        '.inbounds[] | select(.tag == $t)' \
        /usr/local/etc/xray/config.json &>/dev/null; then
        xray_add_trojan_client "$INBOUND_TAG" "$password" "$remark"
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
    xray_del_trojan_client "$INBOUND_TAG" "$SELECTED_USER_ID"
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

    printf "\n  ${DIM}%-4s  %-28s  %-28s  %-12s${NC}\n" "No." "Remark" "Password" "Created"
    echo -e "  ${DIM}──────────────────────────────────────────────────────────────────────────────${NC}"
    local i=1
    while IFS='|' read -r id remark date; do
        printf "  ${CYAN}%-4s${NC}  ${BWHITE}%-28s${NC}  ${DIM}%-28s${NC}  ${DIM}%-12s${NC}\n" \
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

    [[ -f "$CONF_FILE" ]] && source "$CONF_FILE"
    load_tcp_config

    if [[ -z "$DOMAIN" ]]; then
        error "Domain not configured. Run the certificate/domain setup first."
        pause; return
    fi

    if [[ -z "$TROJAN_TCP_PORT" ]]; then
        error "Protocol not configured. Install it first with option [05]."
        pause; return
    fi

    local link
    link=$(build_trojan_tcp_link \
        "$SELECTED_USER_ID" \
        "$DOMAIN" \
        "$TROJAN_TCP_PORT" \
        "$SELECTED_USER_REMARK")

    echo ""
    kv "Remark"    "$SELECTED_USER_REMARK"
    kv "Password"  "$SELECTED_USER_ID"
    kv "Domain"    "$DOMAIN"
    kv "Port"      "$TROJAN_TCP_PORT"
    kv "TLS"       "yes"
    kv "Fallback"  "→ port 80"

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

    # Port selection — default 8443 to avoid collision with Nginx 443
    read -p "$(echo -e "  ${ORANGE}Listening port [default: 8443]: ${NC}")" port_input
    TROJAN_TCP_PORT="${port_input:-8443}"

    check_ports_conflict "$TROJAN_TCP_PORT" || return

    save_tcp_config

    # Build inbound JSON with TCP fallback to port 80
    local inbound_json
    inbound_json=$(cat <<EOF
{
  "tag": "${INBOUND_TAG}",
  "listen": "0.0.0.0",
  "port": ${TROJAN_TCP_PORT},
  "protocol": "trojan",
  "settings": {
    "clients": [],
    "fallbacks": [
      { "dest": 80 }
    ]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "tls",
    "tlsSettings": {
      "serverName": "${DOMAIN}",
      "certificates": [
        {
          "certificateFile": "${CERT_PATH}",
          "keyFile": "${KEY_PATH}"
        }
      ]
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
        while IFS='|' read -r passwd uremark _; do
            xray_add_trojan_client "$INBOUND_TAG" "$passwd" "$uremark"
        done < "$uf"
    fi

    xray_reload
    echo ""
    success "${PROTO_LABEL} installed and configured!"
    kv "Port"      "${TROJAN_TCP_PORT} (direct TCP)"
    kv "Listen"    "0.0.0.0"
    kv "Fallback"  "→ port 80"
    kv "Domain"    "${DOMAIN}"
    kv "Cert"      "${CERT_PATH}"
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
    load_tcp_config
    echo ""
    kv "Inbound Tag"    "$INBOUND_TAG"
    kv "Protocol"       "Trojan"
    kv "Transport"      "TCP"
    kv "Security"       "TLS"
    kv "Listen"         "0.0.0.0:${TROJAN_TCP_PORT:-not set}"
    kv "Fallback"       "→ port 80"
    kv "Domain"         "${DOMAIN:-not set}"
    kv "Cert File"      "${CERT_PATH:-not set}"
    kv "Key File"       "${KEY_PATH:-not set}"
    kv "Auth Type"      "Password"
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
