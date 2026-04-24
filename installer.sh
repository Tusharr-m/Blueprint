#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_modules_dir() {
    local source_path=""
    source_path="$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || true)"

    local candidates=(
        "${SCRIPT_DIR}/modules"
        "$(pwd)/modules"
    )

    if [[ -n "$source_path" ]]; then
        candidates+=("$(dirname "$source_path")/modules")
    fi

    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -d "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    printf '%s\n' "${SCRIPT_DIR}/modules"
}

MODULES_DIR="$(resolve_modules_dir)"

# ── Color palette ────────────────────────────────────────────────────
BK="\e[0m"
CY="\e[96m"       # Bright Cyan
GR="\e[92m"       # Bright Green
RD="\e[91m"       # Bright Red
YL="\e[93m"       # Bright Yellow
MG="\e[95m"       # Bright Magenta
WH="\e[97m"       # Bright White
DM="\e[90m"       # Dim Gray
BD="\e[1m"        # Bold

# ── Terminal width helper ─────────────────────────────────────────────
get_width() {
    tput cols 2>/dev/null || echo 72
}

center_text() {
    local text="$1"
    local color="${2:-}"
    local w
    w=$(get_width)
    local len=${#text}
    local pad=$(( (w - len) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    printf "%*s%b%s%b\n" "$pad" "" "$color" "$text" "$BK"
}

draw_line() {
    local char="${1:-─}"
    local color="${2:-$DM}"
    local w
    w=$(get_width)
    local line
    line=$(printf "%*s" "$w" | tr ' ' "$char")
    echo -e "${color}${line}${BK}"
}

show_header() {
    clear
    echo
    echo -e "${CY}${BD}"
    center_text "╔══════════════════════════════════════════════════════════╗"
    center_text "║   ██████╗ ██╗     ██╗   ██╗███████╗██████╗ ██████╗     ║"
    center_text "║   ██╔══██╗██║     ██║   ██║██╔════╝██╔══██╗██╔══██╗    ║"
    center_text "║   ██████╔╝██║     ██║   ██║█████╗  ██████╔╝██████╔╝    ║"
    center_text "║   ██╔══██╗██║     ██║   ██║██╔══╝  ██╔═══╝ ██╔══██╗    ║"
    center_text "║   ██████╔╝███████╗╚██████╔╝███████╗██║     ██║  ██║    ║"
    center_text "║   ╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝╚═╝     ╚═╝  ╚═╝    ║"
    center_text "╠══════════════════════════════════════════════════════════╣"
    center_text "║        Pterodactyl Blueprint Installer  v2.0.0           ║"
    center_text "║              By Tushar  •  Premium CLI Tool              ║"
    center_text "╚══════════════════════════════════════════════════════════╝"
    echo -e "${BK}"
    echo
}

# ── System requirement checker ────────────────────────────────────────
check_requirements() {
    local missing=()
    for cmd in curl git unzip; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo
        echo -e "  ${RD}╔══════════════════════════════════════════════╗${BK}"
        echo -e "  ${RD}║  ✖  Missing System Requirements              ║${BK}"
        echo -e "  ${RD}╠══════════════════════════════════════════════╣${BK}"
        for cmd in "${missing[@]}"; do
            printf "  ${RD}║${BK}  ➜  %-40s ${RD}║${BK}\n" "$cmd not found"
        done
        echo -e "  ${RD}╠══════════════════════════════════════════════╣${BK}"
        printf  "  ${RD}║${BK}  Run: sudo apt install %-20s ${RD}║${BK}\n" "${missing[*]}"
        echo -e "  ${RD}╚══════════════════════════════════════════════╝${BK}"
        echo
        exit 1
    fi
}

# ── Module file guard ─────────────────────────────────────────────────
require_module() {
    local mod="${MODULES_DIR}/$1"
    if [[ ! -f "$mod" ]]; then
        echo
        echo -e "  ${RD}╔══════════════════════════════════════════════╗${BK}"
        echo -e "  ${RD}║  ✖  Module Not Found                         ║${BK}"
        echo -e "  ${RD}╠══════════════════════════════════════════════╣${BK}"
        printf  "  ${RD}║${BK}  File : %-36s ${RD}║${BK}\n" "modules/$1"
        printf  "  ${RD}║${BK}  Path : %-36s ${RD}║${BK}\n" "$mod"
        echo -e "  ${RD}╚══════════════════════════════════════════════╝${BK}"
        echo
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$mod"
}

# ── Interactive main menu ─────────────────────────────────────────────
show_menu() {
    while true; do
        show_header

        echo -e "  ${CY}┌─────────────────────────────────────────────────────┐${BK}"
        echo -e "  ${CY}│${BK}   ${GR}${BD}⚡  MAIN MENU${BK}                                    ${CY}│${BK}"
        echo -e "  ${CY}├─────────────────────────────────────────────────────┤${BK}"
        echo -e "  ${CY}│${BK}                                                     ${CY}│${BK}"
        echo -e "  ${CY}│${BK}   ${MG}➤${BK}  ${WH}${BD}1.${BK}  ${CY}📦  Install Blueprint Framework${BK}         ${CY}│${BK}"
        echo -e "  ${CY}│${BK}      ${WH}2.${BK}  ${WH}🧩  Run Addon Installer${BK}                  ${CY}│${BK}"
        echo -e "  ${CY}│${BK}      ${WH}3.${BK}  ${WH}🔽  Download Blueprints from GitHub${BK}      ${CY}│${BK}"
        echo -e "  ${CY}│${BK}      ${RD}4.${BK}  ${RD}🚪  Exit${BK}                                ${CY}│${BK}"
        echo -e "  ${CY}│${BK}                                                     ${CY}│${BK}"
        echo -e "  ${CY}└─────────────────────────────────────────────────────┘${BK}"
        echo
        echo -e "  ${DM}Use number keys to select  •  Press Enter to confirm${BK}"
        echo
        printf  "  ${DM}➜${BK}  ${YL}Select option [1-4]:${BK} "
        read -r choice

        case "$choice" in
            1)
                require_module "blueprint-installer.sh"
                main
                ;;
            2)
                require_module "addon-installer.sh"
                main
                ;;
            3)
                require_module "blueprint-manager.sh"
                bp_manager_main
                ;;
            4)
                show_exit
                exit 0
                ;;
            *)
                echo
                echo -e "  ${RD}✖  Invalid option. Please enter 1, 2, 3 or 4.${BK}"
                sleep 1
                continue
                ;;
        esac

        echo
        printf "  ${DM}Press [Enter] to return to main menu...${BK}"
        read -r
    done
}

# ── Clean exit screen ─────────────────────────────────────────────────
show_exit() {
    clear
    echo
    echo -e "${GR}${BD}"
    center_text "╔═══════════════════════════════════════════╗"
    center_text "║                                           ║"
    center_text "║   ✔  Thanks for using Blueprint CLI!      ║"
    center_text "║        Have a productive day 🚀           ║"
    center_text "║                                           ║"
    center_text "╚═══════════════════════════════════════════╝"
    echo -e "${BK}"
    echo
}

# ── Entry point ───────────────────────────────────────────────────────
main() {
    check_requirements
    show_menu
}

main "$@"
