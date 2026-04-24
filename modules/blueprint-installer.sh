#!/usr/bin/env bash

LOG_FILE="/var/log/blueprint-installer.log"
LIVE_LOG_LINES=10

# ── Colors ─────────────────────────────────────────────────────────────
BK="\e[0m"
CY="\e[96m"
GR="\e[92m"
RD="\e[91m"
YL="\e[93m"
MG="\e[95m"
WH="\e[97m"
DM="\e[90m"
BD="\e[1m"

# ── Logger ──────────────────────────────────────────────────────────────
_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | sudo tee -a "$LOG_FILE" >/dev/null
}

_draw_live_frame() {
    local msg="$1"
    local temp_log="$2"
    local frame="$3"

    local lines=()
    mapfile -t lines < <(tail -n "$LIVE_LOG_LINES" "$temp_log" 2>/dev/null)

    while ((${#lines[@]} < LIVE_LOG_LINES)); do
        lines=("" "${lines[@]}")
    done

    printf "\033[H\033[J"
    echo
    echo -e "  ${CY}${BD}⚡  BLUEPRINT FRAMEWORK INSTALLER${BK}   ${DM}— Option 1${BK}"
    echo
    echo -e "  ${CY}┌──────────────────────────────────────────────────────────┐${BK}"
    echo -e "  ${CY}│${BK}   ${WH}${BD}📦  Installing Blueprint Framework on Pterodactyl${BK}    ${CY}│${BK}"
    printf  "  ${CY}│${BK}   ${DM}%s ${MG}%s${BK}  ${WH}%-36s${BK} ${CY}│${BK}\n" "Status:" "$frame" "$msg"
    printf  "  ${CY}│${BK}   ${DM}Log file: ${WH}%-45s${BK} ${CY}│${BK}\n" "$LOG_FILE"
    echo -e "  ${CY}└──────────────────────────────────────────────────────────┘${BK}"
    echo
    echo -e "  ${CY}${BD}── Live Logs (last ${LIVE_LOG_LINES} lines) ─────────────────────────${BK}"
    echo
    for line in "${lines[@]}"; do
        line="${line//$'\r'/}"
        printf "  ${DM}%s${BK}\n" "${line:0:120}"
    done
}

# ── Run command with live log window + spinner ─────────────────────────
_run() {
    local msg="$1"
    shift

    local temp_log
    temp_log="$(mktemp)"
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0

    (
        stdbuf -oL -eL "$@" 2>&1 | while IFS= read -r line; do
            printf '%s\n' "$line" | sudo tee -a "$LOG_FILE" >/dev/null
            printf '%s\n' "$line" >> "$temp_log"
        done
    ) &
    local pid=$!

    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        _draw_live_frame "$msg" "$temp_log" "${frames[$i]}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.2
    done
    tput cnorm 2>/dev/null || true
    _draw_live_frame "$msg" "$temp_log" "✔"

    if wait "$pid"; then
        echo
        printf "  ${GR}✔${BK}  %-55s\n" "$msg"
        _log "OK: $msg"
        rm -f "$temp_log"
        return 0
    fi

    echo
    printf "  ${RD}✖${BK}  Failed: %-49s\n" "$msg"
    _log "FAIL: $msg"
    echo
    echo -e "  ${RD}╔══════════════════════════════════════════════════╗${BK}"
    echo -e "  ${RD}║  ✖  Installation step failed — aborting.         ║${BK}"
    printf  "  ${RD}║${BK}  Step: %-42s ${RD}║${BK}\n" "$msg"
    printf  "  ${RD}║${BK}  Log : %-42s ${RD}║${BK}\n" "$LOG_FILE"
    echo -e "  ${RD}╚══════════════════════════════════════════════════╝${BK}"
    echo
    rm -f "$temp_log"
    exit 1
}

# ── Section divider ─────────────────────────────────────────────────────
_section() {
    echo
    echo -e "  ${CY}${BD}── $* ──────────────────────────────────────────${BK}"
    echo
}

# ── Privilege check ─────────────────────────────────────────────────────
_check_privileges() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        echo
        echo -e "  ${RD}╔══════════════════════════════════════════════════╗${BK}"
        echo -e "  ${RD}║  ✖  Insufficient Privileges                      ║${BK}"
        echo -e "  ${RD}╠══════════════════════════════════════════════════╣${BK}"
        echo -e "  ${RD}║${BK}  This module requires sudo / root access.         ${RD}║${BK}"
        echo -e "  ${RD}║${BK}  Run: ${WH}sudo bash installer.sh${BK}                    ${RD}║${BK}"
        echo -e "  ${RD}╚══════════════════════════════════════════════════╝${BK}"
        echo
        exit 1
    fi
}

# ── Already-installed guard ─────────────────────────────────────────────
_check_existing() {
    if [[ -f "/var/www/pterodactyl/.blueprint-installed" ]]; then
        echo
        echo -e "  ${YL}╔══════════════════════════════════════════════════╗${BK}"
        echo -e "  ${YL}║  ⚠  Blueprint Already Installed                  ║${BK}"
        echo -e "  ${YL}╠══════════════════════════════════════════════════╣${BK}"
        echo -e "  ${YL}║${BK}  A previous installation was detected.             ${YL}║${BK}"
        echo -e "  ${YL}║${BK}  Reinstalling may overwrite existing config.       ${YL}║${BK}"
        echo -e "  ${YL}╚══════════════════════════════════════════════════╝${BK}"
        echo
        printf "  ${DM}➜${BK}  ${YL}Reinstall Blueprint? [y/N]:${BK} "
        read -r reply
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            echo -e "  ${GR}  Installation cancelled.${BK}"
            echo
            return 1
        fi
    fi
}

# ── Install package if not present ──────────────────────────────────────
_ensure_pkg() {
    local pkg="$1"
    if dpkg -l "$pkg" &>/dev/null; then
        printf "  ${GR}✔${BK}  %-50s ${DM}(already installed)${BK}\n" "$pkg"
        return 0
    fi
    _run "Installing package: $pkg" sudo apt-get install -y "$pkg"
}

# ── Node.js 20 setup ────────────────────────────────────────────────────
_setup_node() {
    if command -v node &>/dev/null && node --version 2>/dev/null | grep -q "^v20"; then
        printf "  ${GR}✔${BK}  %-50s ${DM}(already installed)${BK}\n" "Node.js 20"
        return 0
    fi

    if command -v node &>/dev/null; then
        _run "Removing old Node.js version" \
            bash -c "sudo apt-get remove -y --purge nodejs npm && sudo rm -f /etc/apt/sources.list.d/nodesource.list"
    fi

    _run "Adding NodeSource 20.x repository" \
        bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
    _run "Installing Node.js 20" \
        sudo apt-get install -y nodejs
}

# ── Yarn setup via corepack ──────────────────────────────────────────────
_setup_yarn() {
    if command -v yarn &>/dev/null; then
        printf "  ${GR}✔${BK}  %-50s ${DM}(already installed)${BK}\n" "Yarn"
        return 0
    fi
    _run "Installing Yarn via Corepack" \
        bash -c "sudo npm install -g corepack && sudo corepack enable"
}

# ── Module main() — called from installer.sh ────────────────────────────
main() {
    clear
    echo
    echo -e "  ${CY}${BD}⚡  BLUEPRINT FRAMEWORK INSTALLER${BK}   ${DM}— Option 1${BK}"
    echo
    echo -e "  ${CY}┌──────────────────────────────────────────────────────────┐${BK}"
    echo -e "  ${CY}│${BK}   ${WH}${BD}📦  Installing Blueprint Framework on Pterodactyl${BK}    ${CY}│${BK}"
    echo -e "  ${CY}│${BK}   ${DM}Log file: ${WH}${LOG_FILE}${BK}                            ${CY}│${BK}"
    echo -e "  ${CY}└──────────────────────────────────────────────────────────┘${BK}"
    echo

    _check_privileges
    _check_existing || return 0

    _log "Starting Blueprint Framework installation"

    _section "System Update"
    _run "Updating package lists"  sudo apt-get update -y
    _run "Upgrading system packages" sudo apt-get upgrade -y

    _section "Installing Dependencies"
    for pkg in curl wget unzip git zip ca-certificates gnupg lsb-release; do
        _ensure_pkg "$pkg"
    done

    if [[ ! -d "/var/www/pterodactyl" ]]; then
        echo -e "  ${RD}✖  /var/www/pterodactyl not found.${BK}"
        echo -e "  ${RD}   Please install Pterodactyl Panel first!${BK}"
        echo
        exit 1
    fi

    cd /var/www/pterodactyl || exit 1

    _section "Fetching Latest Blueprint Release"

    local latest_url
    latest_url=$(curl -fsSL \
        https://api.github.com/repos/BlueprintFramework/framework/releases/latest \
        | grep '"browser_download_url"' \
        | grep '\.zip' \
        | head -n 1 \
        | cut -d'"' -f4)

    if [[ -z "$latest_url" ]]; then
        echo -e "  ${RD}✖  Failed to fetch latest release URL from GitHub.${BK}"
        exit 1
    fi

    printf "  ${DM}➜${BK}  Release URL: ${CY}%s${BK}\n" "$latest_url"
    echo

    _run "Downloading Blueprint release"  wget -q "$latest_url" -O blueprint.zip
    _run "Extracting Blueprint archive"   unzip -oq blueprint.zip
    _run "Cleaning up archive"            rm -f blueprint.zip

    _section "Node.js & Yarn Setup"
    _setup_node
    _setup_yarn
    _run "Installing frontend dependencies" yarn install --production=false

    _section "Blueprint Configuration"
    if [[ ! -f "/var/www/pterodactyl/.blueprintrc" ]]; then
        sudo tee /var/www/pterodactyl/.blueprintrc >/dev/null <<EOF
WEBUSER="www-data"
OWNERSHIP="www-data:www-data"
USERSHELL="/bin/bash"
EOF
        printf "  ${GR}✔${BK}  %-55s\n" "Created .blueprintrc configuration"
        _log "Created .blueprintrc"
    else
        printf "  ${GR}✔${BK}  %-50s ${DM}(already exists)${BK}\n" ".blueprintrc"
    fi

    _section "Running Blueprint Installer"

    if [[ ! -f "/var/www/pterodactyl/blueprint.sh" ]]; then
        echo -e "  ${RD}✖  blueprint.sh not found — extraction may have failed.${BK}"
        exit 1
    fi

    sudo chmod +x /var/www/pterodactyl/blueprint.sh

    _run "Running blueprint.sh installer" sudo bash /var/www/pterodactyl/blueprint.sh
    _log "Blueprint installer ran successfully"

    sudo touch /var/www/pterodactyl/.blueprint-installed
    _log "Installation marked complete"

    echo
    echo -e "  ${CY}╔══════════════════════════════════════════════════════════╗${BK}"
    echo -e "  ${CY}║${BK}   ${GR}${BD}✔  Blueprint Framework Installed Successfully!${BK}       ${CY}║${BK}"
    echo -e "  ${CY}╠══════════════════════════════════════════════════════════╣${BK}"
    echo -e "  ${CY}║${BK}   ${WH}Next steps:${BK}                                            ${CY}║${BK}"
    printf  "  ${CY}║${BK}   ${DM}1. ${WH}sudo php artisan cache:clear%-21s${BK} ${CY}║${BK}\n" ""
    printf  "  ${CY}║${BK}   ${DM}2. ${WH}sudo php artisan queue:restart%-19s${BK} ${CY}║${BK}\n" ""
    printf  "  ${CY}║${BK}   ${DM}3. View log: ${WH}%-39s${BK} ${CY}║${BK}\n" "$LOG_FILE"
    echo -e "  ${CY}╚══════════════════════════════════════════════════════════╝${BK}"
    echo
}
