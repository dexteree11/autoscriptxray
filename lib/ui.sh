#!/bin/bash
# ==========================================================
# lib/ui.sh — Terminal UI Helpers
# Imagitech XRAY Suite
# ==========================================================
source /opt/imagitech-xray/lib/colors.sh 2>/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"

# --- Box Drawing (60-char wide) ---
draw_top() { echo -e "${CYAN}┌──────────────────────────────────────────────────────────┐${NC}"; }
draw_mid() { echo -e "${CYAN}├──────────────────────────────────────────────────────────┤${NC}"; }
draw_bot() { echo -e "${CYAN}└──────────────────────────────────────────────────────────┘${NC}"; }
draw_line(){ echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# Print a padded row: │  <text>  │
# Usage: draw_row "text"
draw_row() {
    local text="$1"
    printf "${CYAN}│${NC}  %-56s  ${CYAN}│${NC}\n" "$text"
}

# Print a centered title row
draw_title() {
    local text="$1"
    local width=58
    local pad=$(( (width - ${#text}) / 2 ))
    local padded
    padded=$(printf "%${pad}s%s%${pad}s" "" "$text" "")
    printf "${CYAN}│${NC}${BOLD}${CYAN}%-60s${NC}${CYAN}│${NC}\n" "$padded"
}

# --- Status Badge ---
# Returns colored [ON] or [OFF]
service_status() {
    local svc="$1"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "${BGREEN}[ON] ${NC}"
    else
        echo -e "${BRED}[OFF]${NC}"
    fi
}

# --- Pause ---
pause() {
    echo ""
    read -n 1 -s -r -p "$(echo -e "  ${DIM}Press any key to return...${NC}")"
    echo ""
}

# --- Confirm Prompt (y/n) ---
# Usage: confirm "Are you sure?" && do_something
confirm() {
    local prompt="${1:-Are you sure?}"
    echo -en "  ${ORANGE}${prompt} [y/N]: ${NC}"
    read -r ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

# --- Info / Success / Error / Warn printers ---
info()    { echo -e "  ${CYAN}[*]${NC} $*"; }
success() { echo -e "  ${BGREEN}[✓]${NC} $*"; }
error()   { echo -e "  ${BRED}[✗]${NC} $*"; }
warn()    { echo -e "  ${ORANGE}[!]${NC} $*"; }
step()    { echo -e "  ${MAGENTA}[→]${NC} $*"; }

# --- Spinner for long operations ---
spinner() {
    local pid=$1
    local msg="${2:-Working...}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r  ${CYAN}${spin:$i:1}${NC}  ${DIM}${msg}${NC}"
        sleep 0.1
    done
    printf "\r%-60s\r" ""  # clear spinner line
}

# --- Print a two-column key: value line ---
kv() {
    local key="$1"
    local val="$2"
    printf "  ${DIM}%-22s${NC} ${BWHITE}%s${NC}\n" "${key}:" "$val"
}
