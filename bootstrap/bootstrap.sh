#!/usr/bin/env bash
# Lara Diaries — Linux Bootstrap
# Usage: ./bootstrap.sh [--check] [--dry-run]
#    or: curl -fsSL https://raw.githubusercontent.com/orlinefoster/lara-diaries/main/bootstrap/bootstrap.sh | bash
set -euo pipefail

# ── Parse flags ───────────────────────────────
DRY_RUN=false
CHECK_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --check|-c)   CHECK_ONLY=true  ;;
        --dry-run|-n) DRY_RUN=true     ;;
        --help|-h)
            echo "Usage: ./bootstrap.sh [--check] [--dry-run]"
            echo ""
            echo "  --check, -c    Solo diagnosticar prerequisites. No instala nada."
            echo "  --dry-run, -n  Simular la configuracion completa sin cambios."
            echo "  --help, -h     Mostrar esta ayuda."
            exit 0
            ;;
    esac
done

# =============================================================================
# Colors & Helpers
# =============================================================================
if command -v tput &>/dev/null; then
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    RED=$(tput setaf 1)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    GREEN=""; YELLOW=""; RED=""; CYAN=""; BOLD=""; RESET=""
fi

info()  { echo -e "${GREEN}[✓]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[!]${RESET} $*"; }
error() { echo -e "${RED}[✗]${RESET} $*"; }
title() { echo -e "${CYAN}${BOLD}$*${RESET}"; }

# =============================================================================
# Banner
# =============================================================================
print_banner() {
    echo ""
    title "  _                          ___     _               _  "
    title " | |    __ _ _ __ __ _  ___|_ _|_ _(_)___ _ _   ___(_) "
    title " | |   / _\` | '__/ _\` |/ _ \| || \`_| / -_) ' \ (_-< _  "
    title " | |__| (_| | | | (_| |  __/| || (_| \__ \_| |_/__/(_) "
    title " |_____\__,_|_|  \__,_|\___|___/\__,_|___/            "
    echo ""
    echo -e "${BOLD}Lara Diaries Bootstrap v1.0${RESET}"
    echo -e "${CYAN}Sister, it's gonna be amazing.${RESET}"
    echo ""
}

# =============================================================================
# OS & Distro Detection
# =============================================================================
DISTRO=""
DISTRO_NAME=""
PKG_MANAGER=""
INSTALL_CMD=""

detect_os() {
    local os
    os="$(uname -s)"
    info "OS detected: $os"

    if [[ "$os" != "Linux" ]]; then
        error "This script is for Linux only. Detected: $os"
        exit 1
    fi

    # --- Distro ---
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO="${ID:-unknown}"
        DISTRO_NAME="${NAME:-Unknown Linux}"
    else
        DISTRO="unknown"
        DISTRO_NAME="Unknown Linux"
    fi
    info "Distro: $DISTRO_NAME ($DISTRO)"

    # --- Package manager ---
    if command -v apt &>/dev/null; then
        PKG_MANAGER="apt"
        INSTALL_CMD="sudo apt install -y"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="sudo dnf install -y"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="sudo pacman -S --noconfirm"
    else
        error "No supported package manager found (apt, dnf, pacman)."
        info "Install git, gh (GitHub CLI), and Node.js manually, then re-run."
        exit 1
    fi
    info "Package manager: $PKG_MANAGER"
}

# =============================================================================
# Prerequisites Check
# =============================================================================
check_prerequisites() {
    local missing=()

    echo ""
    title "Checking prerequisites..."

    # --- git ---
    if [[ -x "$(command -v git)" ]]; then
        info "git found: $(git --version 2>&1 | head -1)"
    else
        warn "git not found"
        missing+=("git")
    fi

    # --- gh (GitHub CLI) ---
    if [[ -x "$(command -v gh)" ]]; then
        info "gh found: $(gh --version 2>&1 | head -1)"
    else
        warn "gh (GitHub CLI) not found"
        missing+=("gh")
    fi

    # --- node ---
    if [[ -x "$(command -v node)" ]]; then
        info "node found: $(node --version 2>&1)"
    else
        warn "node not found"
        missing+=("nodejs")
    fi

    # --- code (VSCode - optional) ---
    if [[ -x "$(command -v code)" ]]; then
        info "VSCode found: $(code --version 2>&1 | head -1)"
    else
        warn "VSCode not found (optional — will be offered in the wizard)"
    fi

    # --- Install missing packages ---
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        warn "Missing packages: ${missing[*]}"
        echo -e "${YELLOW}We'll use 'sudo' with $PKG_MANAGER to install them.${RESET}"
        echo -e "${YELLOW}You may be prompted for your sudo password.${RESET}"
        echo ""

        # Translate package names per distro
        local pkgs_to_install=()
        local pkg
        for pkg in "${missing[@]}"; do
            case "$pkg" in
                gh)
                    case "$PKG_MANAGER" in
                        apt)    pkgs_to_install+=("gh") ;;
                        dnf)    pkgs_to_install+=("gh") ;;
                        pacman) pkgs_to_install+=("github-cli") ;;
                    esac
                    ;;
                *)  pkgs_to_install+=("$pkg") ;;
            esac
        done

        $INSTALL_CMD "${pkgs_to_install[@]}"
        echo ""
        info "Packages installed successfully."
    else
        info "All prerequisites satisfied!"
    fi
}

# =============================================================================
# Check Mode
# =============================================================================
check_only() {
    echo ""
    title "  [CHECK MODE] Solo diagnóstico — no se instalará nada."
    echo ""
    check_prerequisites
    echo ""
    echo -e "  ${BOLD}Resumen del check:${RESET}"
    echo -e "  ${GREEN}git:      $(command -v git &>/dev/null && echo 'OK' || echo 'FALTA')${RESET}"
    echo -e "  ${GREEN}gh:       $(command -v gh &>/dev/null && echo 'OK' || echo 'FALTA')${RESET}"
    echo -e "  ${GREEN}node:     $(command -v node &>/dev/null && echo 'OK' || echo 'FALTA')${RESET}"
    echo -e "  ${YELLOW}code:     $(command -v code &>/dev/null && echo 'OK' || echo 'OPCIONAL')${RESET}"
    echo -e "  ${GREEN}opencode: $(command -v opencode &>/dev/null && echo 'OK' || echo 'FALTA - instalar primero')${RESET}"
    echo ""
    echo -e "  ${CYAN}Para instalar: corre ./bootstrap.sh sin parámetros.${RESET}"
    echo -e "  ${CYAN}Para simular:  corre ./bootstrap.sh --dry-run${RESET}"
    echo ""
}

# =============================================================================
# Dry-Run Mode
# =============================================================================
dry_run() {
    echo ""
    title "  [DRY-RUN MODE] Simulando configuración... no se modificará nada."
    echo ""
    source "$(dirname "$0")/../modules/wizard-core.sh"
    wizard_main
    echo ""
    info "Simulación completada. Nada se instaló ni modificó."
    info "Para instalar de verdad, corre ./bootstrap.sh sin parámetros."
    echo ""
}

# =============================================================================
# Main Entry Point
# =============================================================================
main() {
    print_banner
    detect_os

    if [[ "$CHECK_ONLY" == "true" ]]; then
        check_only
        exit 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run
        exit 0
    fi

    check_prerequisites

    echo ""
    echo -e "${BOLD}¿Querés que proceda con la configuración completa? (s/N)${RESET}"
    echo -n "> "
    read -r proceed

    case "${proceed,,}" in
        s|si|y|yes)
            echo ""
            info "¡Vamos! Iniciando wizard de configuración..."

            # Resolve module path — supports both local clone and curl-pipe usage
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || echo "$HOME/lara-diaries/bootstrap")"
            WIZARD_CORE="$SCRIPT_DIR/../modules/wizard-core.sh"

            if [[ ! -f "$WIZARD_CORE" ]]; then
                # Fallback: try the repo clone
                WIZARD_CORE="$HOME/lara-diaries/modules/wizard-core.sh"
            fi

            if [[ ! -f "$WIZARD_CORE" ]]; then
                error "Wizard core not found at $WIZARD_CORE"
                error "Make sure you've cloned the full lara-diaries repo."
                exit 1
            fi

            # shellcheck source=modules/wizard-core.sh
            source "$WIZARD_CORE"
            wizard_main
            ;;
        *)
            echo ""
            echo -e "${CYAN}No hay problema. Cuando quieras configurar, corre este script de vuelta.${RESET}"
            echo -e "${CYAN}¡Nos vemos pronto! 💜${RESET}"
            exit 0
            ;;
    esac
}

main "$@"
