#!/bin/bash
# ==========================================================
# lib/port_check.sh — Port Conflict Manager
# Imagitech XRAY Suite
# ==========================================================
source /opt/imagitech-xray/lib/colors.sh 2>/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"
source /opt/imagitech-xray/lib/ui.sh 2>/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

# --- Check if a port is in use ---
# Returns 0 (free) or 1 (in use)
port_is_free() {
    local port="$1"
    if command -v ss &>/dev/null; then
        ss -tlnp "sport = :${port}" 2>/dev/null | grep -q ":${port}"
        [[ $? -ne 0 ]]
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | grep -q ":${port} "
        [[ $? -ne 0 ]]
    else
        # fallback: try connecting
        ! (echo >/dev/tcp/localhost/"$port") 2>/dev/null
    fi
}

# --- Get the process using a port ---
port_owner() {
    local port="$1"
    if command -v ss &>/dev/null; then
        ss -tlnp "sport = :${port}" 2>/dev/null | grep ":${port}" | \
            grep -oP 'users:\(\("([^"]+)"' | grep -oP '"[^"]+"' | tr -d '"' | head -1
    elif command -v fuser &>/dev/null; then
        fuser "${port}/tcp" 2>/dev/null | xargs -I{} cat /proc/{}/comm 2>/dev/null | head -1
    else
        echo "unknown"
    fi
}

# --- Full conflict check for a list of ports ---
# Usage: check_ports_conflict 443 80 8080
# Returns 0 if all free, 1 if any conflict (and prints info)
check_ports_conflict() {
    local ports=("$@")
    local conflict=0

    echo ""
    info "Checking port availability..."
    echo ""

    for port in "${ports[@]}"; do
        if port_is_free "$port"; then
            printf "  ${BGREEN}[FREE]${NC}  Port %-6s — OK\n" "$port"
        else
            local owner
            owner=$(port_owner "$port")
            printf "  ${BRED}[BUSY]${NC}  Port %-6s — in use by: ${ORANGE}%s${NC}\n" "$port" "${owner:-unknown}"
            conflict=1
        fi
    done

    echo ""

    if [[ $conflict -eq 1 ]]; then
        warn "One or more required ports are already in use."
        echo ""
        echo -e "  ${DIM}Options:${NC}"
        echo -e "  ${CYAN}[1]${NC} Kill the conflicting process(es) and continue"
        echo -e "  ${CYAN}[2]${NC} Abort installation"
        echo ""
        read -p "$(echo -e "  ${ORANGE}Choose [1/2]: ${NC}")" choice
        case "$choice" in
            1)
                for port in "${ports[@]}"; do
                    if ! port_is_free "$port"; then
                        step "Freeing port ${port}..."
                        if command -v fuser &>/dev/null; then
                            fuser -k "${port}/tcp" 2>/dev/null
                        else
                            # Use ss + kill as fallback
                            local pid
                            pid=$(ss -tlnp "sport = :${port}" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -1)
                            [[ -n "$pid" ]] && kill -9 "$pid" 2>/dev/null
                        fi
                        sleep 1
                        if port_is_free "$port"; then
                            success "Port $port is now free."
                        else
                            error "Could not free port $port. Aborting."
                            return 1
                        fi
                    fi
                done
                return 0
                ;;
            2|*)
                warn "Installation aborted by user."
                return 1
                ;;
        esac
    fi

    return 0
}

# --- Quick single port check (no interactive prompt) ---
# Returns 0 if free, prints warning and returns 1 if busy
require_port_free() {
    local port="$1"
    local label="${2:-required}"
    if ! port_is_free "$port"; then
        local owner
        owner=$(port_owner "$port")
        error "Port ${port} (${label}) is already in use by: ${owner:-unknown process}"
        return 1
    fi
    return 0
}
