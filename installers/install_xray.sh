#!/bin/bash
# =============================================================================
#  IMAGITECH XRAY — Xray-Core Installer / Updater / Remover
#  File   : installers/install_xray.sh
#  Author : IMAGITECH
#  Purpose: Install, update, or remove Xray-core using the official XTLS
#           install-release.sh script on Ubuntu / Debian systems.
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
readonly XRAY_BINARY="/usr/local/bin/xray"
readonly XRAY_SERVICE="xray"
readonly XTLS_INSTALL_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"
readonly BRAND="IMAGITECH XRAY"

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
# check_xray_installed
# Returns: 0 if xray binary is present, 1 otherwise
# ---------------------------------------------------------------------------
check_xray_installed() {
    if [[ -x "${XRAY_BINARY}" ]]; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# _fetch_installer — download the XTLS install-release.sh script and execute
# with the supplied arguments ($@).
# ---------------------------------------------------------------------------
_fetch_installer() {
    local args=("$@")

    info "Fetching official XTLS install script from GitHub…"

    if ! command -v curl &>/dev/null; then
        step "Installing curl…"
        apt-get update -qq && apt-get install -y curl
    fi

    # Run the installer; capture stdout+stderr for logging
    if bash -c "$(curl -fsSL "${XTLS_INSTALL_URL}")" @ "${args[@]}"; then
        return 0
    else
        return 1
    fi
}

# ---------------------------------------------------------------------------
# install_xray — fresh install of Xray-core
# ---------------------------------------------------------------------------
install_xray() {
    check_root

    draw_top
    echo -e "${CYAN}  ${BRAND} — Xray-Core Installer${RESET}"
    draw_mid

    # ── Already installed? ──────────────────────────────────────────────────
    if check_xray_installed; then
        local installed_ver
        installed_ver="$("${XRAY_BINARY}" version 2>/dev/null | head -n1)"
        warn "Xray-core is already installed: ${installed_ver}"
        warn "Use the update option to upgrade, or remove first."
        draw_bot
        return 0
    fi

    # ── Dependency check ────────────────────────────────────────────────────
    step "Checking system dependencies…"
    apt-get update -qq

    # ── Run XTLS installer ──────────────────────────────────────────────────
    step "Running XTLS official installer…"
    spinner "Downloading and installing Xray-core" \
        _fetch_installer install

    local rc=$?
    if [[ ${rc} -ne 0 ]]; then
        error "XTLS installer exited with code ${rc}. Installation failed."
        draw_bot
        return 1
    fi

    # ── Verify binary ───────────────────────────────────────────────────────
    if ! check_xray_installed; then
        error "Xray binary not found at ${XRAY_BINARY} after installation."
        draw_bot
        return 1
    fi

    # ── Enable & start service ──────────────────────────────────────────────
    step "Enabling and starting the xray systemd service…"
    if ! systemctl enable --now "${XRAY_SERVICE}" &>/dev/null; then
        warn "Could not enable/start xray service. You may need to configure it manually."
    else
        success "xray systemd service enabled and started."
    fi

    # ── Print version ───────────────────────────────────────────────────────
    local xray_ver
    xray_ver="$("${XRAY_BINARY}" version 2>/dev/null | head -n1)"

    draw_mid
    success "${BRAND}: Xray-core installed successfully!"
    echo -e "  ${GREEN}Version :${RESET} ${xray_ver}"
    echo -e "  ${GREEN}Binary  :${RESET} ${XRAY_BINARY}"
    draw_bot
}

# ---------------------------------------------------------------------------
# update_xray — update an existing Xray-core installation
# ---------------------------------------------------------------------------
update_xray() {
    check_root

    draw_top
    echo -e "${CYAN}  ${BRAND} — Xray-Core Updater${RESET}"
    draw_mid

    # ── Must already be installed ───────────────────────────────────────────
    if ! check_xray_installed; then
        warn "Xray-core is not currently installed. Running installer instead…"
        draw_bot
        install_xray
        return $?
    fi

    local old_ver
    old_ver="$("${XRAY_BINARY}" version 2>/dev/null | head -n1)"
    step "Current version: ${old_ver}"

    # ── Run XTLS installer in update mode ───────────────────────────────────
    step "Running XTLS official installer (update)…"
    spinner "Downloading and updating Xray-core" \
        _fetch_installer install

    local rc=$?
    if [[ ${rc} -ne 0 ]]; then
        error "XTLS updater exited with code ${rc}. Update failed."
        draw_bot
        return 1
    fi

    # ── Restart service after update ────────────────────────────────────────
    step "Restarting xray service…"
    if systemctl is-active --quiet "${XRAY_SERVICE}"; then
        systemctl restart "${XRAY_SERVICE}" && success "xray service restarted."
    else
        systemctl enable --now "${XRAY_SERVICE}" && success "xray service started."
    fi

    local new_ver
    new_ver="$("${XRAY_BINARY}" version 2>/dev/null | head -n1)"

    draw_mid
    success "${BRAND}: Xray-core updated successfully!"
    echo -e "  ${GREEN}Old version :${RESET} ${old_ver}"
    echo -e "  ${GREEN}New version :${RESET} ${new_ver}"
    draw_bot
}

# ---------------------------------------------------------------------------
# remove_xray — uninstall Xray-core
# ---------------------------------------------------------------------------
remove_xray() {
    check_root

    draw_top
    echo -e "${CYAN}  ${BRAND} — Xray-Core Remover${RESET}"
    draw_mid

    # ── Must be installed to remove ─────────────────────────────────────────
    if ! check_xray_installed; then
        warn "Xray-core does not appear to be installed. Nothing to remove."
        draw_bot
        return 0
    fi

    # ── Confirmation prompt ─────────────────────────────────────────────────
    echo -e "  ${YELLOW}WARNING:${RESET} This will stop and remove Xray-core from this system."
    read -r -p "  Are you sure you want to continue? [y/N]: " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        info "Removal cancelled."
        draw_bot
        return 0
    fi

    # ── Stop & disable service ──────────────────────────────────────────────
    step "Stopping and disabling xray service…"
    systemctl stop  "${XRAY_SERVICE}" 2>/dev/null || true
    systemctl disable "${XRAY_SERVICE}" 2>/dev/null || true

    # ── Run XTLS installer in remove mode ───────────────────────────────────
    step "Running XTLS official installer (remove)…"
    spinner "Removing Xray-core" \
        _fetch_installer remove

    local rc=$?
    if [[ ${rc} -ne 0 ]]; then
        error "XTLS remove script exited with code ${rc}."
        draw_bot
        return 1
    fi

    # ── Final verification ───────────────────────────────────────────────────
    if check_xray_installed; then
        warn "Xray binary still present at ${XRAY_BINARY}. Manual cleanup may be required."
    else
        draw_mid
        success "${BRAND}: Xray-core has been removed successfully."
    fi

    draw_bot
}

# ---------------------------------------------------------------------------
# Main — allow this script to be sourced (for function imports) or executed
# directly with a sub-command argument.
#
# Usage:  install_xray.sh [install|update|remove|check]
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        install) install_xray  ;;
        update)  update_xray   ;;
        remove)  remove_xray   ;;
        check)
            if check_xray_installed; then
                info "Xray-core is installed: $("${XRAY_BINARY}" version 2>/dev/null | head -n1)"
                exit 0
            else
                info "Xray-core is NOT installed."
                exit 1
            fi
            ;;
        *)
            echo -e "Usage: ${0} {install|update|remove|check}"
            exit 1
            ;;
    esac
fi
