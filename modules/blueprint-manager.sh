#!/usr/bin/env bash

# ── Constants ──────────────────────────────────────────────────────────
readonly BP_TEMP_DIR="/tmp/blueprints"
readonly BP_DEST_DIR="/var/www/pterodactyl"
readonly BP_RAW_BASE="https://raw.githubusercontent.com"
readonly BP_API_BASE="https://api.github.com/repos"

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

# ── Braille spinner animation ──────────────────────────────────────────
_spinner() {
    local pid="$1"
    local msg="$2"
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0

    tput civis 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${MG}%s${BK}  ${DM}%s${BK}  " "${frames[$i]}" "$msg"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.08
    done
    tput cnorm 2>/dev/null
    printf "\r  ${GR}✔${BK}  %-55s\n" "$msg"
}

# ── Styled error panel ─────────────────────────────────────────────────
_error() {
    echo
    echo -e "  ${RD}╔══════════════════════════════════════════════════╗${BK}"
    echo -e "  ${RD}║  ✖  Error                                        ║${BK}"
    echo -e "  ${RD}╠══════════════════════════════════════════════════╣${BK}"
    printf  "  ${RD}║${BK}  %-48s ${RD}║${BK}\n" "$*"
    echo -e "  ${RD}╚══════════════════════════════════════════════════╝${BK}"
    echo
}

# ── Section divider ────────────────────────────────────────────────────
_section() {
    echo
    echo -e "  ${CY}${BD}── $* ──────────────────────────────────────────${BK}"
    echo
}

# ── Pre-flight checks ──────────────────────────────────────────────────
_preflight() {
    if [[ ! -d "$BP_DEST_DIR" ]]; then
        _error "Pterodactyl not found at ${BP_DEST_DIR} — install it first."
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        echo -e "  ${YL}⚡  jq not found — installing automatically...${BK}"
        echo
        sudo apt-get install -y jq -qq 2>/dev/null || {
            _error "Failed to install jq. Run: sudo apt install jq"
            return 1
        }
        echo -e "  ${GR}✔  jq installed successfully${BK}"
        echo
    fi

    mkdir -p "$BP_TEMP_DIR"
}

# ── Prompt for GitHub repo details ─────────────────────────────────────
_get_repo() {
    echo -e "  ${CY}┌──────────────────────────────────────────────────────────┐${BK}"
    echo -e "  ${CY}│${BK}   ${WH}${BD}🔽  Download Blueprints from GitHub${BK}                    ${CY}│${BK}"
    echo -e "  ${CY}├──────────────────────────────────────────────────────────┤${BK}"
    echo -e "  ${CY}│${BK}   ${DM}Format  : owner/repo-name${BK}                             ${CY}│${BK}"
    echo -e "  ${CY}│${BK}   ${DM}Example : tushar/blueprint-addons${BK}                     ${CY}│${BK}"
    echo -e "  ${CY}└──────────────────────────────────────────────────────────┘${BK}"
    echo

    printf "  ${DM}➜${BK}  ${YL}GitHub Repo [owner/repo]:${BK} "
    read -r BP_REPO

    if [[ -z "$BP_REPO" || "$BP_REPO" != *"/"* ]]; then
        _error "Invalid format. Use: owner/repo-name"
        return 1
    fi

    printf "  ${DM}➜${BK}  ${YL}Branch name [default: main]:${BK} "
    read -r BP_BRANCH
    BP_BRANCH="${BP_BRANCH:-main}"

    printf "  ${DM}➜${BK}  ${YL}Subdirectory path [leave blank for root]:${BK} "
    read -r BP_SUBDIR
    BP_SUBDIR="${BP_SUBDIR:-}"
}

# ── Fetch .blueprint file list via GitHub API ──────────────────────────
_fetch_blueprint_list() {
    local api_path="${BP_API_BASE}/${BP_REPO}/contents"
    [[ -n "$BP_SUBDIR" ]] && api_path="${api_path}/${BP_SUBDIR}"

    _section "Fetching blueprint list from GitHub"
    printf "  ${DM}➜${BK}  Querying: ${CY}%s${BK}\n" "$api_path"
    echo

    local response
    response=$(curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$api_path" 2>/dev/null) || {
        _error "Failed to reach GitHub API. Check repo name and internet connection."
        return 1
    }

    if echo "$response" | jq -e '.message' &>/dev/null; then
        local api_msg
        api_msg=$(echo "$response" | jq -r '.message')
        _error "GitHub API: $api_msg"
        return 1
    fi

    BP_FILES=()
    BP_PATHS=()

    while IFS= read -r line; do
        BP_FILES+=("$line")
    done < <(echo "$response" | jq -r '.[] | select(.name | endswith(".blueprint")) | .name' 2>/dev/null)

    while IFS= read -r line; do
        BP_PATHS+=("$line")
    done < <(echo "$response" | jq -r '.[] | select(.name | endswith(".blueprint")) | .path' 2>/dev/null)

    if [[ ${#BP_FILES[@]} -eq 0 ]]; then
        _error "No .blueprint files found in ${BP_REPO}${BP_SUBDIR:+/${BP_SUBDIR}}"
        return 1
    fi

    echo -e "  ${GR}✔${BK}  Found ${WH}${BD}${#BP_FILES[@]}${BK} blueprint file(s)"
    echo
}

# ── Display interactive selection list ────────────────────────────────
_show_selection_menu() {
    echo -e "  ${CY}┌──────────────────────────────────────────────────────────┐${BK}"
    echo -e "  ${CY}│${BK}   ${WH}${BD}📦  Available Blueprints${BK}                               ${CY}│${BK}"
    echo -e "  ${CY}├──────────────────────────────────────────────────────────┤${BK}"
    printf  "  ${CY}│${BK}   ${DM}Repo: ${WH}%-51s${BK} ${CY}│${BK}\n" "${BP_REPO}"
    echo -e "  ${CY}├──────────────────────────────────────────────────────────┤${BK}"
    echo -e "  ${CY}│${BK}                                                          ${CY}│${BK}"

    for i in "${!BP_FILES[@]}"; do
        printf "  ${CY}│${BK}   ${MG}[%2d]${BK}  %-49s ${CY}│${BK}\n" "$(( i + 1 ))" "${BP_FILES[$i]}"
    done

    echo -e "  ${CY}│${BK}                                                          ${CY}│${BK}"
    echo -e "  ${CY}├──────────────────────────────────────────────────────────┤${BK}"
    printf  "  ${CY}│${BK}   ${YL}[ 0]${BK}  %-49s ${CY}│${BK}\n" "⚡  Install ALL blueprints"
    echo -e "  ${CY}└──────────────────────────────────────────────────────────┘${BK}"
    echo
    echo -e "  ${DM}Tip: Enter multiple numbers separated by spaces → 1 2 3${BK}"
    echo
    printf  "  ${DM}➜${BK}  ${YL}Your selection:${BK} "
    read -r BP_SELECTION
}

# ── Resolve user selection to file arrays ──────────────────────────────
_resolve_selection() {
    SELECTED_FILES=()
    SELECTED_PATHS=()

    if [[ "$BP_SELECTION" == "0" ]]; then
        SELECTED_FILES=("${BP_FILES[@]}")
        SELECTED_PATHS=("${BP_PATHS[@]}")
        echo -e "  ${GR}✔${BK}  All ${WH}${BD}${#BP_FILES[@]}${BK} blueprint(s) selected."
    else
        local seen=()
        for num in $BP_SELECTION; do
            if [[ "$num" =~ ^[0-9]+$ ]] && \
               [[ "$num" -ge 1 ]] && \
               [[ "$num" -le ${#BP_FILES[@]} ]]; then
                local idx=$(( num - 1 ))
                if [[ ! " ${seen[*]} " =~ " ${idx} " ]]; then
                    SELECTED_FILES+=("${BP_FILES[$idx]}")
                    SELECTED_PATHS+=("${BP_PATHS[$idx]}")
                    seen+=("$idx")
                fi
            else
                echo -e "  ${YL}⚠  Skipping invalid input: ${WH}${num}${BK}"
            fi
        done

        if [[ ${#SELECTED_FILES[@]} -eq 0 ]]; then
            _error "No valid blueprints selected. Please try again."
            return 1
        fi

        echo -e "  ${GR}✔${BK}  ${WH}${BD}${#SELECTED_FILES[@]}${BK} blueprint(s) selected."
    fi
    echo
}

# ── Confirm before download ────────────────────────────────────────────
_confirm_download() {
    echo -e "  ${CY}┌──────────────────────────────────────────────────────────┐${BK}"
    echo -e "  ${CY}│${BK}   ${WH}${BD}📋  Download Summary${BK}                                   ${CY}│${BK}"
    echo -e "  ${CY}├──────────────────────────────────────────────────────────┤${BK}"

    for f in "${SELECTED_FILES[@]}"; do
        printf "  ${CY}│${BK}   ${GR}✔${BK}  %-53s ${CY}│${BK}\n" "$f"
    done

    echo -e "  ${CY}├──────────────────────────────────────────────────────────┤${BK}"
    printf  "  ${CY}│${BK}   ${DM}Destination : ${WH}%-43s${BK} ${CY}│${BK}\n" "$BP_DEST_DIR"
    printf  "  ${CY}│${BK}   ${DM}Branch      : ${WH}%-43s${BK} ${CY}│${BK}\n" "$BP_BRANCH"
    echo -e "  ${CY}├──────────────────────────────────────────────────────────┤${BK}"
    echo -e "  ${CY}│${BK}   ${DM}⚠  Files will be downloaded only, NOT activated.     ${CY}│${BK}"
    echo -e "  ${CY}│${BK}   ${DM}   Use Option 2 to run blueprint -install afterward.  ${CY}│${BK}"
    echo -e "  ${CY}└──────────────────────────────────────────────────────────┘${BK}"
    echo

    printf "  ${DM}➜${BK}  ${YL}Proceed with download? [y/N]:${BK} "
    read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]]
}

# ── Download a single .blueprint file with spinner ─────────────────────
_download_file() {
    local filepath="$1"
    local filename="$2"
    local raw_url="${BP_RAW_BASE}/${BP_REPO}/${BP_BRANCH}/${filepath}"
    local dest_tmp="${BP_TEMP_DIR}/${filename}"

    (
        curl -fsSL "$raw_url" -o "$dest_tmp" 2>/dev/null
    ) &
    local dl_pid=$!
    _spinner "$dl_pid" "Downloading  ${filename}"

    if ! wait "$dl_pid"; then
        printf "  ${RD}✖${BK}  Download failed: %-40s\n" "$filename"
        FAILED_FILES+=("$filename")
        return 1
    fi

    if sudo mv "$dest_tmp" "${BP_DEST_DIR}/${filename}" 2>/dev/null; then
        SUCCESS_FILES+=("$filename")
    else
        printf "  ${RD}✖${BK}  Move failed (permission?): %-30s\n" "$filename"
        FAILED_FILES+=("$filename")
        return 1
    fi
}

# ── Run all selected downloads ─────────────────────────────────────────
_run_downloads() {
    SUCCESS_FILES=()
    FAILED_FILES=()

    _section "Downloading Blueprints"
    echo -e "  ${DM}Temp dir    : ${WH}${BP_TEMP_DIR}${BK}"
    echo -e "  ${DM}Destination : ${WH}${BP_DEST_DIR}${BK}"
    echo -e "  ${DM}Source      : ${WH}${BP_RAW_BASE}/${BP_REPO}/${BP_BRANCH}/${BK}"
    echo

    for i in "${!SELECTED_FILES[@]}"; do
        local filename="${SELECTED_FILES[$i]}"
        local filepath="${SELECTED_PATHS[$i]}"
        printf "  ${DM}[%d/%d]${BK}  " "$(( i + 1 ))" "${#SELECTED_FILES[@]}"
        _download_file "$filepath" "$filename"
    done
}

# ── Final summary panel ────────────────────────────────────────────────
_show_summary() {
    echo
    echo -e "  ${CY}╔══════════════════════════════════════════════════════════╗${BK}"
    echo -e "  ${CY}║${BK}   ${WH}${BD}📊  Download Summary${BK}                                  ${CY}║${BK}"
    echo -e "  ${CY}╠══════════════════════════════════════════════════════════╣${BK}"

    if [[ ${#SUCCESS_FILES[@]} -gt 0 ]]; then
        echo -e "  ${CY}║${BK}   ${GR}✔  Successfully transferred:${BK}                          ${CY}║${BK}"
        for f in "${SUCCESS_FILES[@]}"; do
            printf "  ${CY}║${BK}      ${GR}%-54s${BK} ${CY}║${BK}\n" "$f"
        done
        echo -e "  ${CY}╠══════════════════════════════════════════════════════════╣${BK}"
    fi

    if [[ ${#FAILED_FILES[@]} -gt 0 ]]; then
        echo -e "  ${CY}║${BK}   ${RD}✖  Failed:${BK}                                            ${CY}║${BK}"
        for f in "${FAILED_FILES[@]}"; do
            printf "  ${CY}║${BK}      ${RD}%-54s${BK} ${CY}║${BK}\n" "$f"
        done
        echo -e "  ${CY}╠══════════════════════════════════════════════════════════╣${BK}"
    fi

    printf  "  ${CY}║${BK}   ${DM}Total : ${GR}%d success${BK}  /  ${RD}%d failed${BK}%-22s ${CY}║${BK}\n" \
        "${#SUCCESS_FILES[@]}" "${#FAILED_FILES[@]}" ""
    echo -e "  ${CY}╠══════════════════════════════════════════════════════════╣${BK}"
    echo -e "  ${CY}║${BK}   ${WH}Next step:${BK} Go back → ${MG}Option 2${BK} → Addon Installer       ${CY}║${BK}"
    echo -e "  ${CY}║${BK}   ${DM}to run blueprint -install on your downloaded files.  ${CY}║${BK}"
    echo -e "  ${CY}╚══════════════════════════════════════════════════════════╝${BK}"
    echo
}

# ── Module entry point ──────────────────────────────────────────────────
bp_manager_main() {
    clear
    echo
    echo -e "  ${MG}${BD}⚡  BLUEPRINT MANAGER${BK}   ${DM}— GitHub Downloader${BK}"
    echo

    _preflight            || return 1
    _get_repo             || return 1
    _fetch_blueprint_list || return 1
    _show_selection_menu
    _resolve_selection    || return 1

    if ! _confirm_download; then
        echo
        echo -e "  ${YL}⚠  Download cancelled by user.${BK}"
        echo
        return 0
    fi

    _run_downloads
    _show_summary

    if [[ ${#SUCCESS_FILES[@]} -gt 0 ]]; then
        echo -e "  ${GR}${BD}✔  All selected blueprints transferred successfully!${BK}"
        echo -e "  ${DM}   Files are now in: ${WH}${BP_DEST_DIR}${BK}"
        echo
    fi
}
