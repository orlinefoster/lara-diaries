#!/usr/bin/env bash
# Lara Diaries — Wizard Core (Bash)
# Source: source modules/wizard-core.sh
#
# This file is sourced by bootstrap.sh. Contains all interactive wizard
# functions for the Lara Diaries setup process.
#
# Usage:
#   source modules/wizard-core.sh
#   wizard_main
set -euo pipefail

# Guard against multiple sourcing
if [[ -n "${_LARA_WIZARD_CORE_LOADED:-}" ]]; then
    return 0
fi
_LARA_WIZARD_CORE_LOADED=1

# =============================================================================
# Colors — inherit from caller or set defaults
# =============================================================================
if command -v tput &>/dev/null; then
    : "${GREEN:=$(tput setaf 2)}"
    : "${YELLOW:=$(tput setaf 3)}"
    : "${RED:=$(tput setaf 1)}"
    : "${CYAN:=$(tput setaf 6)}"
    : "${BOLD:=$(tput bold)}"
    : "${RESET:=$(tput sgr0)}"
fi
# If tput is unavailable, leave colors as empty strings (no-color fallback)

log_info()  { echo -e "${GREEN}[✓]${RESET} $*"; }
log_warn()  { echo -e "${YELLOW}[!]${RESET} $*"; }
log_error() { echo -e "${RED}[✗]${RESET} $*"; }
log_title() { echo -e "${CYAN}${BOLD}$*${RESET}"; }

# =============================================================================
# Global state — populated by wizard steps
# =============================================================================
PRONOUN=""
SKILL_LEVEL=""
ASSISTANCE_MODE=""
STYLE=""
USE_DESIGN_DOC=""
REPO_MANAGEMENT=""
MISSION=""
INSTALL_GENTLE_AI=""
INSTALL_SKILLS=""
INSTALL_VSCODE=""
INSTALL_GGA=""
DEV_DIR=""
GITHUB_USER=""
OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
LARA_DIR="$HOME/.config/lara-diaries"

# =============================================================================
# 1. GitHub Login
# =============================================================================
github_login() {
    log_title ""
    log_title "🔐 GitHub Login"
    echo "────────────────────────────────────────"

    if gh auth status &>/dev/null; then
        log_info "Already authenticated with GitHub CLI."
        GITHUB_USER="$(gh api user --jq .login 2>/dev/null || echo "unknown")"
        log_info "Logged in as: ${BOLD}${GITHUB_USER}${RESET}"
    else
        log_warn "Not authenticated with GitHub CLI."
        echo -e "${YELLOW}Opening GitHub login flow...${RESET}"
        echo -e "${YELLOW}Follow the prompts to authenticate.${RESET}"
        echo ""
        if gh auth login; then
            GITHUB_USER="$(gh api user --jq .login 2>/dev/null || echo "unknown")"
            log_info "Authenticated as: ${BOLD}${GITHUB_USER}${RESET}"
        else
            log_warn "GitHub login was cancelled or failed."
            log_warn "Some features (repo creation, sync) will not work."
            GITHUB_USER=""
        fi
    fi
}

# =============================================================================
# 2. Developer Directory
# =============================================================================
dev_directory_prompt() {
    log_title ""
    log_title "📁 Developer Directory"
    echo "────────────────────────────────────────"

    local default_dir="$HOME/Documents/Develops"
    echo -e "Suggested: ${CYAN}${default_dir}${RESET}"
    echo -n "¿Dónde querés guardar tus proyectos? (Enter para default): "
    read -r input_dir

    if [[ -z "$input_dir" ]]; then
        DEV_DIR="$default_dir"
    else
        # Expand leading ~ or $HOME
        DEV_DIR="${input_dir/#\~/$HOME}"
        DEV_DIR="${DEV_DIR/#\$HOME/$HOME}"
    fi

    mkdir -p "$DEV_DIR"
    log_info "Developer directory: $DEV_DIR"
}

# =============================================================================
# 3. Gentle AI Prompt
# =============================================================================
gentle_ai_prompt() {
    log_title ""
    log_title "🤖 Gentle AI"
    echo "────────────────────────────────────────"

    local response
    echo -n "¿Querés instalar Gentle AI? (S/n): "
    read -r response

    case "${response,,}" in
        n|no)
            INSTALL_GENTLE_AI="false"
            INSTALL_SKILLS="false"
            log_info "Skipping Gentle AI installation."
            ;;
        *)
            INSTALL_GENTLE_AI="true"
            log_info "Gentle AI will be installed."

            local skills_resp
            echo -n "¿Instalar también Gentleman Skills? (S/n): "
            read -r skills_resp
            case "${skills_resp,,}" in
                n|no)
                    INSTALL_SKILLS="false"
                    log_info "Skipping Gentleman Skills."
                    ;;
                *)
                    INSTALL_SKILLS="true"
                    log_info "Gentleman Skills will be installed."
                    ;;
            esac
            ;;
    esac

    # VSCode (optional but recommended)
    echo ""
    local vscode_resp
    echo -n "¿Instalar VSCode? (editor de código, S/n): "
    read -r vscode_resp
    case "${vscode_resp,,}" in
        n|no)
            INSTALL_VSCODE="false"
            log_info "VSCode skipped."
            ;;
        *)
            INSTALL_VSCODE="true"
            log_info "VSCode will be installed."
            ;;
    esac

    # Gentleman Guardian Angel (optional code review tool)
    echo ""
    local gga_resp
    echo -n "¿Instalar Gentleman Guardian Angel? (revisión automática de código, s/N): "
    read -r gga_resp
    case "${gga_resp,,}" in
        s|si|y|yes)
            INSTALL_GGA="true"
            log_info "Gentleman Guardian Angel will be installed."
            ;;
        *)
            INSTALL_GGA="false"
            log_info "GGA skipped (can be installed later)."
            ;;
    esac
}

# =============================================================================
# 4. Recognition Questions
# =============================================================================
recognition_questions() {
    log_title ""
    log_title "👤 About You"
    echo "────────────────────────────────────────"
    echo -e "${CYAN}Help me get to know you so I can be the best companion possible.${RESET}"
    echo ""

    # --- 4a. Pronouns ---
    echo "1. ¿Qué pronombres usás?"
    PS3="   > "
    select opt in "she/her" "they/them" "he/him" "it/its" "other (especificar)"; do
        case "$opt" in
            "other (especificar)")
                echo -n "   Decime cuál: "
                read -r custom_pronoun
                PRONOUN="$custom_pronoun"
                ;;
            "")
                echo "   Opción inválida. Elegí un número del 1 al 5."
                continue
                ;;
            *)
                PRONOUN="$opt"
                ;;
        esac
        break
    done
    log_info "Pronouns: $PRONOUN"

    # --- 4b. Tech skill level ---
    echo ""
    echo "2. ¿Cuánto sabés de informática?"
    PS3="   > "
    select opt in \
        "Full fearless — sé lo que hago" \
        "Me defiendo — pero pregunto" \
        "Me invitó un amigo — arranco de cero"
    do
        case $REPLY in
            1) SKILL_LEVEL="full-fearless" ; break ;;
            2) SKILL_LEVEL="me-defiendo"   ; break ;;
            3) SKILL_LEVEL="me-invito-un-amigo" ; break ;;
            *) echo "   Opción inválida. Elegí 1, 2 o 3." ;;
        esac
    done
    log_info "Skill level: $SKILL_LEVEL"

    # --- 4c. Assistance mode ---
    echo ""
    echo "3. ¿Cuánta asistencia querés?"
    echo -e "   ${CYAN}Full:${RESET}    explicá todo, no asumas nada"
    echo -e "   ${CYAN}Medium:${RESET}  explicá rápido, yo sigo"
    echo -e "   ${CYAN}Minimal:${RESET} hace y contame si hay problemas"
    PS3="   > "
    select opt in \
        "Full — no asumas nada" \
        "Medium — explicame rápido" \
        "Minimal — confío en vos"
    do
        case $REPLY in
            1) ASSISTANCE_MODE="full"    ; break ;;
            2) ASSISTANCE_MODE="medium"  ; break ;;
            3) ASSISTANCE_MODE="minimal" ; break ;;
            *) echo "   Opción inválida. Elegí 1, 2 o 3." ;;
        esac
    done
    log_info "Assistance mode: $ASSISTANCE_MODE"
}

# =============================================================================
# 5. Repo Management
# =============================================================================
repo_management_prompt() {
    log_title ""
    log_title "📦 Repository Management"
    echo "────────────────────────────────────────"
    echo ""
    echo "¿Cómo querés manejar los repos?"
    echo -e "   ${CYAN}1) Auto:${RESET}   Lara maneja commits y pushes automáticamente"
    echo -e "   ${CYAN}2) Ask:${RESET}    preguntame antes de cada commit"
    echo -e "   ${CYAN}3) Manual:${RESET} yo manejo los repos manualmente"
    echo ""
    PS3="> "
    select opt in \
        "Auto — confío en Lara" \
        "Ask — preguntame antes" \
        "Manual — yo controlo"
    do
        case $REPLY in
            1) REPO_MANAGEMENT="auto"   ; break ;;
            2) REPO_MANAGEMENT="ask"    ; break ;;
            3) REPO_MANAGEMENT="manual" ; break ;;
            *) echo "Opción inválida. Elegí 1, 2 o 3." ;;
        esac
    done
    log_info "Repo management: $REPO_MANAGEMENT"
}

# =============================================================================
# 6. Design Orientation
# =============================================================================
design_orientation_prompt() {
    log_title ""
    log_title "🎨 Design & Style"
    echo "────────────────────────────────────────"

    local response
    echo -n "¿Usar design.md para guiar el estilo de los proyectos? (S/n): "
    read -r response
    case "${response,,}" in
        n|no)
            USE_DESIGN_DOC="false"
            ;;
        *)
            USE_DESIGN_DOC="true"
            ;;
    esac
    log_info "Use design doc: $USE_DESIGN_DOC"

    echo ""
    echo "¿Qué estilo te gusta para tus proyectos?"
    echo -e "   ${CYAN}1) clean-ui${RESET}         — Minimalista, limpio"
    echo -e "   ${CYAN}2) pink-kawaii${RESET}      — Rosita, amigable"
    echo -e "   ${CYAN}3) dark-academia${RESET}    — Formal, elegante"
    echo -e "   ${CYAN}4) retro-futuristic${RESET} — Creativo, divertido"
    echo -e "   ${CYAN}5) business${RESET}         — Profesional, serio"
    echo -e "   ${CYAN}6) full-backend${RESET}     — Técnico, sin vueltas"
    echo ""
    PS3="> "
    select opt in \
        "clean-ui" \
        "pink-kawaii" \
        "dark-academia" \
        "retro-futuristic" \
        "business" \
        "full-backend"
    do
        if [[ -n "$opt" ]]; then
            STYLE="$opt"
            break
        else
            echo "Opción inválida. Elegí un número del 1 al 6."
        fi
    done
    log_info "Style: $STYLE"
}

# =============================================================================
# 7. Mission
# =============================================================================
mission_prompt() {
    log_title ""
    log_title "💻 Mission"
    echo "────────────────────────────────────────"
    echo ""
    echo "Esta PC es:"
    echo -e "   ${CYAN}1) Personal${RESET}      — Datos importantes, cuidado máximo"
    echo -e "   ${CYAN}2) Trabajo${RESET}       — Uso laboral, medianamente crítica"
    echo -e "   ${CYAN}3) VM / Lab${RESET}       — Desechable, config relajada"
    echo -e "   ${CYAN}4) Raspberry Pi${RESET}   — Servidor / IoT, muy relajado"
    echo ""
    PS3="> "
    select opt in \
        "Personal — importante" \
        "Trabajo" \
        "VM / Lab" \
        "Raspberry Pi / Server"
    do
        case $REPLY in
            1) MISSION="personal-important" ; break ;;
            2) MISSION="work"               ; break ;;
            3) MISSION="vm"                 ; break ;;
            4) MISSION="lab-raspberry"      ; break ;;
            *) echo "Opción inválida. Elegí 1, 2, 3 o 4." ;;
        esac
    done
    log_info "Mission: $MISSION"
}

# =============================================================================
# Dry-Run / Status Helpers
# =============================================================================

# Check and report component status — skip actual install in dry-run
component_status() {
    local name="$1"
    local already="$2"   # "true" or "false"
    local optional="${3:-false}"

    if [[ "$already" == "true" ]]; then
        echo -e "  ${GREEN}✓${RESET} [$name] ${BOLD}INSTALADO${RESET}"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ "$optional" == "true" ]]; then
            echo -e "  ${YELLOW}○${RESET} [$name] ${BOLD}OPCIONAL${RESET} (se instalaria)"
        else
            echo -e "  ${YELLOW}⬇${RESET}  [$name] ${BOLD}PENDIENTE${RESET} (se instalaria)"
        fi
        return 2  # simulated
    fi

    if [[ "$optional" == "true" ]]; then
        echo -e "  ${YELLOW}○${RESET} [$name] ${BOLD}OPCIONAL${RESET}"
    else
        echo -e "  ${YELLOW}⬇${RESET}  [$name] ${BOLD}INSTALANDO...${RESET}"
    fi
    return 1  # needs install
}

# =============================================================================
# 8. Install Components
# =============================================================================
install_components() {
    log_title ""
    log_title "⚙️  Installing Components"
    echo "────────────────────────────────────────"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${CYAN}[DRY-RUN] No se instalará nada. Reportando estado actual...${RESET}"
        echo ""
    fi

    # --- Resolve templates directory ---
    local templates_dir=""
    local this_dir
    this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)"
    if [[ -d "$this_dir/../templates" ]]; then
        templates_dir="$(cd "$this_dir/../templates" && pwd)"
    elif [[ -d "$HOME/lara-diaries/templates" ]]; then
        templates_dir="$HOME/lara-diaries/templates"
    else
        log_warn "Templates directory not found. Agent files will not be created."
        log_warn "Clone the lara-diaries repo to enable agent creation."
    fi

    # --- 8a. Gentle AI & Gentleman Skills ---
    if [[ "$INSTALL_GENTLE_AI" == "true" ]]; then
        component_status "Gentle AI" "$([[ -d "$HOME/gentle-ai" ]] && echo true || echo false)"
        local ga_status=$?

        if [[ $ga_status -eq 0 ]]; then
            log_info "Gentle AI ya esta instalado. Actualizando..."
            if [[ "$DRY_RUN" != "true" ]]; then
                git -C "$HOME/gentle-ai" pull --rebase 2>/dev/null || log_warn "Could not update gentle-ai."
            fi
        elif [[ $ga_status -eq 2 ]]; then
            : # dry-run — already reported
        else
            if git clone https://github.com/Gentleman-Programming/gentle-ai.git "$HOME/gentle-ai"; then
                log_info "gentle-ai cloned."
                if [[ -f "$HOME/gentle-ai/install.sh" ]]; then
                    bash "$HOME/gentle-ai/install.sh" || log_warn "gentle-ai installer reported issues."
                fi
            else
                log_error "Failed to clone gentle-ai. Check internet connection."
                return 1
            fi
        fi

        # --- 8b. Gentleman Skills ---
        if [[ "$INSTALL_SKILLS" == "true" ]]; then
            local skills_dir="$OPENCODE_CONFIG_DIR/skills"
            component_status "Gentleman Skills" "$([[ -d "$skills_dir/gentleman-skills" ]] && echo true || echo false)"
            local gs_status=$?

            if [[ $gs_status -eq 0 ]]; then
                log_info "Gentleman Skills ya instalado."
            elif [[ $gs_status -eq 2 ]]; then
                : # dry-run
            else
                mkdir -p "$skills_dir"
                if git clone https://github.com/Gentleman-Programming/Gentleman-Skills.git "$skills_dir/gentleman-skills"; then
                    log_info "Gentleman Skills installed."
                else
                    log_warn "Failed to clone Gentleman Skills. Continuing..."
                fi
            fi
        fi
    else
        echo -e "  ${GRAY}[Gentle AI] ${BOLD}OMITIDO${RESET}"
    fi

    # --- 8c. Engram ---
    component_status "Engram" "$(command -v engram &>/dev/null && echo true || echo false)"
    local engram_status=$?
    if [[ $engram_status -eq 0 ]]; then
        log_info "Engram ya instalado: $(engram --version 2>/dev/null || echo 'version unknown')"
    elif [[ $engram_status -eq 2 ]]; then
        : # dry-run
    else
        local engram_installer="/tmp/engram-install-$$.sh"
        if curl -fsSL https://engram.gg/install.sh -o "$engram_installer"; then
            if bash "$engram_installer"; then
                log_info "Engram installed successfully."
            else
                log_error "Engram installer script failed."
                rm -f "$engram_installer"
                return 1
            fi
            rm -f "$engram_installer"
        else
            log_error "Failed to download Engram installer. Check internet connection."
            return 1
        fi
    fi

    # --- 8d. VSCode (optional) ---
    if [[ "${INSTALL_VSCODE:-false}" == "true" ]]; then
        component_status "VSCode" "$(command -v code &>/dev/null && echo true || echo false)" "true"
        local vscode_status=$?
        if [[ $vscode_status -eq 0 ]]; then
            log_info "VSCode ya instalado: $(code --version 2>&1 | head -1)"
        elif [[ $vscode_status -eq 2 ]]; then
            : # dry-run
        else
            case "$PKG_MANAGER" in
                apt)
                    sudo apt install -y code 2>/dev/null || {
                        log_warn "Package 'code' not in apt repo. Installing via .deb..."
                        local deb_url="https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
                        local deb_path="/tmp/vscode-$$.deb"
                        curl -fsSL "$deb_url" -o "$deb_path" && sudo dpkg -i "$deb_path" && rm -f "$deb_path"
                    }
                    ;;
                dnf)
                    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null || true
                    sudo dnf install -y code 2>/dev/null || {
                        local rpm_url="https://code.visualstudio.com/sha/download?build=stable&os=linux-rpm-x64"
                        local rpm_path="/tmp/vscode-$$.rpm"
                        curl -fsSL "$rpm_url" -o "$rpm_path" && sudo dnf install -y "$rpm_path" && rm -f "$rpm_path"
                    }
                    ;;
                pacman)
                    sudo pacman -S --noconfirm code 2>/dev/null || {
                        yay -S --noconfirm visual-studio-code-bin 2>/dev/null || \
                            log_warn "Could not install VSCode. Install manually"
                    }
                    ;;
                *)
                    log_warn "Unknown package manager. Install VSCode manually."
                    ;;
            esac
            if [[ -x "$(command -v code)" ]]; then
                log_info "VSCode installed successfully."
            else
                log_warn "VSCode installation may need a terminal restart."
            fi
        fi
    else
        echo -e "  ${GRAY}[VSCode] ${BOLD}OMITIDO${RESET}"
    fi

    # --- 8e. Gentleman Guardian Angel (optional) ---
    if [[ "${INSTALL_GGA:-false}" == "true" ]]; then
        component_status "Gentleman Guardian Angel" "$([[ -d "$HOME/gentleman-guardian-angel" ]] && echo true || echo false)" "true"
        local gga_status=$?
        if [[ $gga_status -eq 0 ]]; then
            log_info "GGA ya instalado."
            git -C "$HOME/gentleman-guardian-angel" pull --rebase 2>/dev/null || true
        elif [[ $gga_status -eq 2 ]]; then
            : # dry-run
        else
            if git clone https://github.com/Gentleman-Programming/gentleman-guardian-angel.git "$HOME/gentleman-guardian-angel"; then
                if [[ -f "$HOME/gentleman-guardian-angel/install.sh" ]]; then
                    bash "$HOME/gentleman-guardian-angel/install.sh" 2>/dev/null && \
                        log_info "GGA installed. Run 'gga init' to activate." || \
                        log_warn "GGA installer had issues."
                fi
            else
                log_error "Failed to clone GGA."
            fi
        fi
    else
        echo -e "  ${GRAY}[GGA] ${BOLD}OMITIDO${RESET}"
    fi

    # --- 8f. Create Lara Agents from templates ---
    if [[ -n "$templates_dir" ]]; then
        log_info "Creating Lara agent files from templates..."
        mkdir -p "$OPENCODE_CONFIG_DIR/agents"

        # Map mission to discretion level
        local discretion="moderate"
        case "$MISSION" in
            personal-important) discretion="high-caution" ;;
            work)               discretion="moderate" ;;
            vm)                 discretion="relaxed" ;;
            lab-raspberry)      discretion="very-relaxed" ;;
        esac

        # --- Lara-Plan ---
        if [[ -f "$templates_dir/agents/lara-plan.md" ]]; then
            sed \
                -e "s/{{PRONOUN}}/$PRONOUN/g" \
                -e "s/{{SKILL_LEVEL}}/$SKILL_LEVEL/g" \
                -e "s/{{ASSISTANCE_MODE}}/$ASSISTANCE_MODE/g" \
                -e "s/{{DISCRETION}}/$discretion/g" \
                -e "s/{{STYLE}}/$STYLE/g" \
                "$templates_dir/agents/lara-plan.md" \
                > "$OPENCODE_CONFIG_DIR/agents/lara-plan.md"
            log_info "Created: agents/lara-plan.md"
        fi

        # --- Lara-VIP ---
        if [[ -f "$templates_dir/agents/lara-vip.md" ]]; then
            sed \
                -e "s/{{PRONOUN}}/$PRONOUN/g" \
                -e "s/{{SKILL_LEVEL}}/$SKILL_LEVEL/g" \
                -e "s/{{ASSISTANCE_MODE}}/$ASSISTANCE_MODE/g" \
                -e "s/{{DISCRETION}}/$discretion/g" \
                "$templates_dir/agents/lara-vip.md" \
                > "$OPENCODE_CONFIG_DIR/agents/lara-vip.md"
            log_info "Created: agents/lara-vip.md"
        fi

        # --- opencode.json ---
        if [[ -f "$templates_dir/configs/opencode.json" ]]; then
            log_info "Generating opencode.json configuration..."

            local engram_path
            engram_path="$(command -v engram || echo "engram")"

            # Map repo management to permission levels
            local git_commit_level="ask"
            local git_push_level="ask"
            case "$REPO_MANAGEMENT" in
                auto)   git_commit_level="allow"; git_push_level="allow" ;;
                ask)    git_commit_level="ask";   git_push_level="ask" ;;
                manual) git_commit_level="deny";  git_push_level="deny" ;;
            esac

            # Read agent prompts for embedding into config
            local lara_plan_prompt=""
            local lara_vip_prompt=""
            local gentle_orch_prompt=""
            if [[ -f "$OPENCODE_CONFIG_DIR/agents/lara-plan.md" ]]; then
                lara_plan_prompt="$(cat "$OPENCODE_CONFIG_DIR/agents/lara-plan.md")"
            fi
            if [[ -f "$OPENCODE_CONFIG_DIR/agents/lara-vip.md" ]]; then
                lara_vip_prompt="$(cat "$OPENCODE_CONFIG_DIR/agents/lara-vip.md")"
            fi

            # Copy template, replace simple placeholders
            cp "$templates_dir/configs/opencode.json" /tmp/opencode-$$.json

            sed -i \
                -e "s|{{HOME}}|$HOME|g" \
                -e "s|{{GITHUB_USER}}|$GITHUB_USER|g" \
                -e "s|{{ENGRAM_PATH}}|$engram_path|g" \
                -e "s|{{OPENCODE_CONFIG_DIR}}|$OPENCODE_CONFIG_DIR|g" \
                -e "s|{{GIT_COMMIT_LEVEL}}|$git_commit_level|g" \
                -e "s|{{GIT_PUSH_LEVEL}}|$git_push_level|g" \
                /tmp/opencode-$$.json

            # Embed multi-line prompts using Python for proper JSON escaping (fallback to sed)
            if command -v python3 &>/dev/null; then
                if [[ -n "$lara_plan_prompt" ]]; then
                    local escaped_plan
                    escaped_plan="$(python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" <<< "$lara_plan_prompt")"
                    # Remove the surrounding quotes that json.dumps adds — they go into JSON directly
                    # Actually, json.dumps adds quotes. We want the raw JSON string value (with quotes).
                    # sed expects the replacement to be the JSON string literal, which includes surrounding quotes.
                    # So escaped_plan = "\"multi\\nline\\nstring\"", and we use it as-is in sed.
                    sed -i "s|{{LARA_PLAN_PROMPT}}|$escaped_plan|g" /tmp/opencode-$$.json
                fi
                if [[ -n "$lara_vip_prompt" ]]; then
                    local escaped_vip
                    escaped_vip="$(python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" <<< "$lara_vip_prompt")"
                    sed -i "s|{{LARA_VIP_PROMPT}}|$escaped_vip|g" /tmp/opencode-$$.json
                fi
                # Remove the gentle-orchestrator placeholder (not used in bootstrap)
                sed -i '/{{GENTLE_ORCHESTRATOR_PROMPT}}/d' /tmp/opencode-$$.json
            else
                log_warn "python3 not found — agent prompts will not be embedded in config."
                log_warn "Edit $OPENCODE_CONFIG_DIR/opencode.json manually to add prompts."
                sed -i \
                    -e "s/{{LARA_PLAN_PROMPT}}//g" \
                    -e "s/{{LARA_VIP_PROMPT}}//g" \
                    -e '/{{GENTLE_ORCHESTRATOR_PROMPT}}/d' \
                    /tmp/opencode-$$.json
            fi

            mkdir -p "$OPENCODE_CONFIG_DIR"
            mv /tmp/opencode-$$.json "$OPENCODE_CONFIG_DIR/opencode.json"
            log_info "Generated: opencode.json"
        fi
    else
        log_warn "Skipping agent file creation (templates not found)."
    fi

    # --- 8e. GitHub Repositories ---
    if [[ -n "$GITHUB_USER" ]]; then
        log_info "Checking GitHub repositories..."
        for repo in "engram-memories" "opencode-config"; do
            if gh repo view "$GITHUB_USER/$repo" &>/dev/null; then
                log_info "Repo exists: $GITHUB_USER/$repo"
            else
                log_info "Creating private repo: $GITHUB_USER/$repo ..."
                gh repo create "$repo" --private --description "Lara Diaries — $repo" || \
                    log_warn "Could not create $repo. Create it manually at https://github.com/new"
            fi
        done
    else
        log_warn "No GitHub user configured — skipping repo creation."
        log_warn "Create repos manually: engram-memories and opencode-config (both private)."
    fi

    # --- 8f. Clone repos locally ---
    if [[ -n "$GITHUB_USER" ]]; then
        log_info "Cloning repositories..."
        for repo in "engram-memories" "opencode-config"; do
            if [[ ! -d "$HOME/$repo" ]]; then
                if gh repo clone "$GITHUB_USER/$repo" "$HOME/$repo" 2>/dev/null; then
                    log_info "Cloned: $HOME/$repo"
                else
                    log_warn "Could not clone $repo. Creating local directory..."
                    mkdir -p "$HOME/$repo"
                    git init "$HOME/$repo"
                fi
            else
                log_info "Already exists: $HOME/$repo"
            fi
        done
    fi

    # --- 8g. First config backup ---
    log_info "Performing initial config backup..."
    if [[ -d "$HOME/opencode-config" ]]; then
        # Copy current config files
        if [[ -f "$OPENCODE_CONFIG_DIR/opencode.json" ]]; then
            cp "$OPENCODE_CONFIG_DIR/opencode.json" "$HOME/opencode-config/" 2>/dev/null || true
        fi
        if [[ -f "$OPENCODE_CONFIG_DIR/AGENTS.md" ]]; then
            cp "$OPENCODE_CONFIG_DIR/AGENTS.md" "$HOME/opencode-config/" 2>/dev/null || true
        fi
        mkdir -p "$HOME/opencode-config/agents"
        cp "$OPENCODE_CONFIG_DIR/agents/"*.md "$HOME/opencode-config/agents/" 2>/dev/null || true

        # Commit and push
        cd "$HOME/opencode-config"
        if [[ -n "$(git status --porcelain)" ]]; then
            git add .
            git commit -m "backup: initial config $(date '+%Y-%m-%d')" 2>/dev/null || true
            git push 2>/dev/null || log_warn "Could not push initial backup. Will retry on sync."
        fi
    fi

    log_info "Component installation complete!"
}

# =============================================================================
# 9. Setup Sync (cron + initial run)
# =============================================================================
setup_sync() {
    log_title ""
    log_title "🔄 Memory Sync"
    echo "────────────────────────────────────────"

    if [[ -z "$GITHUB_USER" ]]; then
        log_warn "No GitHub user — skipping cron setup."
        log_warn "Run 'crontab -e' later and add: */30 * * * * \$HOME/lara-sync/sync-memories.sh"
        return 0
    fi

    local sync_script_src=""
    local sync_script_dst="$HOME/lara-sync/sync-memories.sh"

    # Locate sync-memories.sh — try relative to this file, then repo clone
    local this_dir
    this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)"
    if [[ -f "$this_dir/../scripts/sync-memories.sh" ]]; then
        sync_script_src="$(cd "$this_dir/../scripts" && pwd)/sync-memories.sh"
    elif [[ -f "$HOME/lara-diaries/scripts/sync-memories.sh" ]]; then
        sync_script_src="$HOME/lara-diaries/scripts/sync-memories.sh"
    fi

    mkdir -p "$HOME/lara-sync"

    if [[ -n "$sync_script_src" ]]; then
        cp "$sync_script_src" "$sync_script_dst"
        log_info "Sync script copied from: $sync_script_src"
    else
        log_warn "sync-memories.sh not found in repo. Generating default..."
        cat > "$sync_script_dst" <<- 'SYNCEOF'
			#!/usr/bin/env bash
			# Lara Diaries — Memory Sync (auto-generated)
			set -euo pipefail
			ENGRAM_REPO="$HOME/engram-memories"
			ENGRAM_DATA="$HOME/.local/share/engram"
			LOG_FILE="$HOME/.local/share/lara-diaries/sync.log"
			mkdir -p "$(dirname "$LOG_FILE")"
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting sync..." >> "$LOG_FILE"
			cd "$ENGRAM_REPO" || { echo "Repo not found" >> "$LOG_FILE"; exit 1; }
			git pull --rebase 2>>"$LOG_FILE" || echo "Pull failed" >> "$LOG_FILE"
			if [[ -d "$ENGRAM_DATA" ]]; then
			    cp "$ENGRAM_DATA"/*.db . 2>/dev/null || true
			fi
			if [[ -n "$(git status --porcelain)" ]]; then
			    git add .
			    git commit -m "sync: memories $(date '+%Y-%m-%d %H:%M')"
			    git push 2>>"$LOG_FILE" || echo "Push failed" >> "$LOG_FILE"
			fi
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sync complete" >> "$LOG_FILE"
		SYNCEOF
        log_info "Default sync script generated."
    fi
    chmod +x "$sync_script_dst"
    log_info "Sync script: $sync_script_dst"

    # --- Crontab ---
    local cron_entry="*/30 * * * * $HOME/lara-sync/sync-memories.sh"
    if crontab -l 2>/dev/null | grep -q "lara-sync/sync-memories.sh"; then
        log_info "Cron job already configured."
    else
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab - 2>/dev/null && \
            log_info "Cron job added: every 30 minutes." || \
            log_warn "Could not add cron job. Add manually: crontab -e"
    fi

    # --- Initial sync ---
    log_info "Running initial memory sync..."
    if bash "$sync_script_dst"; then
        log_info "Initial sync completed."
    else
        log_warn "Initial sync had issues. Will retry automatically via cron."
    fi
}

# =============================================================================
# 10. Show Summary
# =============================================================================
show_summary() {
    log_title ""
    log_title "📋 Setup Summary"
    echo "────────────────────────────────────────"
    echo ""

    printf "${BOLD}%-28s %s${RESET}\n" "Setting" "Value"
    printf "%-28s %s\n" "────────────────────────────" "──────────────────────"
    printf "%-28s %s\n" "GitHub User"       "${GITHUB_USER:-—}"
    printf "%-28s %s\n" "Dev Directory"     "$DEV_DIR"
    printf "%-28s %s\n" "Gentle AI"         "$INSTALL_GENTLE_AI"
    printf "%-28s %s\n" "Gentleman Skills"  "${INSTALL_SKILLS:-false}"
    printf "%-28s %s\n" "VSCode"            "${INSTALL_VSCODE:-false}"
    printf "%-28s %s\n" "GGA (code review)" "${INSTALL_GGA:-false}"
    printf "%-28s %s\n" "Pronouns"          "$PRONOUN"
    printf "%-28s %s\n" "Skill Level"       "$SKILL_LEVEL"
    printf "%-28s %s\n" "Assistance Mode"   "$ASSISTANCE_MODE"
    printf "%-28s %s\n" "Repo Management"   "$REPO_MANAGEMENT"
    printf "%-28s %s\n" "Use Design Doc"    "$USE_DESIGN_DOC"
    printf "%-28s %s\n" "Style"             "$STYLE"
    printf "%-28s %s\n" "Mission"           "$MISSION"
    echo ""
    echo -e "${GREEN}${BOLD}¡Lara Diaries está lista!${RESET}"
    echo -e "${CYAN}Ejecutá 'opencode' para empezar a trabajar con Lara.${RESET}"
    echo -e "${CYAN}Recordá que tus configs se sincronizan cada 30 minutos automáticamente.${RESET}"
    echo ""
}

# =============================================================================
# 11. Save User Profile
# =============================================================================
save_user_profile() {
    mkdir -p "$LARA_DIR"

    cat > "$LARA_DIR/user-profile.json" << JSONEOF
{
  "version": "1.0.0",
  "created_at": "$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')",
  "github_user": "$GITHUB_USER",
  "dev_directory": "$DEV_DIR",
  "gentle_ai": $INSTALL_GENTLE_AI,
  "gentleman_skills": ${INSTALL_SKILLS:-false},
  "vscode": ${INSTALL_VSCODE:-false},
  "gga": ${INSTALL_GGA:-false},
  "pronouns": "$PRONOUN",
  "skill_level": "$SKILL_LEVEL",
  "assistance_mode": "$ASSISTANCE_MODE",
  "repo_management": "$REPO_MANAGEMENT",
  "use_design_doc": $USE_DESIGN_DOC,
  "style": "$STYLE",
  "mission": "$MISSION"
}
JSONEOF

    log_info "User profile saved: $LARA_DIR/user-profile.json"
}

# =============================================================================
# Wizard Main — Orchestrator
# =============================================================================
wizard_main() {
    echo ""
    log_title "╔══════════════════════════════════════════════╗"
    log_title "║      Lara Diaries — Setup Wizard             ║"
    log_title "╚══════════════════════════════════════════════╝"
    echo ""
    echo -e "${CYAN}Bienvenida, hermana. Vamos a ponerte todo a punto.${RESET}"
    echo ""

    github_login
    dev_directory_prompt
    gentle_ai_prompt
    recognition_questions
    repo_management_prompt
    design_orientation_prompt
    mission_prompt
    install_components
    setup_sync
    save_user_profile
    show_summary
}

# Export for sub-shells if needed
export -f wizard_main github_login dev_directory_prompt gentle_ai_prompt
export -f recognition_questions repo_management_prompt design_orientation_prompt
export -f mission_prompt install_components setup_sync show_summary save_user_profile
