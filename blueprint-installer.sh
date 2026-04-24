#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

#============ COLORS ============#
CYAN="\e[96m"
GREEN="\e[92m"
RED="\e[91m"
YELLOW="\e[93m"
RESET="\e[0m"

clear

#============ ASCII BANNER ============#
echo -e "${CYAN}"
cat << "EOF"
██████╗ ██╗     ██╗███████╗███████╗ █████╗ ██████╗ ██████╗ 
██╔══██╗██║     ██║╚══███╔╝╚══███╔╝██╔══██╗██╔══██╗██╔══██╗
██████╔╝██║     ██║  ███╔╝   ███╔╝ ███████║██████╔╝██║  ██║
██╔══██╗██║     ██║ ███╔╝   ███╔╝  ██╔══██║██╔══██╗██║  ██║
██████╔╝███████╗██║███████╗███████╗██║  ██║██║  ██║██████╔╝
╚═════╝ ╚══════╝╚═╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ 
                                                           
EOF
echo -e "${RESET}"

echo -e "${GREEN} AUTO BLUEPRINT INSTALLER — BY TUSHAR ${RESET}"
echo

LOG_FILE="/var/log/blueprint-installer.log"
exec > >(tee -a "$LOG_FILE") 2>&1
LIVE_LOG_LINES=10

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

loading() {
    local msg="$1"
    echo -ne "${YELLOW}${msg}${RESET}"
    for _ in {1..3}; do
        echo -ne "."
        sleep 0.3
    done
    echo
}

draw_live_logs() {
    local title="$1"
    local temp_log="$2"
    local spinner="$3"
    local lines=()
    mapfile -t lines < <(tail -n "$LIVE_LOG_LINES" "$temp_log" 2>/dev/null)
    while ((${#lines[@]} < LIVE_LOG_LINES)); do lines=("" "${lines[@]}"); done

    printf "\033[H\033[J"
    echo -e "${CYAN} AUTO BLUEPRINT INSTALLER — BY TUSHAR ${RESET}"
    printf "${YELLOW}Status:${RESET} %s %s\n" "$spinner" "$title"
    printf "${YELLOW}Log file:${RESET} %s\n\n" "$LOG_FILE"
    echo -e "${CYAN}Live logs (last ${LIVE_LOG_LINES} lines):${RESET}"
    for line in "${lines[@]}"; do
        line="${line//$'\r'/}"
        printf "  %s\n" "${line:0:120}"
    done
}

run_live() {
    local msg="$1"
    shift
    local temp_log
    temp_log="$(mktemp)"
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0

    (
        stdbuf -oL -eL "$@" 2>&1 | while IFS= read -r line; do
            printf '%s\n' "$line" >> "$LOG_FILE"
            printf '%s\n' "$line" >> "$temp_log"
        done
    ) &
    local pid=$!
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        draw_live_logs "$msg" "$temp_log" "${frames[$i]}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.2
    done
    tput cnorm 2>/dev/null || true
    draw_live_logs "$msg" "$temp_log" "✔"
    if ! wait "$pid"; then
        rm -f "$temp_log"
        fail "$msg failed"
    fi
    rm -f "$temp_log"
    echo
}

fail() {
    echo -e "${RED}❌ ERROR: $1${RESET}"
    log "ERROR: $1"
    exit 1
}

require() {
    if ! command -v "$1" >/dev/null 2>&1; then
        fail "Missing required command: $1"
    fi
}

check_already_installed() {
    if [[ -f "/var/www/pterodactyl/.blueprint-installed" ]]; then
        echo -e "${YELLOW}⚠️  BLUEPRINT APPEARS TO BE ALREADY INSTALLED.${RESET}"
        read -p "Do you want to reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}INSTALLATION CANCLED.${RESET}"
            exit 0
        fi
    fi
}

check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  Warning: Running as root is not recommended.${RESET}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    elif [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        fail "This script requires sudo privileges. Run with sudo or as root."
    fi
}
install_if_missing() {
    local pkg="$1"
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        run_live "Installing $pkg" sudo apt install -y "$pkg"
        log "Installed package: $pkg"
    else
        log "Package already installed: $pkg"
    fi
}

#============ MAIN SCRIPT ============#
main() {
    log "STARTING BLUEPRINT INSTALLATION"
    
    # Initial checks
    check_privileges
    check_already_installed

    #============ REQUIRED COMMANDS ============#
    loading "Checking system requirements"
    for cmd in curl wget unzip git; do
        require "$cmd"
    done

    #============ SYSTEM UPDATE ============#
    run_live "Updating package lists" sudo apt update -y
    run_live "Upgrading system packages" sudo apt upgrade -y

    #============ INSTALL REQUIRED PACKAGES ============#
    loading "Checking and installing dependencies"
    for pkg in curl wget unzip git zip ca-certificates gnupg lsb-release; do
        install_if_missing "$pkg"
    done

    #============ VERIFY PTERODACTYL DIR ============#
    if [[ ! -d "/var/www/pterodactyl" ]]; then
        fail "/var/www/pterodactyl directory not found. Install Pterodactyl first!"
    fi

    cd /var/www/pterodactyl || fail "Unable to enter Pterodactyl directory"

    #============ DOWNLOAD LATEST BLUEPRINT ============#
    loading "Fetching latest Blueprint release"

    LATEST_URL=$(curl -s https://api.github.com/repos/BlueprintFramework/framework/releases/latest \
        | grep '"browser_download_url"' \
        | grep ".zip" \
        | head -n 1 \
        | cut -d '"' -f 4)

    [[ -z "$LATEST_URL" ]] && fail "Failed to get latest release URL"

    run_live "Downloading Blueprint" wget -q "$LATEST_URL" -O blueprint.zip

    run_live "Extracting Blueprint" unzip -oq blueprint.zip
    rm -f blueprint.zip

    #============ NODE.JS INSTALLATION ============#
    if ! command -v node >/dev/null 2>&1 || ! node --version | grep -q "v20"; then
        loading "Setting up Node.js 20"

        # Remove existing Node.js if wrong version
        if command -v node >/dev/null 2>&1; then
            run_live "Removing existing Node.js version" sudo apt remove -y --purge nodejs npm
            sudo rm -rf /etc/apt/sources.list.d/nodesource.list
        fi

        # Install Node.js 20 using NodeSource
        run_live "Configuring NodeSource repository" bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
        run_live "Refreshing apt metadata" sudo apt update -y
        run_live "Installing Node.js 20" sudo apt install -y nodejs
        
        log "Node.js installed/updated to version 20"
    else
        loading "Node.js 20 already installed"
        log "Node.js 20 already present"
    fi

    #============ YARN SETUP ============#
    if ! command -v yarn >/dev/null 2>&1; then
        run_live "Installing Corepack" sudo npm install -g corepack
        run_live "Enabling Corepack" sudo corepack enable
        log "Yarn installed via corepack"
    else
        loading "Yarn already installed"
        log "Yarn already present"
    fi

    #============ FRONTEND DEPENDENCIES ============#
    run_live "Installing frontend dependencies" yarn install --production=false
    log "Frontend dependencies installed"

    #============ BLUEPRINT CONFIG ============#
    if [[ ! -f "/var/www/pterodactyl/.blueprintrc" ]]; then
        loading "Creating .blueprintrc"
        cat <<EOF | sudo tee /var/www/pterodactyl/.blueprintrc >/dev/null
WEBUSER="www-data"
OWNERSHIP="www-data:www-data"
USERSHELL="/bin/bash"
EOF
        log "Created .blueprintrc configuration"
    else
        loading ".blueprintrc already exists"
        log ".blueprintrc configuration already present"
    fi

    #============ RUN BLUEPRINT INSTALLER ============#
    if [[ ! -f "/var/www/pterodactyl/blueprint.sh" ]]; then
        fail "blueprint.sh missing! Extraction failed!"
    fi

    run_live "Fixing blueprint.sh permissions" sudo chmod +x /var/www/pterodactyl/blueprint.sh

    run_live "Running Blueprint installer" sudo bash /var/www/pterodactyl/blueprint.sh

    #============ MARK AS INSTALLED ============#
    sudo touch /var/www/pterodactyl/.blueprint-installed
    log "Blueprint installation completed successfully"

    #============ COMPLETE ============#
    echo
    echo -e "${GREEN}✔ Blueprint installation completed successfully!${RESET}"
    echo -e "${CYAN}🎉 Your Pterodactyl Blueprint theme is now installed perfectly.${RESET}"
    echo
    echo -e "${YELLOW}Next steps:${RESET}"
    echo -e "${YELLOW}1. Clear cache:${RESET} sudo php artisan cache:clear"
    echo -e "${YELLOW}2. Restart queue:${RESET} sudo php artisan queue:restart"
    echo -e "${YELLOW}3. View logs:${RESET} tail -f $LOG_FILE"
    echo
    echo -e "${GREEN}Installation log: $LOG_FILE${RESET}"
}

# Run main function
main "$@"
