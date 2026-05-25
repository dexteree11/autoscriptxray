#!/bin/bash
# ==========================================================
# lib/qr.sh — QR Code & Share Link Builders
# Imagitech XRAY Suite
# ==========================================================
source /opt/imagitech-xray/lib/colors.sh 2>/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
source /opt/imagitech-xray/lib/ui.sh 2>/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

# --- Display QR Code in terminal ---
show_qr() {
    local link="$1"
    if command -v qrencode &>/dev/null; then
        echo ""
        echo -e "  ${CYAN}┌─ QR CODE ──────────────────────────────────────────────┐${NC}"
        qrencode -t ansiutf8 -m 1 "$link" | sed 's/^/  /'
        echo -e "  ${CYAN}└────────────────────────────────────────────────────────┘${NC}"
    else
        warn "qrencode not installed. Run: apt install qrencode"
    fi
}

# --- Print share link in a styled box ---
show_link() {
    local label="$1"
    local link="$2"
    echo ""
    echo -e "  ${BGREEN}${label}:${NC}"
    echo -e "  ${DIM}────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BWHITE}${link}${NC}"
    echo -e "  ${DIM}────────────────────────────────────────────────────────${NC}"
    echo ""
}

# --- URL-encode a string ---
url_encode() {
    local raw="$1"
    python3 -c "import urllib.parse; print(urllib.parse.quote('${raw}', safe=''))" 2>/dev/null \
        || echo "$raw" | sed 's/ /%20/g; s/\//%2F/g; s/:/%3A/g'
}

# ==============================================================
# VLESS-REALITY-xHTTP Share Link
# Format: vless://UUID@IP:PORT?type=xhttp&security=reality&...#REMARK
# Matches the exact working URI format from the reference config
# ==============================================================
build_vless_reality_xhttp_link() {
    local uuid="$1"
    local ip="$2"
    local port="$3"
    local public_key="$4"
    local short_id="$5"
    local sni="$6"
    local path="$7"
    local remark="${8:-VLESS-REALITY-xHTTP}"

    # URL-encode the path (e.g. /abc123 → %2Fabc123)
    local encoded_path
    encoded_path=$(url_encode "$path")

    local link="vless://${uuid}@${ip}:${port}"
    link+="?security=reality"
    link+="&encryption=none"
    link+="&pbk=${public_key}"
    link+="&headerType=none"
    link+="&fp=chrome"
    link+="&type=xhttp"
    link+="&path=${encoded_path}"
    link+="&sni=${sni}"
    link+="&sid=${short_id}"
    link+="#$(url_encode "$remark")"

    echo "$link"
}

# ==============================================================
# VLESS-REALITY-TCP Share Link
# ==============================================================
build_vless_reality_tcp_link() {
    local uuid="$1"
    local ip="$2"
    local port="$3"
    local public_key="$4"
    local short_id="$5"
    local sni="$6"
    local remark="${7:-VLESS-REALITY-TCP}"

    local link="vless://${uuid}@${ip}:${port}"
    link+="?security=reality"
    link+="&encryption=none"
    link+="&pbk=${public_key}"
    link+="&headerType=none"
    link+="&fp=chrome"
    link+="&type=tcp"
    link+="&flow=xtls-rprx-vision"
    link+="&sni=${sni}"
    link+="&sid=${short_id}"
    link+="#$(url_encode "$remark")"

    echo "$link"
}

# ==============================================================
# VLESS-WS-TLS Share Link
# ==============================================================
build_vless_ws_link() {
    local uuid="$1"
    local domain="$2"
    local port="${3:-443}"
    local path="${4:-/vless}"
    local remark="${5:-VLESS-WS-TLS}"

    local encoded_path
    encoded_path=$(url_encode "$path")

    local link="vless://${uuid}@${domain}:${port}"
    link+="?type=ws"
    link+="&security=tls"
    link+="&sni=${domain}"
    link+="&path=${encoded_path}"
    link+="&host=${domain}"
    link+="&fp=chrome"
    link+="&encryption=none"
    link+="#$(url_encode "$remark")"

    echo "$link"
}

# ==============================================================
# Trojan-WS-TLS Share Link
# ==============================================================
build_trojan_ws_link() {
    local password="$1"
    local domain="$2"
    local port="${3:-443}"
    local path="${4:-/trojan-ws}"
    local remark="${5:-Trojan-WS-TLS}"

    local encoded_path
    encoded_path=$(url_encode "$path")

    local link="trojan://${password}@${domain}:${port}"
    link+="?type=ws"
    link+="&security=tls"
    link+="&sni=${domain}"
    link+="&path=${encoded_path}"
    link+="&host=${domain}"
    link+="&fp=chrome"
    link+="#$(url_encode "$remark")"

    echo "$link"
}

# ==============================================================
# Trojan-TCP-TLS Share Link
# ==============================================================
build_trojan_tcp_link() {
    local password="$1"
    local domain="$2"
    local port="${3:-443}"
    local remark="${4:-Trojan-TCP-TLS}"

    local link="trojan://${password}@${domain}:${port}"
    link+="?type=tcp"
    link+="&security=tls"
    link+="&sni=${domain}"
    link+="&fp=chrome"
    link+="#$(url_encode "$remark")"

    echo "$link"
}

# ==============================================================
# VMess-WS-TLS Share Link (base64 JSON format)
# ==============================================================
build_vmess_ws_link() {
    local uuid="$1"
    local domain="$2"
    local port="${3:-443}"
    local path="${4:-/vmess}"
    local remark="${5:-VMess-WS-TLS}"

    local json
    json=$(cat <<EOF
{"v":"2","ps":"${remark}","add":"${domain}","port":"${port}","id":"${uuid}","aid":"0","net":"ws","type":"none","host":"${domain}","path":"${path}","tls":"tls","sni":"${domain}","fp":"chrome"}
EOF
)
    local b64
    b64=$(echo -n "$json" | base64 -w 0)
    echo "vmess://${b64}"
}
