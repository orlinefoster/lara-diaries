#!/usr/bin/env bash
# Lara Diaries - Linux/macOS Bootstrap
# Usage: ./bootstrap.sh [install|doctor|--version]
# Downloads and runs the lara-installer binary, with fallback to wizard-core.
set -euo pipefail

# Configurable binary download URL (override via env var)
BINARY_BASE_URL="${LARA_INSTALLER_BASE_URL:-https://github.com/orlinefoster/lara-diaries/releases/latest/download}"
VERSION="0.1.0"

# --- Parse flags ---
NON_INTERACTIVE=""
CHECK_ONLY=false
DRY_RUN=false
GO_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --check|-c)        CHECK_ONLY=true ;;
        --dry-run|-n)      DRY_RUN=true ;;
        --non-interactive) ;;  # next arg is the JSON value
        --help|-h)
            echo "Usage: ./bootstrap.sh [--check|--dry-run|--non-interactive <json>|install|doctor|--version]"
            echo ""
            echo "  install           Run the full installer (default)"
            echo "  doctor            System health check (if binary available)"
            echo "  --version         Show version"
            echo "  --check, -c       Diagnose system state without installing"
            echo "  --dry-run, -n     Show installation plan without changes"
            echo "  --non-interactive AI-driven install from JSON config"
            echo "  --help, -h        Show this help"
            exit 0
            ;;
        doctor|install|--version) GO_ARGS+=("$arg") ;;
        *)
            if [[ -z "$NON_INTERACTIVE" ]] && [[ "$arg" != -* ]]; then
                NON_INTERACTIVE="$arg"
            fi
            ;;
    esac
done

# --- Detect OS + arch ---
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "[FAIL] Unsupported architecture: $ARCH"; exit 1 ;;
esac

case "$OS" in
    linux)  BINARY_NAME="lara-installer-linux-${ARCH}" ;;
    darwin) BINARY_NAME="lara-installer-darwin-${ARCH}" ;;
    *)      echo "[FAIL] Unsupported OS: $OS"; exit 1 ;;
esac

# --- Binary path ---
BIN_DIR="${HOME}/.local/bin"
BINARY_PATH="${BIN_DIR}/lara-installer"

# --- Colors (if available) ---
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

# --- Functions ---
install_binary() {
    local url="${BINARY_BASE_URL}/${BINARY_NAME}"
    local tmp_file
    tmp_file="$(mktemp)"

    echo -e "${CYAN}[..]${RESET} Downloading lara-installer v${VERSION}..."
    if command -v curl &>/dev/null; then
        if ! curl -fsSL "$url" -o "$tmp_file"; then
            echo -e "${YELLOW}[!]${RESET} Download failed."
            rm -f "$tmp_file"
            return 1
        fi
    elif command -v wget &>/dev/null; then
        if ! wget -q "$url" -O "$tmp_file"; then
            echo -e "${YELLOW}[!]${RESET} Download failed."
            rm -f "$tmp_file"
            return 1
        fi
    else
        echo -e "${RED}[FAIL]${RESET} Neither curl nor wget found. Cannot download binary."
        rm -f "$tmp_file"
        return 1
    fi

    # Verify SHA256 if checksum file is available
    local checksum_url="${BINARY_BASE_URL}/${BINARY_NAME}.sha256"
    if command -v sha256sum &>/dev/null; then
        local checksum_content
        checksum_content="$(curl -fsSL "$checksum_url" 2>/dev/null || wget -q -O- "$checksum_url" 2>/dev/null || true)"
        if [[ -n "$checksum_content" ]]; then
            local expected_hash
            expected_hash="$(echo "$checksum_content" | awk '{print $1}')"
            local actual_hash
            actual_hash="$(sha256sum "$tmp_file" | awk '{print $1}')"
            if [[ "${actual_hash,,}" != "${expected_hash,,}" ]]; then
                echo -e "${RED}[FAIL]${RESET} SHA256 checksum mismatch."
                echo "  Expected: $expected_hash"
                echo "  Got:      $actual_hash"
                rm -f "$tmp_file"
                return 1
            fi
            echo -e "${GREEN}[OK]${RESET} Checksum verified."
        else
            echo -e "${YELLOW}[!]${RESET} No checksum file available, skipping verification."
        fi
    else
        echo -e "${YELLOW}[!]${RESET} sha256sum not found, skipping checksum verification."
    fi

    # Install binary
    mkdir -p "$BIN_DIR"
    mv "$tmp_file" "$BINARY_PATH"
    chmod +x "$BINARY_PATH"
    echo -e "${GREEN}[OK]${RESET} Binary installed to $BINARY_PATH"
    return 0
}

fallback_wizard() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local wizard_core="${script_dir}/../modules/wizard-core.sh"

    if [[ ! -f "$wizard_core" ]]; then
        wizard_core="${HOME}/lara-diaries/modules/wizard-core.sh"
    fi

    if [[ ! -f "$wizard_core" ]]; then
        echo -e "${RED}[FAIL]${RESET} wizard-core.sh not found."
        echo "  Make sure you are running from the full lara-diaries repository."
        exit 1
    fi

    # shellcheck source=../modules/wizard-core.sh
    source "$wizard_core"

    if [[ -n "$NON_INTERACTIVE" ]]; then
        echo -e "${YELLOW}[!]${RESET} Running non-interactive install from JSON config..."
        wizard_noninteractive "$NON_INTERACTIVE"
    elif [[ "$CHECK_ONLY" == "true" ]]; then
        echo -e "${YELLOW}[!]${RESET} Check mode (script-based)..."
        # check_only and dry_run were removed in the hybrid rewrite;
        # run the doctor from wizard-core.sh if available, or the Go binary's doctor
        if type wizard_check_only &>/dev/null 2>&1; then
            wizard_check_only
        else
            echo -e "${YELLOW}[!]${RESET} Check mode not available in script fallback."
            echo "  Install the lara-installer binary and use: lara-installer doctor"
            exit 0
        fi
    elif [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[!]${RESET} Dry-run mode (script-based)..."
        if type wizard_dry_run &>/dev/null 2>&1; then
            wizard_dry_run
        else
            echo -e "${YELLOW}[!]${RESET} Dry-run mode not available in script fallback."
            echo "  Run without --dry-run for interactive installation."
            exit 0
        fi
    else
        echo -e "${YELLOW}[!]${RESET} Falling back to script-based wizard..."
        wizard_main
    fi
}

# ---- FALLBACK PATH ----
# The functions below (install_binary, fallback_wizard) implement the
# two-phase hybrid strategy:
#   1. If the Go binary exists at BINARY_PATH, run it directly.
#   2. If not found, download it from GitHub Releases (install_binary).
#   3. If the download fails, fall back to the script-based wizard-core.sh
#      (fallback_wizard). This ensures operation even without network
#      access to release artifacts or a pre-built binary.
#
# The binary download includes SHA256 verification when the checksum
# file is available from the release server.

# --- MAIN ---

# --check and --dry-run always go to shell fallback (Go binary has no dedicated subcommand for these)
if [[ "$CHECK_ONLY" == "true" || "$DRY_RUN" == "true" ]]; then
    fallback_wizard
    exit $?
fi

# --non-interactive: try Go binary first with --config, fallback to wizard-core
if [[ -n "$NON_INTERACTIVE" ]]; then
    # If Go binary exists, write config to temp file and delegate
    if [[ -x "$BINARY_PATH" ]]; then
        local config_file=""
        # Detect if NON_INTERACTIVE is inline JSON or file path
        if [[ "${NON_INTERACTIVE:0:1}" == "{" ]]; then
            config_file="$(mktemp)"
            printf '%s\n' "$NON_INTERACTIVE" > "$config_file"
            trap 'rm -f "$config_file"' EXIT
            echo -e "${GREEN}[OK]${RESET} Using lara-installer with inline config..."
            exec "$BINARY_PATH" install --config "$config_file"
        elif [[ -f "$NON_INTERACTIVE" ]]; then
            echo -e "${GREEN}[OK]${RESET} Using lara-installer with config file..."
            exec "$BINARY_PATH" install --config "$NON_INTERACTIVE"
        fi
    fi
    # Fallback: use shell wizard
    fallback_wizard
    exit $?
fi

# Try existing binary
if [[ -x "$BINARY_PATH" ]]; then
    echo -e "${GREEN}[OK]${RESET} lara-installer binary found. Running..."
    exec "$BINARY_PATH" "${GO_ARGS[@]}"
fi

# Download binary
echo -e "${YELLOW}[..]${RESET} lara-installer not found at $BINARY_PATH"
if install_binary; then
    exec "$BINARY_PATH" "${GO_ARGS[@]}"
else
    fallback_wizard
fi
