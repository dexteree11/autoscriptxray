#!/bin/bash
# =============================================================================
#  IMAGITECH XRAY — Nginx Installer / WS Reverse-Proxy Configurator
#  File   : installers/install_nginx.sh
#  Author : IMAGITECH
#  Purpose: Install Nginx and configure it as a WebSocket reverse proxy for
#           XRAY protocols (VLESS/VMess/Trojan over WS + TLS) on
#           Ubuntu / Debian systems.
# =============================================================================

# ---------------------------------------------------------------------------
# Source shared libraries
# ---------------------------------------------------------------------------
LIB_DIR="/opt/imagitech-xray/lib"

if [[ ! -f "${LIB_DIR}/colors.sh" ]]; then
    echo "[ERROR] colors.sh not found at ${LIB_DIR}/colors.sh" >&2
    exit 1
fi

if [[ ! -f "${LIB_DIR}/ui.sh" ]]; then
    echo "[ERROR] ui.sh not found at ${LIB_DIR}/ui.sh" >&2
    exit 1
fi

# shellcheck source=/opt/imagitech-xray/lib/colors.sh
source "${LIB_DIR}/colors.sh"
# shellcheck source=/opt/imagitech-xray/lib/ui.sh
source "${LIB_DIR}/ui.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
readonly BRAND="IMAGITECH XRAY"
readonly NGINX_SITE="/etc/nginx/sites-available/imagitech-xray"
readonly NGINX_ENABLED="/etc/nginx/sites-enabled/imagitech-xray"
readonly NGINX_TEMPLATE="/opt/imagitech-xray/configs/nginx_ws.conf.template"
readonly NGINX_SERVICE="nginx"

# ---------------------------------------------------------------------------
# check_root — abort if not running as root
# ---------------------------------------------------------------------------
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        error "This script must be run as root."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# check_nginx_installed
# Returns: 0 if nginx binary is present, 1 otherwise
# ---------------------------------------------------------------------------
check_nginx_installed() {
    if command -v nginx &>/dev/null; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# install_nginx — install Nginx via apt and enable the service
# ---------------------------------------------------------------------------
install_nginx() {
    check_root

    draw_top
    echo -e "${CYAN}  ${BRAND} — Nginx Installer${RESET}"
    draw_mid

    # ── Already installed? ──────────────────────────────────────────────────
    if check_nginx_installed; then
        local installed_ver
        installed_ver="$(nginx -v 2>&1 | head -n1)"
        warn "Nginx is already installed: ${installed_ver}"
        warn "Skipping installation. Use configure option to (re)configure."
        draw_bot
        return 0
    fi

    # ── Install ─────────────────────────────────────────────────────────────
    step "Updating package lists…"
    if ! apt-get update -qq; then
        error "apt-get update failed."
        draw_bot
        return 1
    fi

    step "Installing Nginx…"
    if ! apt-get install -y nginx; then
        error "Failed to install Nginx via apt-get."
        draw_bot
        return 1
    fi

    # ── Enable & start service ───────────────────────────────────────────────
    step "Enabling and starting Nginx service…"
    if ! systemctl enable --now "${NGINX_SERVICE}" &>/dev/null; then
        warn "Could not enable/start Nginx service automatically."
    else
        success "Nginx service enabled and started."
    fi

    # ── Verify ──────────────────────────────────────────────────────────────
    if ! check_nginx_installed; then
        error "Nginx binary not found after installation. Something went wrong."
        draw_bot
        return 1
    fi

    local nginx_ver
    nginx_ver="$(nginx -v 2>&1 | head -n1)"

    draw_mid
    success "${BRAND}: Nginx installed successfully!"
    echo -e "  ${GREEN}Version :${RESET} ${nginx_ver}"
    draw_bot
}

# ---------------------------------------------------------------------------
# configure_nginx_ws — generate and deploy the WS reverse-proxy site config
#
# Parameters (positional or interactive):
#   $1 — DOMAIN    : the fully-qualified domain name (e.g. vpn.example.com)
#   $2 — CERT_PATH : full path to the TLS certificate file
#   $3 — KEY_PATH  : full path to the TLS private key file
#   $4 — WS_PATH   : WebSocket path prefix (e.g. /ws)  [optional, default=/ws]
#
# The function replaces the following placeholders in the template:
#   {{DOMAIN}}    → DOMAIN
#   {{CERT_PATH}} → CERT_PATH
#   {{KEY_PATH}}  → KEY_PATH
#   {{WS_PATH}}   → WS_PATH
# ---------------------------------------------------------------------------
configure_nginx_ws() {
    check_root

    draw_top
    echo -e "${CYAN}  ${BRAND} — Nginx WebSocket Reverse-Proxy Configurator${RESET}"
    draw_mid

    # ── Nginx must be installed ──────────────────────────────────────────────
    if ! check_nginx_installed; then
        error "Nginx is not installed. Run the install option first."
        draw_bot
        return 1
    fi

    # ── Gather parameters ────────────────────────────────────────────────────
    local domain="${1:-}"
    local cert_path="${2:-}"
    local key_path="${3:-}"
    local ws_path="${4:-/ws}"

    # Interactive prompts for any missing values
    if [[ -z "${domain}" ]]; then
        read -r -p "  Enter your domain name (e.g. vpn.example.com): " domain
    fi
    if [[ -z "${domain}" ]]; then
        error "Domain cannot be empty."
        draw_bot
        return 1
    fi

    if [[ -z "${cert_path}" ]]; then
        read -r -p "  Enter full path to TLS certificate file: " cert_path
    fi
    if [[ -z "${cert_path}" ]]; then
        error "Certificate path cannot be empty."
        draw_bot
        return 1
    fi

    if [[ -z "${key_path}" ]]; then
        read -r -p "  Enter full path to TLS private key file: " key_path
    fi
    if [[ -z "${key_path}" ]]; then
        error "Private key path cannot be empty."
        draw_bot
        return 1
    fi

    # Validate cert / key existence (warn only — they may be provisioned later)
    [[ -f "${cert_path}" ]] || warn "Certificate file not found: ${cert_path} (continuing anyway)"
    [[ -f "${key_path}" ]]  || warn "Private key file not found: ${key_path} (continuing anyway)"

    # ── Template must exist ──────────────────────────────────────────────────
    if [[ ! -f "${NGINX_TEMPLATE}" ]]; then
        error "Nginx WS template not found at: ${NGINX_TEMPLATE}"
        draw_bot
        return 1
    fi

    step "Generating Nginx site config for domain: ${domain}…"

    # ── Perform template substitution ────────────────────────────────────────
    # Use a temp file so we don't corrupt the live config on failure
    local tmp_conf
    tmp_conf="$(mktemp /tmp/imagitech-nginx-XXXXXX.conf)"

    sed \
        -e "s|{{DOMAIN}}|${domain}|g"       \
        -e "s|{{CERT_PATH}}|${cert_path}|g" \
        -e "s|{{KEY_PATH}}|${key_path}|g"   \
        -e "s|{{WS_PATH}}|${ws_path}|g"     \
        "${NGINX_TEMPLATE}" > "${tmp_conf}"

    if [[ ! -s "${tmp_conf}" ]]; then
        error "Template substitution produced an empty file."
        rm -f "${tmp_conf}"
        draw_bot
        return 1
    fi

    # ── Deploy to sites-available ────────────────────────────────────────────
    step "Writing config to ${NGINX_SITE}…"
    if ! mv "${tmp_conf}" "${NGINX_SITE}"; then
        error "Could not write Nginx site config to ${NGINX_SITE}."
        rm -f "${tmp_conf}"
        draw_bot
        return 1
    fi
    chmod 644 "${NGINX_SITE}"

    # ── Create sites-enabled symlink ─────────────────────────────────────────
    step "Creating symlink in sites-enabled…"
    if [[ -L "${NGINX_ENABLED}" ]]; then
        rm -f "${NGINX_ENABLED}"
    fi
    if ! ln -s "${NGINX_SITE}" "${NGINX_ENABLED}"; then
        error "Failed to create symlink: ${NGINX_ENABLED} → ${NGINX_SITE}"
        draw_bot
        return 1
    fi
    success "Symlink created: ${NGINX_ENABLED}"

    # ── Disable default site if present ─────────────────────────────────────
    if [[ -L /etc/nginx/sites-enabled/default ]]; then
        step "Disabling Nginx default site…"
        rm -f /etc/nginx/sites-enabled/default
        info "Default site disabled."
    fi

    # ── Test Nginx configuration ─────────────────────────────────────────────
    step "Testing Nginx configuration…"
    if ! nginx -t &>/dev/null; then
        error "Nginx configuration test FAILED. Check the output below:"
        nginx -t
        draw_bot
        return 1
    fi
    success "Nginx configuration test passed."

    # ── Reload Nginx ─────────────────────────────────────────────────────────
    step "Reloading Nginx…"
    if ! systemctl reload "${NGINX_SERVICE}"; then
        error "Failed to reload Nginx."
        draw_bot
        return 1
    fi
    success "Nginx reloaded successfully."

    draw_mid
    success "${BRAND}: Nginx WS reverse proxy configured!"
    echo -e "  ${GREEN}Domain    :${RESET} ${domain}"
    echo -e "  ${GREEN}Cert      :${RESET} ${cert_path}"
    echo -e "  ${GREEN}Key       :${RESET} ${key_path}"
    echo -e "  ${GREEN}WS Path   :${RESET} ${ws_path}"
    echo -e "  ${GREEN}Site conf :${RESET} ${NGINX_SITE}"
    draw_bot
}

# ---------------------------------------------------------------------------
# remove_nginx — stop, disable, and purge Nginx
# ---------------------------------------------------------------------------
remove_nginx() {
    check_root

    draw_top
    echo -e "${CYAN}  ${BRAND} — Nginx Remover${RESET}"
    draw_mid

    if ! check_nginx_installed; then
        warn "Nginx does not appear to be installed. Nothing to remove."
        draw_bot
        return 0
    fi

    # ── Confirmation prompt ──────────────────────────────────────────────────
    echo -e "  ${YELLOW}WARNING:${RESET} This will stop, disable, and purge Nginx from this system."
    read -r -p "  Are you sure you want to continue? [y/N]: " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        info "Removal cancelled."
        draw_bot
        return 0
    fi

    # ── Stop & disable service ───────────────────────────────────────────────
    step "Stopping and disabling Nginx service…"
    systemctl stop    "${NGINX_SERVICE}" 2>/dev/null || true
    systemctl disable "${NGINX_SERVICE}" 2>/dev/null || true

    # ── Remove site config ───────────────────────────────────────────────────
    step "Removing IMAGITECH XRAY site config…"
    rm -f "${NGINX_ENABLED}" "${NGINX_SITE}"

    # ── Purge package ────────────────────────────────────────────────────────
    step "Purging Nginx packages…"
    if ! apt-get purge -y nginx nginx-common nginx-full nginx-core 2>/dev/null; then
        warn "apt-get purge reported errors; some packages may not have been removed."
    fi
    apt-get autoremove -y 2>/dev/null || true

    if check_nginx_installed; then
        warn "Nginx binary still detected after removal. Manual cleanup may be required."
    else
        draw_mid
        success "${BRAND}: Nginx has been removed successfully."
    fi

    draw_bot
}

# ---------------------------------------------------------------------------
# Main — allow sourcing for function imports or direct execution.
#
# Usage:  install_nginx.sh [install|configure|remove|check]
#   configure accepts optional positional args:
#     install_nginx.sh configure <domain> <cert_path> <key_path> [ws_path]
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        install)
            install_nginx
            ;;
        configure)
            configure_nginx_ws "${2:-}" "${3:-}" "${4:-}" "${5:-/ws}"
            ;;
        remove)
            remove_nginx
            ;;
        check)
            if check_nginx_installed; then
                info "Nginx is installed: $(nginx -v 2>&1 | head -n1)"
                exit 0
            else
                info "Nginx is NOT installed."
                exit 1
            fi
            ;;
        *)
            echo -e "Usage: ${0} {install|configure|remove|check}"
            echo -e "       ${0} configure <domain> <cert_path> <key_path> [ws_path]"
            exit 1
            ;;
    esac
fi
