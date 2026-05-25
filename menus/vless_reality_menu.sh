#!/bin/bash
# ==========================================================
# menus/vless_reality_menu.sh — VLESS + REALITY (xHTTP / TCP)
# Imagitech XRAY Suite
# Usage: vless_reality_menu.sh [xhttp|tcp]
# ==========================================================
source /opt/imagitech-xray/lib/colors.sh
source /opt/imagitech-xray/lib/ui.sh
source /opt/imagitech-xray/lib/xray_utils.sh
source /opt/imagitech-xray/lib/qr.sh
source /opt/imagitech-xray/lib/port_check.sh

TRANSPORT="${1:-xhttp}"   # xhttp or tcp
if [[ "$TRANSPORT" == "tcp" ]]; then
    PROTO_LABEL="VLESS + REALITY + TCP"
    INBOUND_TAG="vless-reality-tcp"
    USERS_PROTO="vless-reality-tcp"
    DEFAULT_PORT=443
    FLOW="xtls-rprx-vision"
else
    PROTO_LABEL="VLESS + REALITY + xHTTP"
    INBOUND_TAG="vless-reality-xhttp"
    USERS_PROTO="vless-reality-xhttp"
    DEFAULT_PORT=443
    FLOW=""
fi

CONF_FILE="/opt/imagitech-xray/core/imagitech-xray.conf"
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

REALITY_KEYS_FILE="/opt/imagitech-xray/core/keys/reality_${TRANSPORT}.env"

# --- Load or reset REALITY keys ---
load_reality_keys() {
    REALITY_PRIVATE_KEY=""
    REALITY_PUBLIC_KEY=""
    REALITY_SHORT_ID=""
    REALITY_SNI=""
    REALITY_PORT=""
    REALITY_PATH=""
    if [[ -f "$REALITY_KEYS_FILE" ]]; then
        source "$REALITY_KEYS_FILE"
    fi
}

save_reality_keys() {
    mkdir -p "$(dirname "$REALITY_KEYS_FILE")"
    cat > "$REALITY_KEYS_FILE" <<EOF
REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY}"
REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY}"
REALITY_SHORT_ID="${REALITY_SHORT_ID}"
REALITY_SNI="${REALITY_SNI}"
REALITY_PORT="${REALITY_PORT}"
REALITY_PATH="${REALITY_PATH}"
EOF
}

# --- Draw sub-menu header ---
draw_header() {
    load_reality_keys
    local svc
    svc=$(service_status "xray")
    local ucount
    ucount=$(users_count "$USERS_PROTO")
    clear
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    printf "${CYAN}  ║${NC}${BOLD}  ✦ %-53s${NC}${CYAN}║${NC}\n" "${PROTO_LABEL}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Port    : ${REALITY_PORT:-not configured}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  SNI     : ${REALITY_SNI:-not configured}"
    if [[ "$TRANSPORT" == "xhttp" ]]; then
        printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Path    : ${REALITY_PATH:-not configured}"
    fi
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Users   : ${ucount}   Xray: ${svc}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${CYAN}[01]${NC} %-52s${CYAN}║${NC}\n" "Add User"
    printf "${CYAN}  ║${NC}  ${CYAN}[02]${NC} %-52s${CYAN}║${NC}\n" "Delete User"
    printf "${CYAN}  ║${NC}  ${CYAN}[03]${NC} %-52s${CYAN}║${NC}\n" "List Users"
    printf "${CYAN}  ║${NC}  ${CYAN}[04]${NC} %-52s${CYAN}║${NC}\n" "Show User Link + QR"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${MAGENTA}[05]${NC} %-52s${CYAN}║${NC}\n" "Install / Configure Protocol"
    printf "${CYAN}  ║${NC}  ${MAGENTA}[06]${NC} %-52s${CYAN}║${NC}\n" "Start / Stop / Restart Xray"
    printf "${CYAN}  ║${NC}  ${MAGENTA}[07]${NC} %-52s${CYAN}║${NC}\n" "Show Config Info"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  ${RED}[00]${NC} %-52s${CYAN}║${NC}\n" "Back to Main Menu"
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

    while true; do
        read -p "$(echo -e "  ${ORANGE}Remark / Account Name: ${NC}")" remark
        [[ -z "$remark" ]] && { error "Remark cannot be empty."; continue; }
        users_remark_exists "$USERS_PROTO" "$remark" && {
            error "Remark '${remark}' already exists. Choose another."
            continue
        }
        break
    done

    local uuid
    uuid=$(xray_gen_uuid)
    success "Generated UUID: ${BWHITE}${uuid}${NC}"

    users_add "$USERS_PROTO" "$uuid" "$remark"

    if jq -e --arg t "$INBOUND_TAG" '.inbounds[] | select(.tag == $t)' /usr/local/etc/xray/config.json &>/dev/null; then
        xray_add_vless_client "$INBOUND_TAG" "$uuid" "$remark" "$FLOW"
        xray_reload
    else
        warn "Protocol not yet installed. User saved — install it first (option [05])."
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

    load_reality_keys

    if [[ -z "$REALITY_PUBLIC_KEY" ]]; then
        error "Protocol not configured. Install it first with option [05]."
        pause; return
    fi

    local ip
    ip=$(get_server_ip)

    local link
    if [[ "$TRANSPORT" == "tcp" ]]; then
        link=$(build_vless_reality_tcp_link \
            "$SELECTED_USER_ID" "$ip" "$REALITY_PORT" \
            "$REALITY_PUBLIC_KEY" "$REALITY_SHORT_ID" "$REALITY_SNI" \
            "$SELECTED_USER_REMARK")
    else
        link=$(build_vless_reality_xhttp_link \
            "$SELECTED_USER_ID" "$ip" "$REALITY_PORT" \
            "$REALITY_PUBLIC_KEY" "$REALITY_SHORT_ID" "$REALITY_SNI" \
            "$REALITY_PATH" "$SELECTED_USER_REMARK")
    fi

    echo ""
    kv "Remark"  "$SELECTED_USER_REMARK"
    kv "UUID"    "$SELECTED_USER_ID"
    kv "IP"      "$ip"
    kv "Port"    "$REALITY_PORT"
    kv "SNI"     "$REALITY_SNI"
    if [[ "$TRANSPORT" == "xhttp" ]]; then
        kv "Path"    "$REALITY_PATH"
    fi
    kv "PubKey"  "$REALITY_PUBLIC_KEY"
    kv "ShortID" "$REALITY_SHORT_ID"

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

    # Port
    read -p "$(echo -e "  ${ORANGE}Listening port [default: ${DEFAULT_PORT}]: ${NC}")" port
    REALITY_PORT="${port:-${DEFAULT_PORT}}"

    check_ports_conflict "$REALITY_PORT" || return

    # SNI selection
    echo ""
    info "Choose the REALITY SNI (must be a real domain with TLS 1.3, NOT behind CDN)."
    echo ""
    echo -e "  ${CYAN}[1]${NC} www.amazon.com"
    echo -e "  ${CYAN}[2]${NC} www.microsoft.com"
    echo -e "  ${CYAN}[3]${NC} www.apple.com"
    echo -e "  ${CYAN}[4]${NC} www.cloudflare.com"
    echo -e "  ${CYAN}[5]${NC} dl.google.com"
    echo -e "  ${CYAN}[6]${NC} Enter custom SNI"
    echo ""
    read -p "$(echo -e "  ${ORANGE}Choose [1-6]: ${NC}")" sni_choice
    case "$sni_choice" in
        1) REALITY_SNI="www.amazon.com" ;;
        2) REALITY_SNI="www.microsoft.com" ;;
        3) REALITY_SNI="www.apple.com" ;;
        4) REALITY_SNI="www.cloudflare.com" ;;
        5) REALITY_SNI="dl.google.com" ;;
        6|*)
            read -p "$(echo -e "  ${ORANGE}Enter custom SNI: ${NC}")" REALITY_SNI
            ;;
    esac

    [[ -z "$REALITY_SNI" ]] && { error "SNI cannot be empty."; pause; return; }

    # Generate X25519 keypair
    step "Generating X25519 key pair..."
    local keypair
    keypair=$(xray_gen_x25519)
    REALITY_PRIVATE_KEY=$(echo "$keypair" | grep -i "private" | awk '{print $NF}')
    REALITY_PUBLIC_KEY=$(echo "$keypair" | grep -i "public" | awk '{print $NF}')
    REALITY_SHORT_ID=$(openssl rand -hex 8)

    if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" ]]; then
        error "Failed to generate X25519 keys. Is Xray installed?"
        pause; return
    fi

    success "Private Key : ${REALITY_PRIVATE_KEY}"
    success "Public Key  : ${REALITY_PUBLIC_KEY}"
    success "Short ID    : ${REALITY_SHORT_ID}"

    # Generate random path for xHTTP
    if [[ "$TRANSPORT" == "xhttp" ]]; then
        REALITY_PATH="/$(openssl rand -hex 6)"
        info "xHTTP Path  : ${REALITY_PATH}"
    else
        REALITY_PATH=""
    fi

    save_reality_keys

    # Build inbound JSON — exactly matching the working template
    local inbound_json
    if [[ "$TRANSPORT" == "tcp" ]]; then
        inbound_json=$(cat <<EOF
{
  "tag": "${INBOUND_TAG}",
  "listen": "0.0.0.0",
  "port": ${REALITY_PORT},
  "protocol": "vless",
  "settings": {
    "clients": [],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "show": false,
      "dest": "${REALITY_SNI}:443",
      "xver": 0,
      "serverNames": ["${REALITY_SNI}"],
      "privateKey": "${REALITY_PRIVATE_KEY}",
      "shortIds": ["${REALITY_SHORT_ID}"]
    },
    "tcpSettings": {
      "header": { "type": "none" }
    }
  },
  "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"] }
}
EOF
)
    else
        inbound_json=$(cat <<EOF
{
  "tag": "${INBOUND_TAG}",
  "listen": "0.0.0.0",
  "port": ${REALITY_PORT},
  "protocol": "vless",
  "settings": {
    "clients": [],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "xhttp",
    "security": "reality",
    "xhttpSettings": {
      "path": "${REALITY_PATH}",
      "mode": "auto"
    },
    "realitySettings": {
      "show": false,
      "dest": "${REALITY_SNI}:443",
      "xver": 0,
      "serverNames": ["${REALITY_SNI}"],
      "privateKey": "${REALITY_PRIVATE_KEY}",
      "shortIds": ["${REALITY_SHORT_ID}"]
    }
  },
  "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"] }
}
EOF
)
    fi

    local config="/usr/local/etc/xray/config.json"
    if [[ ! -f "$config" ]]; then
        cp /opt/imagitech-xray/configs/xray_base.json "$config"
        mkdir -p /opt/imagitech-xray/core/logs
    fi

    step "Removing old '${INBOUND_TAG}' inbound..."
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
        step "Re-adding $(wc -l < "$uf") existing user(s)..."
        while IFS='|' read -r uid uremark _; do
            xray_add_vless_client "$INBOUND_TAG" "$uid" "$uremark" "$FLOW"
        done < "$uf"
    fi

    xray_reload
    echo ""
    success "${PROTO_LABEL} installed and configured!"
    kv "Port"     "$REALITY_PORT"
    kv "SNI"      "$REALITY_SNI"
    if [[ "$TRANSPORT" == "xhttp" ]]; then
        kv "Path"     "$REALITY_PATH"
    fi
    kv "PubKey"   "$REALITY_PUBLIC_KEY"
    kv "ShortID"  "$REALITY_SHORT_ID"
    echo ""
    info "Use option [01] to add users, then [04] to get the share link."
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
    echo -e "  ${CYAN}[5]${NC} View Logs (last 30)"
    echo -e "  ${RED}[0]${NC} Back"
    echo ""
    read -p "$(echo -e "  ${ORANGE}Choose: ${NC}")" ch
    case "$ch" in
        1) xray_start;   success "Xray started." ;;
        2) xray_stop;    success "Xray stopped." ;;
        3) xray_restart; success "Xray restarted." ;;
        4) clear; xray_status ;;
        5)
            clear; draw_line
            echo -e "  ${BOLD}XRAY LOGS${NC}"; draw_line; echo ""
            if [[ -f /opt/imagitech-xray/core/logs/error.log ]]; then
                tail -30 /opt/imagitech-xray/core/logs/error.log
            else
                journalctl -u xray --no-pager -n 30 2>/dev/null
            fi
            ;;
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
    load_reality_keys
    echo ""
    kv "Inbound Tag"    "$INBOUND_TAG"
    kv "Transport"      "$TRANSPORT"
    kv "Port"           "${REALITY_PORT:-not set}"
    kv "SNI"            "${REALITY_SNI:-not set}"
    if [[ "$TRANSPORT" == "xhttp" ]]; then
        kv "Path"           "${REALITY_PATH:-not set}"
    fi
    kv "Private Key"    "${REALITY_PRIVATE_KEY:+****${REALITY_PRIVATE_KEY: -6}}"
    kv "Public Key"     "${REALITY_PUBLIC_KEY:-not set}"
    kv "Short ID"       "${REALITY_SHORT_ID:-not set}"
    kv "Flow"           "${FLOW:-none (xHTTP)}"
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
