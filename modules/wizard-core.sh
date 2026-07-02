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
    : "${GRAY:=$(tput setaf 8 2>/dev/null || echo '\e[90m')}"
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
# Rollback & Step State Helpers
# =============================================================================

# Rollback: remove a directory (used for failed git clones)
rollback_remove_dir() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        log_warn "  Rollback: eliminando $dir"
        rm -rf "$dir" 2>/dev/null || true
    fi
}

# Rollback: restore a backed-up config file
rollback_config() {
    local backup="$1"
    local original="$2"
    if [[ -f "$backup" ]]; then
        log_warn "  Rollback: restaurando $original desde backup"
        cp "$backup" "$original" 2>/dev/null || true
    fi
}

# Write step state to state.json
wizard_step_state() {
    local step_name="$1"
    local status="$2"
    local error_msg="${3:-}"
    local rollback_action="${4:-}"

    # Use bootstrap.sh's lara_step_state if available
    if command -v lara_step_state &>/dev/null; then
        lara_step_state "$step_name" "$status" "${error_msg:-null}" "${rollback_action:-null}"
        return
    fi

    # Standalone fallback
    local state_dir="$HOME/.config/lara-diaries"
    local state_file="$state_dir/state.json"
    mkdir -p "$state_dir" 2>/dev/null

    local now
    now="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z')"

    # Read existing state or create new
    local state_content=""
    if [[ -f "$state_file" ]]; then
        state_content="$(cat "$state_file" 2>/dev/null || echo "")"
    fi

    local new_json=""
    if [[ -n "$state_content" ]] && echo "$state_content" | grep -q '"version"' 2>/dev/null; then
        if command -v python3 &>/dev/null; then
            # Pass ALL values via environment variables to prevent shell injection
            # into the Python code. Using env vars avoids string interpolation.
            new_json="$(LWS_STEP_NAME="$step_name" \
            LWS_STATUS="$status" \
            LWS_ERROR_MSG="${error_msg:-}" \
            LWS_ROLLBACK="${rollback_action:-}" \
            LWS_NOW="$now" \
            LWS_STATE_CONTENT="$state_content" \
            python3 -c "
import json, os

state_content = os.environ.get('LWS_STATE_CONTENT', '')
state = json.loads(state_content)
if 'steps' not in state:
    state['steps'] = {}

step_name = os.environ.get('LWS_STEP_NAME', '')
status = os.environ.get('LWS_STATUS', '')
error_msg = os.environ.get('LWS_ERROR_MSG', '') or None
rollback = os.environ.get('LWS_ROLLBACK', '') or None
now = os.environ.get('LWS_NOW', '')

step = state['steps'].get(step_name, {})
step['status'] = status
step['error'] = error_msg
step['rollback'] = rollback

if status in ('success', 'failed', 'skipped'):
    step['completed_at'] = now
elif 'completed_at' not in step or step.get('completed_at') is None:
    step['completed_at'] = None
if 'started_at' not in step:
    step['started_at'] = now

state['steps'][step_name] = step
state['updated_at'] = now
print(json.dumps(state, indent=2))
")"
        fi
    fi

    if [[ -z "$new_json" ]]; then
        # Create fresh state (use python3 for safe JSON generation)
        if command -v python3 &>/dev/null; then
            new_json="$(LWS_STEP_NAME="$step_name" \
            LWS_STATUS="$status" \
            LWS_ERROR_MSG="${error_msg:-}" \
            LWS_ROLLBACK="${rollback_action:-}" \
            LWS_NOW="$now" \
            python3 -c "
import json, os, uuid
step_name = os.environ.get('LWS_STEP_NAME', '')
status = os.environ.get('LWS_STATUS', '')
error_msg = os.environ.get('LWS_ERROR_MSG', '') or None
rollback = os.environ.get('LWS_ROLLBACK', '') or None
now = os.environ.get('LWS_NOW', '')

state = {
    'version': 1,
    'install_id': str(uuid.uuid4()),
    'created_at': now,
    'updated_at': now,
    'install_type': 'fresh',
    'steps': {
        step_name: {
            'status': status,
            'started_at': now,
            'completed_at': now if status in ('success', 'failed', 'skipped') else None,
            'error': error_msg,
            'rollback': rollback
        }
    }
}
print(json.dumps(state, indent=2))
")"
        else
            # Last resort fallback (no python3 available)
            local install_id
            install_id="$(uuidgen 2>/dev/null || date '+%s')"
            new_json='{
  "version": 1,
  "install_id": "'"$install_id"'",
  "created_at": "'"$now"'",
  "updated_at": "'"$now"'",
  "install_type": "fresh",
  "steps": {
    "'"$step_name"'": {
      "status": "'"$status"'",
      "started_at": "'"$now"'",
      "completed_at": '"$(if [[ "$status" == "success" || "$status" == "failed" || "$status" == "skipped" ]]; then echo "\"$now\""; else echo "null"; fi)"',
      "error": '"${error_msg:-null}"',
      "rollback": '"${rollback_action:-null}"'
    }
  }
}'
        fi
    fi

    if [[ -n "$new_json" ]]; then
        printf '%s\n' "$new_json" > "$state_file"
    fi
}

# Check if a step is already completed (for resume)
wizard_step_is_done() {
    local step_name="$1"
    local state_file="$HOME/.config/lara-diaries/state.json"
    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    # Use python3 for exact JSON parsing (preferred)
    if command -v python3 &>/dev/null; then
        STATUS_CHECK="$step_name" python3 -c "
import json, os, sys
step_name = os.environ['STATUS_CHECK']
with open('$state_file') as f:
    state = json.load(f)
step = state.get('steps', {}).get(step_name)
if step and step.get('status') == 'success':
    sys.exit(0)
else:
    sys.exit(1)
" 2>/dev/null && return 0 || return 1
    fi

    # Fallback: jq
    if command -v jq &>/dev/null; then
        jq -e ".steps.\"$step_name\".status == \"success\"" "$state_file" >/dev/null 2>&1 && return 0 || return 1
    fi

    # Last resort: grep/sed (fragile, but no other parser available)
    local status
    status="$(grep -A5 "\"$step_name\"" "$state_file" 2>/dev/null | grep '"status"' | sed 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null)"
    if [[ "$status" == "success" ]]; then
        return 0
    fi
    return 1
}

# Run a step with state tracking and rollback on failure
wizard_run_step() {
    local step_name="$1"
    local step_label="$2"
    local step_func="$3"

    # Skip if already done (resume mode)
    if wizard_step_is_done "$step_name"; then
        log_info "Paso '$step_label' ya completado. Omitiendo."
        return 0
    fi

    # Check for alias step names from the Go binary bridge
    local alias_map="install_components:clone_gentle_ai,setup_gentleman_skills,setup_engram,setup_opencode,setup_vscode"
    case "$step_name" in
        install_components)
            # If ALL Go binary sub-steps are complete, skip this too
            local all_go_done=true
            for substep in clone_gentle_ai setup_gentleman_skills setup_engram setup_opencode setup_vscode; do
                if ! wizard_step_is_done "$substep" 2>/dev/null; then
                    all_go_done=false
                    break
                fi
            done
            if [[ "$all_go_done" == "true" ]]; then
                log_info "Paso '$step_label' ya completado (via Go binary steps). Omitiendo."
                return 0
            fi
            ;;
    esac

    wizard_step_state "$step_name" "running"

    if ! $step_func; then
        log_error "Paso '$step_label' fallo."
        wizard_step_state "$step_name" "failed" "Step '$step_label' failed"
        return 1
    fi

    wizard_step_state "$step_name" "success"
    return 0
}

# =============================================================================
# Extracted Install Helpers (callable from run_go_step bridge)
# =============================================================================

# Install Engram binary from GitHub Releases with Homebrew/go fallback.
# Returns 0 on success, 1 on failure.
install_engram() {
    local engram_ok=false

    # Priority 1: Binary download from GitHub Releases (zero deps — just curl + tar)
    if [[ "$engram_ok" != "true" ]]; then
        log_info "Downloading Engram binary from GitHub Releases..."
        local engram_tmpdir="/tmp/engram-install-$$"
        mkdir -p "$engram_tmpdir"
        trap 'rm -rf "$engram_tmpdir"' EXIT

        local engram_latest_url="https://api.github.com/repos/Gentleman-Programming/engram/releases/latest"
        local engram_response
        engram_response="$(curl -sL -w "\n%{http_code}" "$engram_latest_url")"
        local engram_http_code
        engram_http_code="$(echo "$engram_response" | tail -n1)"
        local engram_body
        engram_body="$(echo "$engram_response" | sed '$d')"

        if [[ "$engram_http_code" == "200" ]]; then
            local engram_tag
            engram_tag="$(echo "$engram_body" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
            local engram_version="${engram_tag#v}"
            local engram_os_arch="linux_amd64"
            [[ "$(uname -s)" == "Darwin" ]] && engram_os_arch="darwin_amd64"
            [[ "$(uname -m)" == "arm64" || "$(uname -m)" == "aarch64" ]] && engram_os_arch="${engram_os_arch%_*}_arm64"

            local engram_archive="engram_${engram_version}_${engram_os_arch}.tar.gz"
            local engram_dl_url="https://github.com/Gentleman-Programming/engram/releases/download/${engram_tag}/${engram_archive}"
            local engram_checksums_url="https://github.com/Gentleman-Programming/engram/releases/download/${engram_tag}/checksums.txt"

            log_info "Downloading ${engram_archive}..."
            if curl -sfL -o "${engram_tmpdir}/${engram_archive}" "$engram_dl_url"; then
                # Verify checksum
                if curl -sL -o "${engram_tmpdir}/checksums.txt" "$engram_checksums_url"; then
                    local engram_expected
                    engram_expected="$(grep "${engram_archive}" "${engram_tmpdir}/checksums.txt" | awk '{print $1}')"
                    local engram_actual
                    if command -v sha256sum &>/dev/null; then
                        engram_actual="$(sha256sum "${engram_tmpdir}/${engram_archive}" | awk '{print $1}')"
                    elif command -v shasum &>/dev/null; then
                        engram_actual="$(shasum -a 256 "${engram_tmpdir}/${engram_archive}" | awk '{print $1}')"
                    fi
                    if [[ -n "$engram_expected" && -n "$engram_actual" && "$engram_expected" == "$engram_actual" ]]; then
                        log_info "Checksum verified."
                    else
                        log_warn "Checksum verification skipped or mismatch."
                    fi
                fi

                # Extract and install
                tar -xzf "${engram_tmpdir}/${engram_archive}" -C "$engram_tmpdir"
                local engram_install_dir="${HOME}/.local/bin"
                mkdir -p "$engram_install_dir"
                if cp "${engram_tmpdir}/engram" "$engram_install_dir/engram" 2>/dev/null; then
                    chmod +x "$engram_install_dir/engram"
                    if [[ ":$PATH:" == *":${engram_install_dir}:"* ]]; then
                        log_info "Engram installed to ${engram_install_dir}/engram"
                    else
                        log_info "Engram installed to ${engram_install_dir}/engram (add to PATH)"
                    fi
                    engram_ok=true
                else
                    log_warn "Could not copy engram binary to ${engram_install_dir}."
                fi
            else
                log_warn "Failed to download Engram binary."
            fi
        else
            log_warn "GitHub API returned HTTP ${engram_http_code} (rate limited?)."
        fi
    fi

    # Priority 2: Homebrew (if user already has it)
    if [[ "$engram_ok" != "true" ]] && command -v brew &>/dev/null; then
        log_info "Homebrew found — installing via brew tap..."
        if brew tap Gentleman-Programming/homebrew-tap 2>/dev/null && brew install engram 2>/dev/null; then
            log_info "Engram installed via Homebrew."
            engram_ok=true
        else
            log_warn "Homebrew install failed, trying fallback..."
        fi
    fi

    # Priority 3: go install (if Go toolchain is available)
    if [[ "$engram_ok" != "true" ]] && command -v go &>/dev/null; then
        log_info "Falling back to go install..."
        if go install github.com/Gentleman-Programming/engram/cmd/engram@latest 2>/dev/null; then
            log_info "Engram installed via go install."
            engram_ok=true
        else
            log_warn "go install failed."
        fi
    fi

    if [[ "$engram_ok" != "true" ]]; then
        log_error "Could not install Engram."
        log_info "Install manually: https://github.com/Gentleman-Programming/engram#quick-start"
        return 1
    fi
    return 0
}

# Copy Lara agent templates with variable substitutions.
# Uses global variables: OPENCODE_CONFIG_DIR, MISSION, PRONOUN, SKILL_LEVEL,
# ASSISTANCE_MODE, STYLE.
copy_agent_templates() {
    local templates_dir="$1"
    if [[ -z "$templates_dir" || ! -d "$templates_dir" ]]; then
        log_error "Templates directory not found: ${templates_dir:-<none>}"
        return 1
    fi

    log_info "Creating Lara agent files from templates..."
    mkdir -p "$OPENCODE_CONFIG_DIR/agents"

    local discretion="moderate"
    case "$MISSION" in
        personal-important) discretion="high-caution" ;;
        work)               discretion="moderate" ;;
        vm)                 discretion="relaxed" ;;
        lab-raspberry)      discretion="very-relaxed" ;;
    esac

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

    return 0
}

# Generate opencode.json from template with variable substitution.
# Uses global variables: OPENCODE_CONFIG_DIR, REPO_MANAGEMENT, templates_dir,
# LARA_PLAN_PROMPT, LARA_VIP_PROMPT.
generate_opencode_json() {
    local templates_dir="$1"
    if [[ -z "$templates_dir" || ! -f "$templates_dir/configs/opencode.json" ]]; then
        log_error "opencode.json template not found in: ${templates_dir:-<none>}"
        return 1
    fi

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
    if [[ -f "$OPENCODE_CONFIG_DIR/agents/lara-plan.md" ]]; then
        lara_plan_prompt="$(cat "$OPENCODE_CONFIG_DIR/agents/lara-plan.md")"
    fi
    if [[ -f "$OPENCODE_CONFIG_DIR/agents/lara-vip.md" ]]; then
        lara_vip_prompt="$(cat "$OPENCODE_CONFIG_DIR/agents/lara-vip.md")"
    fi

    local opencode_output="/tmp/opencode-$$.json"
    local opencode_generated=false

    # Cleanup temp file on exit
    trap 'rm -f "$opencode_output"' RETURN

    # Method 1: python3 — full JSON manipulation (escaping, structure, multi-line)
    if command -v python3 &>/dev/null; then
        ENGRAM_BIN="$engram_path" \
        GIT_COMMIT="$git_commit_level" \
        GIT_PUSH="$git_push_level" \
        LARA_PLAN_PROMPT="${lara_plan_prompt}" \
        LARA_VIP_PROMPT="${lara_vip_prompt}" \
        python3 -c "
import json, os

with open('$templates_dir/configs/opencode.json') as f:
    data = json.load(f)

# MCP engram command path
if os.environ.get('ENGRAM_BIN'):
    data['mcp']['engram']['command'][0] = os.environ['ENGRAM_BIN']

# Git permission levels
git_commit = os.environ.get('GIT_COMMIT', 'ask')
git_push = os.environ.get('GIT_PUSH', 'ask')
data['permission']['bash']['git commit *'] = git_commit
data['permission']['bash']['git push'] = git_push
data['permission']['bash']['git push *'] = git_push

# Agent prompts (multi-line, properly escaped by json.dumps)
if os.environ.get('LARA_PLAN_PROMPT'):
    data['agent']['lara-plan']['prompt'] = os.environ['LARA_PLAN_PROMPT']
if os.environ.get('LARA_VIP_PROMPT'):
    data['agent']['lara-vip']['prompt'] = os.environ['LARA_VIP_PROMPT']

# Remove gentle-orchestrator (not used in bootstrap, template placeholder only)
data['agent'].pop('gentle-orchestrator', None)

with open('$opencode_output', 'w') as f:
    json.dump(data, f, indent=2)
" && opencode_generated=true
    fi

    # Method 2: jq — for simple value replacements (no multi-line prompt support)
    if [[ "$opencode_generated" != "true" ]] && command -v jq &>/dev/null; then
        jq \
            --arg engram "$engram_path" \
            --arg git_commit "$git_commit_level" \
            --arg git_push "$git_push_level" \
            '.mcp.engram.command[0] = $engram
             | .permission.bash."git commit *" = $git_commit
             | .permission.bash."git push" = $git_push
             | .permission.bash."git push *" = $git_push
             | del(.agent."gentle-orchestrator")
             | .agent."lara-plan".prompt = (.agent."lara-plan".prompt | gsub("{{LARA_PLAN_PROMPT}}"; ""))
             | .agent."lara-vip".prompt = (.agent."lara-vip".prompt | gsub("{{LARA_VIP_PROMPT}}"; ""))' \
            "$templates_dir/configs/opencode.json" > "$opencode_output" 2>/dev/null && opencode_generated=true
    fi

    if [[ "$opencode_generated" == "true" ]]; then
        mkdir -p "$OPENCODE_CONFIG_DIR"
        mv "$opencode_output" "$OPENCODE_CONFIG_DIR/opencode.json"
        log_info "Generated: opencode.json"
    else
        log_warn "Neither python3 nor jq available — copying template with placeholders."
        log_warn "Edit $OPENCODE_CONFIG_DIR/opencode.json manually to fill in values."
        cp "$templates_dir/configs/opencode.json" "$OPENCODE_CONFIG_DIR/opencode.json"
    fi
}

# =============================================================================
# install_gentle_ai — install or update Gentle AI
# =============================================================================
install_gentle_ai() {
    component_status "Gentle AI" "$([[ -d "$HOME/gentle-ai" ]] && echo true || echo false)"
    local ga_status=$?

    if [[ $ga_status -eq 0 ]]; then
        log_info "Gentle AI ya esta instalado. Actualizando..."
        if [[ "$DRY_RUN" != "true" ]]; then
            git -C "$HOME/gentle-ai" pull --rebase 2>/dev/null || log_warn "Could not update gentle-ai."
        fi
    elif [[ $ga_status -eq 2 ]]; then
        : # dry-run
    else
        if git clone https://github.com/Gentleman-Programming/gentle-ai.git "$HOME/gentle-ai"; then
            log_info "gentle-ai cloned."
            local ga_installer=""
            if [[ -f "$HOME/gentle-ai/scripts/install.sh" ]]; then
                ga_installer="$HOME/gentle-ai/scripts/install.sh"
            elif [[ -f "$HOME/gentle-ai/install.sh" ]]; then
                ga_installer="$HOME/gentle-ai/install.sh"
            fi
            if [[ -n "$ga_installer" ]]; then
                bash "$ga_installer" || log_warn "gentle-ai installer reported issues."
            else
                if command -v gentle-ai &>/dev/null; then
                    gentle-ai install 2>/dev/null || log_warn "gentle-ai install command failed."
                else
                    log_warn "gentle-ai installer script not found at scripts/install.sh"
                    log_info "Run 'bash $HOME/gentle-ai/scripts/install.sh' manually."
                fi
            fi
        else
            log_error "Failed to clone gentle-ai. Check internet connection."
            rollback_remove_dir "$HOME/gentle-ai"
            return 1
        fi
    fi
}

# =============================================================================
# install_gentleman_skills — clone Gentleman Skills under opencode config dir
# =============================================================================
install_gentleman_skills() {
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
            rollback_remove_dir "$skills_dir/gentleman-skills"
        fi
    fi
}

# =============================================================================
# install_vscode — install Visual Studio Code (optional, platform-aware)
# =============================================================================
install_vscode() {
    component_status "VSCode" "$(command -v code &>/dev/null && echo true || echo false)" "true"
    local vscode_status=$?
    if [[ $vscode_status -eq 0 ]]; then
        log_info "VSCode ya instalado: $(code --version 2>&1 | head -1)"
    elif [[ $vscode_status -eq 2 ]]; then
        : # dry-run
    else
        local PKG_MANAGER=""
        if command -v apt &>/dev/null; then PKG_MANAGER="apt"
        elif command -v dnf &>/dev/null; then PKG_MANAGER="dnf"
        elif command -v pacman &>/dev/null; then PKG_MANAGER="pacman"
        fi
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
}

# =============================================================================
# install_gga — install Gentleman Guardian Angel (optional)
# =============================================================================
install_gga() {
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
            rollback_remove_dir "$HOME/gentleman-guardian-angel"
        fi
    fi
}

# =============================================================================
# setup_github_repos — create and clone GitHub repos for engram and config
# =============================================================================
setup_github_repos() {
    if [[ -z "$GITHUB_USER" ]]; then
        log_warn "No GitHub user configured — skipping repo creation."
        log_warn "Create repos manually: engram-memories and opencode-config (both private)."
        return 0
    fi

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
}

# =============================================================================
# backup_initial_config — back up opencode config to opencode-config repo
# =============================================================================
backup_initial_config() {
    log_info "Performing initial config backup..."
    if [[ ! -d "$HOME/opencode-config" ]]; then
        return 0
    fi
    if [[ -f "$OPENCODE_CONFIG_DIR/opencode.json" ]]; then
        cp "$OPENCODE_CONFIG_DIR/opencode.json" "$HOME/opencode-config/" 2>/dev/null || true
    fi
    if [[ -f "$OPENCODE_CONFIG_DIR/AGENTS.md" ]]; then
        cp "$OPENCODE_CONFIG_DIR/AGENTS.md" "$HOME/opencode-config/" 2>/dev/null || true
    fi
    mkdir -p "$HOME/opencode-config/agents"
    cp "$OPENCODE_CONFIG_DIR/agents/"*.md "$HOME/opencode-config/agents/" 2>/dev/null || true

    cd "$HOME/opencode-config"
    if [[ -n "$(git status --porcelain)" ]]; then
        git add .
        git commit -m "backup: initial config $(date '+%Y-%m-%d')" 2>/dev/null || true
        git push 2>/dev/null || log_warn "Could not push initial backup. Will retry on sync."
    fi
}

# =============================================================================
# wizard_check_only — diagnose system without installing (--check mode)
# =============================================================================
wizard_check_only() {
    log_title "System Check (--check mode)"
    echo "────────────────────────────────────────"
    echo ""

    local all_ok=true

    # Prerequisites
    for cmd in git gh curl; do
        if command -v "$cmd" &>/dev/null; then
            log_info "$cmd: found"
        else
            log_error "$cmd: NOT found"
            all_ok=false
        fi
    done

    # Components
    for comp in "Engram" "VSCode"; do
        local bin=""
        case "$comp" in
            Engram) bin="engram" ;;
            VSCode) bin="code" ;;
        esac
        if command -v "$bin" &>/dev/null; then
            log_info "$comp: installed"
        else
            log_warn "$comp: not installed"
        fi
    done

    # GitHub auth
    if gh auth status &>/dev/null; then
        log_info "GitHub: authenticated"
    else
        log_warn "GitHub: NOT authenticated"
    fi

    # State file
    if [[ -f "$HOME/.config/lara-diaries/state.json" ]]; then
        log_info "State file: exists"
    else
        log_warn "State file: not found (first run)"
    fi

    if [[ "$all_ok" == "true" ]]; then
        log_info "All prerequisites satisfied."
    fi
    return 0
}

# =============================================================================
# wizard_dry_run — show install plan without making changes (--dry-run mode)
# =============================================================================
wizard_dry_run() {
    log_title "Installation Plan (--dry-run mode)"
    echo "────────────────────────────────────────"
    echo ""

    DRY_RUN=true

    # Check prerequisites
    wizard_check_only

    echo ""
    log_title "Plan:"
    echo "  • GitHub Login"
    echo "  • Clone gentle-ai"
    echo "  • Install Gentleman Skills"
    echo "  • Install Engram"
    echo "  • Configure opencode"
    echo "  • Install VSCode (optional)"
    echo "  • Setup sync"
    echo "  • Save profile"
    echo ""
    log_info "Run without --dry-run to execute this plan."
    return 0
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
        install_gentle_ai
        if [[ "$INSTALL_SKILLS" == "true" ]]; then
            install_gentleman_skills
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
        install_engram || return 1
    fi

    # --- 8d. VSCode (optional) ---
    if [[ "${INSTALL_VSCODE:-false}" == "true" ]]; then
        install_vscode
    else
        echo -e "  ${GRAY}[VSCode] ${BOLD}OMITIDO${RESET}"
    fi

    # --- 8e. Gentleman Guardian Angel (optional) ---
    if [[ "${INSTALL_GGA:-false}" == "true" ]]; then
        install_gga
    else
        echo -e "  ${GRAY}[GGA] ${BOLD}OMITIDO${RESET}"
    fi

    # --- 8f. Create Lara Agents from templates ---
    if [[ -n "$templates_dir" ]]; then
        copy_agent_templates "$templates_dir"
        generate_opencode_json "$templates_dir"
    else
        log_warn "Skipping agent file creation (templates not found)."
    fi

    # --- 8g. GitHub Repositories + Clone ---
    setup_github_repos

    # --- 8h. First config backup ---
    backup_initial_config

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
# 12. Non-Interactive Wizard (AI-driven)
# =============================================================================
# Verify JSON is valid using python3 or jq
validate_json() {
    local data="$1"
    if command -v python3 &>/dev/null; then
        python3 -c "import sys,json; json.loads(sys.stdin.read())" <<< "$data" 2>/dev/null
    elif command -v jq &>/dev/null; then
        jq '.' <<< "$data" >/dev/null 2>&1
    else
        return 1
    fi
}

# Extract a value from JSON — supports both python3 and jq
get_json_val() {
    local key="$1"
    local default="$2"
    if [[ "$JSON_PARSER" == "python3" ]]; then
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$key','$default'))" <<< "$JSON_DATA"
    else
        jq -r ".$key // \"$default\"" <<< "$JSON_DATA"
    fi
}

wizard_noninteractive() {
    local input="$1"
    JSON_PARSER=""
    JSON_DATA=""

    # Detect JSON parser
    if command -v python3 &>/dev/null; then
        JSON_PARSER="python3"
    elif command -v jq &>/dev/null; then
        JSON_PARSER="jq"
    else
        log_error "Need python3 or jq to parse JSON config."
        log_error "Install python3 or jq and re-run."
        return 1
    fi

    log_title ""
    log_title "⚡ Non-Interactive Setup"
    echo "────────────────────────────────────────"
    echo ""

    # Detect whether input is a file path or inline JSON
    if [[ "${input:0:1}" == "{" ]]; then
        # Inline JSON string
        JSON_DATA="$input"
        log_info "Loading config from inline JSON..."
    elif [[ -f "$input" ]]; then
        # File path
        log_info "Loading config from: $input"
        JSON_DATA="$(cat "$input")"
    else
        log_error "Invalid input: not a file nor JSON: $input"
        return 1
    fi

    # Validate JSON
    if ! validate_json "$JSON_DATA"; then
        log_error "Invalid JSON format in config input."
        return 1
    fi

    # Validate GitHub auth
    if ! gh auth status &>/dev/null; then
        log_error "GitHub not authenticated. User must run 'gh auth login' first."
        return 1
    fi
    GITHUB_USER="$(gh api user --jq .login 2>/dev/null || echo "")"
    log_info "GitHub: $GITHUB_USER"

    # Parse config
    PRONOUN="$(get_json_val "pronoun" "they/them")"
    SKILL_LEVEL="$(get_json_val "skill_level" "me-defiendo")"
    ASSISTANCE_MODE="$(get_json_val "assistance_mode" "medium")"
    STYLE="$(get_json_val "style" "clean-ui")"
    USE_DESIGN_DOC="$(get_json_val "use_design_doc" "true")"
    REPO_MANAGEMENT="$(get_json_val "repo_mode" "auto")"
    MISSION="$(get_json_val "mission" "personal-important")"
    INSTALL_GENTLE_AI="$(get_json_val "install_gentle_ai" "true")"
    INSTALL_SKILLS="$(get_json_val "install_gentleman_skills" "true")"
    INSTALL_VSCODE="$(get_json_val "install_vscode" "true")"
    INSTALL_GGA="$(get_json_val "install_gga" "false")"

    DEV_DIR="$(get_json_val "dev_dir" "$HOME/Documents/Develops")"
    mkdir -p "$DEV_DIR"

    log_info "Config loaded. Starting installation..."

    # Run install steps
    log_info "[1/3] Installing components..."
    install_components

    log_info "[2/3] Setting up sync..."
    setup_sync

    log_info "[3/3] Saving profile..."
    save_user_profile

    show_summary
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

    # Initialize state for interactive wizard
    if command -v lara_state_init &>/dev/null; then
        lara_state_init "fresh"
    fi

    wizard_run_step "github_login"       "GitHub Login"          github_login
    wizard_run_step "dev_directory"      "Developer Directory"   dev_directory_prompt
    wizard_run_step "gentle_ai"          "Gentle AI"             gentle_ai_prompt
    wizard_run_step "recognition"        "Recognition Questions" recognition_questions
    wizard_run_step "repo_management"    "Repo Management"       repo_management_prompt
    wizard_run_step "design_orientation" "Design & Style"        design_orientation_prompt
    wizard_run_step "mission"            "Mission"               mission_prompt
    wizard_run_step "install_components" "Install Components"    install_components
    wizard_run_step "setup_sync"         "Setup Sync"            setup_sync
    wizard_run_step "save_profile"       "Save Profile"          save_user_profile
    wizard_run_step "show_summary"       "Show Summary"          show_summary
}

# =============================================================================
# Go Binary Step Bridge — called by lara-installer for each install step
# =============================================================================
# Each step is non-interactive and idempotent (checks if already done).
# The Go binary manages lock, state machine, and resume — this just does work.

run_go_step() {
    local step_name="$1"
    local json_config="${2:-${LARA_JSON_CONFIG:-}}"

    # Parse config into global vars if provided (non-interactive mode)
    if [[ -n "$json_config" ]]; then
        # set JSON_DATA so get_json_val() can find it
        JSON_DATA="$json_config"
        GITHUB_USER="$(get_json_val "github_user" "")"
        PRONOUN="$(echo "$json_config" | get_json_val "pronoun" "")"
        SKILL_LEVEL="$(echo "$json_config" | get_json_val "skill_level" "me-defiendo")"
        ASSISTANCE_MODE="$(echo "$json_config" | get_json_val "assistance_mode" "medium")"
        STYLE="$(echo "$json_config" | get_json_val "style" "clean-ui")"
        USE_DESIGN_DOC="$(echo "$json_config" | get_json_val "use_design_doc" "true")"
        REPO_MANAGEMENT="$(echo "$json_config" | get_json_val "repo_mode" "auto")"
        MISSION="$(echo "$json_config" | get_json_val "mission" "personal-important")"
        INSTALL_GENTLE_AI="$(echo "$json_config" | get_json_val "install_gentle_ai" "true")"
        INSTALL_SKILLS="$(echo "$json_config" | get_json_val "install_gentleman_skills" "true")"
        INSTALL_VSCODE="$(echo "$json_config" | get_json_val "install_vscode" "true")"
        INSTALL_GGA="$(echo "$json_config" | get_json_val "install_gga" "false")"
        DEV_DIR="$(echo "$json_config" | get_json_val "dev_dir" "$HOME/Documents/Develops")"
    fi

    case "$step_name" in
        github_login)
            if gh auth status &>/dev/null; then
                GITHUB_USER="$(gh api user --jq .login 2>/dev/null || echo "$GITHUB_USER")"
                log_info "GitHub authenticated as: $GITHUB_USER"
                return 0
            else
                log_error "GitHub not authenticated. Run: gh auth login"
                return 1
            fi
            ;;

        clone_gentle_ai)
            if [[ -d "$HOME/gentle-ai" ]]; then
                log_info "gentle-ai already cloned."
                return 0
            fi
            log_info "Cloning Gentle AI..."
            if git clone https://github.com/Gentleman-Programming/gentle-ai.git "$HOME/gentle-ai"; then
                log_info "gentle-ai cloned."
                return 0
            else
                log_error "Failed to clone gentle-ai."
                return 1
            fi
            ;;

        setup_gentleman_skills)
            local skills_dir="$OPENCODE_CONFIG_DIR"
            [[ -z "$skills_dir" ]] && skills_dir="$HOME/.config/opencode"
            if [[ -d "$skills_dir/skills/gentleman-skills" ]]; then
                log_info "Gentleman Skills already installed."
                return 0
            fi
            log_info "Installing Gentleman Skills..."
            if [[ ! -d "$skills_dir/skills" ]]; then
                mkdir -p "$skills_dir/skills"
            fi
            if git clone https://github.com/Gentleman-Programming/gentleman-skills.git "$skills_dir/skills/gentleman-skills"; then
                log_info "Gentleman Skills installed."
                return 0
            else
                log_error "Failed to install Gentleman Skills."
                return 1
            fi
            ;;

        setup_engram)
            if command -v engram &>/dev/null; then
                log_info "Engram already installed."
                return 0
            fi
            log_info "Installing Engram..."
            if install_engram; then
                log_info "Engram installed."
                return 0
            else
                log_error "Engram installation failed."
                return 1
            fi
            ;;

        setup_opencode)
            log_info "Configuring opencode..."
            local templates_dir=""
            local this_dir
            this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)"
            if [[ -d "$this_dir/../templates" ]]; then
                templates_dir="$(cd "$this_dir/../templates" && pwd)"
            elif [[ -d "$HOME/lara-diaries/templates" ]]; then
                templates_dir="$HOME/lara-diaries/templates"
            fi

            if [[ -n "$templates_dir" ]]; then
                if [[ ! -f "$OPENCODE_CONFIG_DIR/agents/lara-plan.md" ]]; then
                    copy_agent_templates "$templates_dir"
                fi
                if [[ ! -f "$OPENCODE_CONFIG_DIR/opencode.json" ]]; then
                    generate_opencode_json "$templates_dir"
                fi
            else
                log_warn "Templates not found — skipping agent file and config generation."
            fi
            log_info "opencode configured."
            return 0
            ;;

        setup_vscode)
            if ! command -v code &>/dev/null; then
                log_warn "VSCode not found — skipping extension setup."
                return 0
            fi
            if [[ "${INSTALL_VSCODE:-true}" != "true" ]]; then
                log_info "VSCode setup skipped by user preference."
                return 0
            fi
            log_info "Installing VSCode extensions..."
            local extensions=(
                "bierner.markdown-mermaid"
                "yzhang.markdown-all-in-one"
                "opencode.opencode-vscode"
            )
            local installed=0
            for ext in "${extensions[@]}"; do
                if code --install-extension "$ext" --force 2>/dev/null; then
                    ((installed++))
                fi
            done
            log_info "VSCode extensions: $installed/${#extensions[@]} installed."
            return 0
            ;;

        *)
            log_error "Unknown step: $step_name"
            return 1
            ;;
    esac
}

# Export for sub-shells if needed
export -f wizard_main github_login dev_directory_prompt gentle_ai_prompt
export -f recognition_questions repo_management_prompt design_orientation_prompt
export -f mission_prompt install_components setup_sync show_summary save_user_profile
export -f run_go_step
