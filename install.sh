#!/bin/bash
# ==========================================================
# install.sh — Imagitech XRAY Suite Master Orchestrator
# Run as root on a fresh VPS to install the full panel.
# Usage: bash install.sh
# ==========================================================

REPO_URL="https://raw.githubusercontent.com/dexteree11/autoscriptxray/main"
INSTALL_DIR="/opt/imagitech-xray"
PANEL_BIN="/usr/local/bin/xray-panel"

# --- ANSI Colors (standalone, no lib sourced yet) ---
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "  ${CYAN}[*]${NC} $*"; }
success() { echo -e "  ${GREEN}[✓]${NC} $*"; }
error()   { echo -e "  ${RED}[✗]${NC} $*"; }
warn()    { echo -e "  ${ORANGE}[!]${NC} $*"; }
step()    { echo -e "  ${MAGENTA}[→]${NC} $*"; }

banner() {
    clear
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║${NC}${BOLD}${CYAN}                                                          ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}  ║${NC}${BOLD}${CYAN}       ✦  IMAGITECH XRAY SUITE  — INSTALLER  ✦           ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}  ║${NC}${BOLD}${CYAN}              VLESS · REALITY · TROJAN · VMESS            ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}  ║${NC}${BOLD}${CYAN}                                                          ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ==========================================================
# ROOT CHECK
# ==========================================================
root_check() {
    if [[ "${EUID}" -ne 0 ]]; then
        error "This installer must be run as root."
        echo -e "  ${ORANGE}Type: sudo su -${NC}"
        exit 1
    fi
}

# ==========================================================
# OS CHECK
# ==========================================================
os_check() {
    if ! command -v apt-get &>/dev/null; then
        error "This installer supports Debian/Ubuntu only (apt-get required)."
        exit 1
    fi
    info "OS check passed: $(grep -w PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
}

# ==========================================================
# DEPENDENCY INSTALL
# ==========================================================
install_dependencies() {
    step "Installing system dependencies..."
    apt-get update -y >/dev/null 2>&1
    apt-get install -y \
        curl wget git jq openssl qrencode unzip socat cron \
        >/dev/null 2>&1
    success "Dependencies installed."
}

# ==========================================================
# FETCH FILE FROM GITHUB (with 404 guard)
# ==========================================================
fetch_file() {
    local remote_path="$1"
    local local_path="$2"

    step "Fetching: ${remote_path}"
    local http_code
    http_code=$(curl -sL -o "$local_path" -w "%{http_code}" "${REPO_URL}/${remote_path}")

    if [[ "$http_code" != "200" ]]; then
        # Check if the file is a 404 HTML response
        if grep -qi "<!DOCTYPE\|<html" "$local_path" 2>/dev/null; then
            rm -f "$local_path"
            error "Failed to fetch ${remote_path} (HTTP ${http_code})"
            return 1
        fi
    fi
    chmod +x "$local_path" 2>/dev/null
    return 0
}

# ==========================================================
# CREATE DIRECTORY STRUCTURE
# ==========================================================
create_dirs() {
    step "Creating panel directory structure..."
    mkdir -p "${INSTALL_DIR}"/{lib,installers,configs,menus,bin,services}
    mkdir -p "${INSTALL_DIR}"/core/{keys,users,logs}
    touch "${INSTALL_DIR}/core/imagitech-xray.conf"
    chmod 600 "${INSTALL_DIR}/core/imagitech-xray.conf"
    success "Directories created at ${INSTALL_DIR}"
}

# ==========================================================
# DOWNLOAD ALL SCRIPTS
# ==========================================================
download_scripts() {
    step "Downloading panel scripts..."

    local files=(
        "lib/colors.sh:${INSTALL_DIR}/lib/colors.sh"
        "lib/ui.sh:${INSTALL_DIR}/lib/ui.sh"
        "lib/xray_utils.sh:${INSTALL_DIR}/lib/xray_utils.sh"
        "lib/qr.sh:${INSTALL_DIR}/lib/qr.sh"
        "lib/port_check.sh:${INSTALL_DIR}/lib/port_check.sh"
        "installers/install_xray.sh:${INSTALL_DIR}/installers/install_xray.sh"
        "installers/install_nginx.sh:${INSTALL_DIR}/installers/install_nginx.sh"
        "installers/install_acme.sh:${INSTALL_DIR}/installers/install_acme.sh"
        "configs/xray_base.json:${INSTALL_DIR}/configs/xray_base.json"
        "configs/nginx_ws.conf.template:${INSTALL_DIR}/configs/nginx_ws.conf.template"
        "menus/main_menu.sh:${INSTALL_DIR}/menus/main_menu.sh"
        "menus/vless_reality_menu.sh:${INSTALL_DIR}/menus/vless_reality_menu.sh"
        "menus/vless_ws_menu.sh:${INSTALL_DIR}/menus/vless_ws_menu.sh"
        "menus/trojan_ws_menu.sh:${INSTALL_DIR}/menus/trojan_ws_menu.sh"
        "menus/trojan_tcp_menu.sh:${INSTALL_DIR}/menus/trojan_tcp_menu.sh"
        "menus/vmess_ws_menu.sh:${INSTALL_DIR}/menus/vmess_ws_menu.sh"
        "menus/service_menu.sh:${INSTALL_DIR}/menus/service_menu.sh"
        "menus/cert_menu.sh:${INSTALL_DIR}/menus/cert_menu.sh"
        "menus/nginx_menu.sh:${INSTALL_DIR}/menus/nginx_menu.sh"
        "menus/settings_menu.sh:${INSTALL_DIR}/menus/settings_menu.sh"
    )

    local fail=0
    for entry in "${files[@]}"; do
        local remote="${entry%%:*}"
        local local_dest="${entry##*:}"
        fetch_file "$remote" "$local_dest" || fail=1
    done

    if [[ $fail -eq 1 ]]; then
        warn "Some files failed to download. Check your GitHub repo."
        warn "You can re-run the installer or manually copy the files."
    else
        success "All scripts downloaded."
    fi
}

# ==========================================================
# INSTALL XRAY CORE
# ==========================================================
install_xray_core() {
    step "Installing Xray-core..."
    if [[ -x /usr/local/bin/xray ]]; then
        local ver
        ver=$(/usr/local/bin/xray version 2>/dev/null | head -1 | grep -oP 'Xray \K[\d.]+')
        warn "Xray is already installed (v${ver}). Skipping."
        return 0
    fi

    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install \
        >/dev/null 2>&1

    if [[ -x /usr/local/bin/xray ]]; then
        success "Xray-core installed: v$(/usr/local/bin/xray version 2>/dev/null | head -1 | grep -oP 'Xray \K[\d.]+')"
    else
        error "Xray installation failed. Please install manually."
        return 1
    fi
}

# ==========================================================
# BOOTSTRAP XRAY CONFIG
# ==========================================================
setup_xray_config() {
    local config_path="/usr/local/etc/xray/config.json"
    if [[ ! -f "$config_path" ]]; then
        step "Setting up base Xray configuration..."
        mkdir -p /usr/local/etc/xray
        cp "${INSTALL_DIR}/configs/xray_base.json" "$config_path"
        # Update log paths to use our panel's log dir
        jq '.log.access = "/opt/imagitech-xray/core/logs/access.log" |
            .log.error  = "/opt/imagitech-xray/core/logs/error.log"' \
            "$config_path" > /tmp/xray_cfg.json && mv /tmp/xray_cfg.json "$config_path"
        success "Xray config initialized."
    else
        info "Xray config already exists, skipping base setup."
    fi

    # Enable and start service
    systemctl enable xray >/dev/null 2>&1
    systemctl start xray >/dev/null 2>&1
}

# ==========================================================
# CREATE PANEL ENTRY POINT
# ==========================================================
create_entry_point() {
    step "Creating panel entry point..."

    cat > "${INSTALL_DIR}/bin/xray-panel" <<'EOF'
#!/bin/bash
exec bash /opt/imagitech-xray/menus/main_menu.sh "$@"
EOF
    chmod +x "${INSTALL_DIR}/bin/xray-panel"

    ln -sf "${INSTALL_DIR}/bin/xray-panel" "$PANEL_BIN"
    success "Panel entry point created. Run: ${BOLD}xray-panel${NC}"
}

# ==========================================================
# OPTIONAL: INSTALL NGINX
# ==========================================================
prompt_install_nginx() {
    echo ""
    echo -e "  ${CYAN}Install Nginx?${NC} (Required for WS-TLS based protocols: VLESS-WS, Trojan-WS, VMess-WS)"
    read -p "$(echo -e "  ${ORANGE}Install Nginx now? [y/N]: ${NC}")" ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        bash "${INSTALL_DIR}/installers/install_nginx.sh" install
    else
        info "Nginx skipped. Install later from menu: [09] Nginx Manager"
    fi
}

# ==========================================================
# OPTIONAL: INSTALL ACME.SH
# ==========================================================
prompt_install_acme() {
    echo ""
    echo -e "  ${CYAN}Install acme.sh?${NC} (Required for TLS certificate issuance via Cloudflare DNS)"
    read -p "$(echo -e "  ${ORANGE}Install acme.sh now? [y/N]: ${NC}")" ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        bash "${INSTALL_DIR}/installers/install_acme.sh" install
    else
        info "acme.sh skipped. Install later from menu: [08] Certificate Manager"
    fi
}

# ==========================================================
# PRINT COMPLETION SUMMARY
# ==========================================================
print_summary() {
    local ip
    ip=$(curl -s4 icanhazip.com 2>/dev/null || echo "N/A")

    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║${NC}${BOLD}${GREEN}        ✦  INSTALLATION COMPLETE!  ✦                     ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Panel Dir  : /opt/imagitech-xray"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Launch Cmd : xray-panel"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Xray Conf  : /usr/local/etc/xray/config.json"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  Server IP  : ${ip}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}  ║${NC}  ${BOLD}Next Steps:${NC}                                              ${CYAN}║${NC}"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  1. Run: xray-panel"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  2. Issue TLS cert: Menu [08] Certificate Manager"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  3. Configure Nginx: Menu [09] Nginx Manager"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  4. Install a protocol from menus [01]-[06]"
    printf "${CYAN}  ║${NC}  %-56s${CYAN}║${NC}\n" "  5. Add users and get share links!"
    echo -e "${CYAN}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ==========================================================
# MAIN
# ==========================================================
main() {
    banner
    root_check
    os_check
    install_dependencies
    create_dirs
    download_scripts
    install_xray_core
    setup_xray_config
    create_entry_point
    prompt_install_nginx
    prompt_install_acme
    print_summary
}

main
