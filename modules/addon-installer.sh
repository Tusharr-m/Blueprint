#!/usr/bin/env bash

BP_PTERO_DIR="/var/www/pterodactyl"

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

# ── Braille spinner ─────────────────────────────────────────────────────
_spin() {
    local pid="$1"
    local msg="$2"
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0

    tput civis 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${MG}%s${BK}  ${DM}Installing: ${WH}%s${BK}  " "${frames[$i]}" "$msg"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done
    tput cnorm 2>/dev/null
}

# ── Section divider ─────────────────────────────────────────────────────
_section() {
    echo
    echo -e "  ${CY}${BD}── $* ──────────────────────────────────────────${BK}"
    echo
}

# ── Scan /var/www/pterodactyl for .blueprint files ──────────────────────
_scan_blueprints() {
    ADDON_FILES=()

    while IFS= read -r f; do
        ADDON_FILES+=("$(basename "$f")")
    done < <(find "$BP_PTERO_DIR" -maxdepth 1 -name "*.blueprint" -type f 2>/dev/null | sort)

    if [[ ${#ADDON_FILES[@]} -eq 0 ]]; then
        echo
        echo -e "  ${YL}╔══════════════════════════════════════════════════════════╗${BK}"
        echo -e "  ${YL}║  ⚠  No .blueprint files found                            ║${BK}"
        echo -e "  ${YL}╠══════════════════════════════════════════════════════════╣${BK}"
        printf  "  ${YL}║${BK}  Directory : %-43s ${YL}║${BK}\n" "$BP_PTERO_DIR"
        echo -e "  ${YL}║${BK}  Use ${MG}Option 3${BK} first to download blueprints from GitHub.  ${YL}║${BK}"
        echo -e "  ${YL}╚══════════════════════════════════════════════════════════╝${BK}"
        echo
        return 1
    fi
}

# ── Interactive file picker ─────────────────────────────────────────────
_show_picker() {
    echo -e "  ${CY}┌──────────────────────────────────────────────────────────┐${BK}"
    echo -e "  ${CY}│${BK}   ${WH}${BD}🧩  Addon Installer${BK}   ${DM}— Select blueprints to install  ${CY}│${BK}"
    echo -e "  ${CY}├──────────────────────────────────────────────────────────┤${BK}"
    printf  "  ${CY}│${BK}   ${DM}Found ${WH}%d${DM} blueprint(s) in ${WH}%s${BK}%-13s ${CY}│${BK}\n" \
        "${#ADDON_FILES[@]}" "$BP_PTERO_DIR" ""
    echo -e "  ${CY}├──────────────────────────────────────────────────────────┤${BK}"
    echo -e "  ${CY}│${BK}                                                          ${CY}│${BK}"

    for i in "${!ADDON_FILES[@]}"; do
        printf "  ${CY}│${BK}   ${MG}[%2d]${BK}  %-49s ${CY}│${BK}\n" "$(( i + 1 ))" "${ADDON_FILES[$i]}"
    done

    echo -e "  ${CY}│${BK}                                                          ${CY}│${BK}"
    echo -e "  ${CY}├──────────────────────────────────────────────────────────┤${BK}"
    printf  "  ${CY}│${BK}   ${YL}[ 0]${BK}  %-49s ${CY}│${BK}\n" "⚡  Install ALL addons"
    echo -e "  ${CY}└──────────────────────────────────────────────────────────┘${BK}"
    echo
    echo -e "  ${DM}Tip: Enter multiple numbers separated by spaces → 1 2 3${BK}"
    echo
    printf  "  ${DM}➜${BK}  ${YL}Your selection:${BK} "
    read -r ADDON_SELECTION
}

# ── Resolve selection to addon array ────────────────────────────────────
_resolve_selection() {
    SELECTED_ADDONS=()

    if [[ "$ADDON_SELECTION" == "0" ]]; then
        SELECTED_ADDONS=("${ADDON_FILES[@]}")
        echo -e "  ${GR}✔${BK}  All ${WH}${BD}${#ADDON_FILES[@]}${BK} addon(s) selected."
    else
        local seen=()
        for num in $ADDON_SELECTION; do
            if [[ "$num" =~ ^[0-9]+$ ]] && \
               [[ "$num" -ge 1 ]] && \
               [[ "$num" -le ${#ADDON_FILES[@]} ]]; then
                local idx=$(( num - 1 ))
                if [[ ! " ${seen[*]} " =~ " ${idx} " ]]; then
                    SELECTED_ADDONS+=("${ADDON_FILES[$idx]}")
                    seen+=("$idx")
                fi
            else
                echo -e "  ${YL}⚠  Skipping invalid input: ${WH}${num}${BK}"
            fi
        done

        if [[ ${#SELECTED_ADDONS[@]} -eq 0 ]]; then
            echo -e "  ${RD}✖  No valid addons selected.${BK}"
            return 1
        fi

        echo -e "  ${GR}✔${BK}  ${WH}${BD}${#SELECTED_ADDONS[@]}${BK} addon(s) selected."
    fi
    echo
}

# ── Run blueprint -install for each selected file ───────────────────────
_run_installs() {
    local ok_list=()
    local fail_list=()

    _section "Installing Addons"

    cd "$BP_PTERO_DIR" || {
        echo -e "  ${RD}✖  Cannot enter directory: ${WH}${BP_PTERO_DIR}${BK}"
        return 1
    }

    for i in "${!SELECTED_ADDONS[@]}"; do
        local addon="${SELECTED_ADDONS[$i]}"

        printf "  ${DM}[%d/%d]${BK}  " "$(( i + 1 ))" "${#SELECTED_ADDONS[@]}"

        ( blueprint -install "$addon" &>/dev/null ) &
        local pid=$!
        _spin "$pid" "$addon"

        if wait "$pid"; then
            printf "\r  ${GR}✔${BK}  %-55s\n" "$addon"
            ok_list+=("$addon")
        else
            printf "\r  ${RD}✖${BK}  Failed: %-49s\n" "$addon"
            fail_list+=("$addon")
        fi
    done

    echo
    echo -e "  ${CY}╔══════════════════════════════════════════════════════════╗${BK}"
    echo -e "  ${CY}║${BK}   ${WH}${BD}📊  Install Summary${BK}                                   ${CY}║${BK}"
    echo -e "  ${CY}╠══════════════════════════════════════════════════════════╣${BK}"
    printf  "  ${CY}║${BK}   ${GR}✔  Installed : %-42s${BK} ${CY}║${BK}\n" "${#ok_list[@]} addon(s)"
    printf  "  ${CY}║${BK}   ${RD}✖  Failed    : %-42s${BK} ${CY}║${BK}\n" "${#fail_list[@]} addon(s)"
    echo -e "  ${CY}╠══════════════════════════════════════════════════════════╣${BK}"

    if [[ ${#ok_list[@]} -gt 0 ]]; then
        echo -e "  ${CY}║${BK}   ${GR}Successfully installed:${BK}                              ${CY}║${BK}"
        for f in "${ok_list[@]}"; do
            printf "  ${CY}║${BK}      ${GR}%-54s${BK} ${CY}║${BK}\n" "$f"
        done
        [[ ${#fail_list[@]} -gt 0 ]] && echo -e "  ${CY}╠══════════════════════════════════════════════════════════╣${BK}"
    fi

    if [[ ${#fail_list[@]} -gt 0 ]]; then
        echo -e "  ${CY}║${BK}   ${RD}Failed — check blueprint logs:${BK}                       ${CY}║${BK}"
        for f in "${fail_list[@]}"; do
            printf "  ${CY}║${BK}      ${RD}%-54s${BK} ${CY}║${BK}\n" "$f"
        done
    fi

    echo -e "  ${CY}╚══════════════════════════════════════════════════════════╝${BK}"
    echo

    if [[ ${#fail_list[@]} -eq 0 ]]; then
        echo -e "  ${GR}${BD}🎉  All addons installed successfully!${BK}"
    else
        echo -e "  ${YL}⚠  Some addons failed. Check the blueprint logs for details.${BK}"
    fi
    echo
}

# ── Module entry point (called from installer.sh) ───────────────────────
main() {
    clear
    echo
    echo -e "  ${YL}${BD}🧩  ADDON INSTALLER${BK}   ${DM}— Option 2${BK}"
    echo

    _scan_blueprints         || return 1
    _show_picker
    _resolve_selection       || return 1
    _run_installs
}
