#!/bin/bash
# ==========================================================
# lib/xray_utils.sh — Core XRAY Logic
# Imagitech XRAY Suite
# ==========================================================
source /opt/imagitech-xray/lib/colors.sh 2>/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
source /opt/imagitech-xray/lib/ui.sh 2>/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

XRAY_CONFIG="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
USERS_DIR="/opt/imagitech-xray/core/users"
CONF_FILE="/opt/imagitech-xray/core/imagitech-xray.conf"

# Load main config if it exists
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

# ==========================================================
# CREDENTIAL GENERATION
# ==========================================================

# Generate a new UUID
xray_gen_uuid() {
    if [[ -x "$XRAY_BIN" ]]; then
        "$XRAY_BIN" uuid 2>/dev/null
    else
        cat /proc/sys/kernel/random/uuid 2>/dev/null || \
        python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null
    fi
}

# Generate X25519 keypair for REALITY
# Outputs: two lines: private_key\npublic_key
xray_gen_x25519() {
    if [[ -x "$XRAY_BIN" ]]; then
        "$XRAY_BIN" x25519 2>/dev/null
    else
        error "Xray binary not found. Cannot generate X25519 keys."
        return 1
    fi
}

# Parse private key from xray x25519 output
get_private_key() {
    xray_gen_x25519 | grep -i "private" | awk '{print $NF}'
}

# Parse public key from xray x25519 output
get_public_key_from_private() {
    local private_key="$1"
    "$XRAY_BIN" x25519 -i "$private_key" 2>/dev/null | grep -i "public" | awk '{print $NF}'
}

# Generate a random short ID (8 hex chars)
gen_short_id() {
    openssl rand -hex 8 2>/dev/null || head -c 4 /dev/urandom | xxd -p
}

# Generate a random Trojan password
gen_trojan_password() {
    openssl rand -base64 18 2>/dev/null | tr -d '+/=' | head -c 24
}

# ==========================================================
# USER FILE MANAGEMENT (flat-file, per protocol)
# Format per line: UUID|REMARK|CREATED_DATE
# ==========================================================

# Get the user file path for a protocol
users_file() {
    local proto="$1"   # e.g. vless-reality, trojan-ws, vmess-ws
    echo "${USERS_DIR}/${proto}.users"
}

# Add a user entry to the protocol's user file
users_add() {
    local proto="$1"
    local id="$2"      # UUID or password
    local remark="$3"
    local file
    file=$(users_file "$proto")
    mkdir -p "$USERS_DIR"
    local created
    created=$(date +"%Y-%m-%d")
    echo "${id}|${remark}|${created}" >> "$file"
}

# Remove a user entry by remark
users_del_by_remark() {
    local proto="$1"
    local remark="$2"
    local file
    file=$(users_file "$proto")
    [[ -f "$file" ]] || { warn "No users file for ${proto}"; return 1; }
    sed -i "/|${remark}|/d" "$file"
}

# Remove a user entry by ID (UUID/password)
users_del_by_id() {
    local proto="$1"
    local id="$2"
    local file
    file=$(users_file "$proto")
    [[ -f "$file" ]] || { warn "No users file for ${proto}"; return 1; }
    sed -i "/^${id}|/d" "$file"
}

# List all users for a protocol
users_list() {
    local proto="$1"
    local file
    file=$(users_file "$proto")
    [[ -f "$file" ]] || return 0
    cat "$file"
}

# Count users for a protocol
users_count() {
    local proto="$1"
    local file
    file=$(users_file "$proto")
    [[ -f "$file" ]] || { echo 0; return; }
    wc -l < "$file"
}

# Check if a remark already exists
users_remark_exists() {
    local proto="$1"
    local remark="$2"
    local file
    file=$(users_file "$proto")
    [[ -f "$file" ]] && grep -q "|${remark}|" "$file"
}

# Get ID (UUID/password) by remark
users_get_id_by_remark() {
    local proto="$1"
    local remark="$2"
    local file
    file=$(users_file "$proto")
    [[ -f "$file" ]] || return 1
    grep "|${remark}|" "$file" | cut -d'|' -f1
}

# Interactive user picker
# Sets global $SELECTED_USER_ID and $SELECTED_USER_REMARK
select_user() {
    local proto="$1"
    local file
    file=$(users_file "$proto")

    if [[ ! -f "$file" ]] || [[ ! -s "$file" ]]; then
        warn "No users found for protocol: $proto"
        return 1
    fi

    echo ""
    info "Select a user:"
    echo ""
    local i=1
    local -a ids remarks dates
    while IFS='|' read -r id remark date; do
        ids+=("$id")
        remarks+=("$remark")
        dates+=("$date")
        printf "  ${CYAN}[%02d]${NC}  %-24s  ${DIM}%s${NC}\n" "$i" "$remark" "$date"
        ((i++))
    done < "$file"
    echo ""
    read -p "$(echo -e "  ${ORANGE}Select [1-$((i-1))]: ${NC}")" sel

    if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel >= i )); then
        error "Invalid selection."
        return 1
    fi

    SELECTED_USER_ID="${ids[$((sel-1))]}"
    SELECTED_USER_REMARK="${remarks[$((sel-1))]}"
    return 0
}

# ==========================================================
# XRAY CONFIG FILE MANIPULATION (using jq)
# ==========================================================

# Validate config
xray_validate_config() {
    if [[ -x "$XRAY_BIN" ]]; then
        "$XRAY_BIN" -test -config "$XRAY_CONFIG" 2>&1
        return $?
    fi
    error "Xray binary not found."
    return 1
}

# Add a VLESS client to a specific inbound tag in config.json
xray_add_vless_client() {
    local tag="$1"
    local uuid="$2"
    local remark="$3"
    local flow="${4:-}"   # empty for non-TCP, "xtls-rprx-vision" for TCP

    local client_json
    if [[ -n "$flow" ]]; then
        client_json=$(jq -n --arg id "$uuid" --arg email "$remark" --arg flow "$flow" \
            '{"id":$id,"email":$email,"level":0,"flow":$flow}')
    else
        client_json=$(jq -n --arg id "$uuid" --arg email "$remark" \
            '{"id":$id,"email":$email,"level":0}')
    fi

    jq --arg tag "$tag" --argjson client "$client_json" \
        '(.inbounds[] | select(.tag == $tag) | .settings.clients) += [$client]' \
        "$XRAY_CONFIG" > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json "$XRAY_CONFIG"
}

# Remove a VLESS client from a specific inbound tag by UUID
xray_del_vless_client() {
    local tag="$1"
    local uuid="$2"

    jq --arg tag "$tag" --arg id "$uuid" \
        '(.inbounds[] | select(.tag == $tag) | .settings.clients) |= map(select(.id != $id))' \
        "$XRAY_CONFIG" > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json "$XRAY_CONFIG"
}

# Add a Trojan client to a specific inbound tag
xray_add_trojan_client() {
    local tag="$1"
    local password="$2"
    local remark="$3"

    local client_json
    client_json=$(jq -n --arg pw "$password" --arg email "$remark" \
        '{"password":$pw,"email":$email,"level":0}')

    jq --arg tag "$tag" --argjson client "$client_json" \
        '(.inbounds[] | select(.tag == $tag) | .settings.clients) += [$client]' \
        "$XRAY_CONFIG" > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json "$XRAY_CONFIG"
}

# Remove a Trojan client by password
xray_del_trojan_client() {
    local tag="$1"
    local password="$2"

    jq --arg tag "$tag" --arg pw "$password" \
        '(.inbounds[] | select(.tag == $tag) | .settings.clients) |= map(select(.password != $pw))' \
        "$XRAY_CONFIG" > /tmp/xray_tmp.json && mv /tmp/xray_tmp.json "$XRAY_CONFIG"
}

# ==========================================================
# SERVICE MANAGEMENT
# ==========================================================

xray_start()   { systemctl start xray; }
xray_stop()    { systemctl stop xray; }
xray_restart() { systemctl restart xray; }
xray_reload()  {
    step "Validating config..."
    if xray_validate_config &>/dev/null; then
        success "Config OK. Restarting Xray..."
        systemctl restart xray
        sleep 1
        if systemctl is-active --quiet xray; then
            success "Xray restarted successfully."
        else
            error "Xray failed to start. Check: journalctl -u xray -n 30"
        fi
    else
        error "Config validation failed! No changes applied."
        xray_validate_config
    fi
}

xray_status() {
    systemctl status xray --no-pager | head -20
}

nginx_restart() { systemctl restart nginx 2>/dev/null; }

# ==========================================================
# SERVER INFO (cached)
# ==========================================================

get_server_ip() {
    local cached="/opt/imagitech-xray/core/.server_ip"
    if [[ -f "$cached" ]]; then
        cat "$cached"
    else
        local ip
        ip=$(curl -s4 icanhazip.com 2>/dev/null || curl -s4 ifconfig.me 2>/dev/null)
        echo "$ip" > "$cached"
        echo "$ip"
    fi
}

get_server_info() {
    local cached="/opt/imagitech-xray/core/.server_geo"
    if [[ ! -f "$cached" ]]; then
        local ip
        ip=$(get_server_ip)
        local data
        data=$(curl -s "http://ip-api.com/line/${ip}?fields=country,org" 2>/dev/null)
        local country
        country=$(echo "$data" | sed -n '1p')
        local isp
        isp=$(echo "$data" | sed -n '2p' | sed 's/ *(.*)//')
        echo "SERVER_IP=\"${ip}\"" > "$cached"
        echo "SERVER_COUNTRY=\"${country:-Unknown}\"" >> "$cached"
        echo "SERVER_ISP=\"${isp:-Unknown}\"" >> "$cached"
    fi
    source "$cached"
}

get_xray_version() {
    if [[ -x "$XRAY_BIN" ]]; then
        "$XRAY_BIN" version 2>/dev/null | head -1 | grep -oP 'Xray \K[\d.]+'
    else
        echo "not installed"
    fi
}
