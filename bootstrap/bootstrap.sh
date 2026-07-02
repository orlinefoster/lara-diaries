#!/usr/bin/env bash
# Lara Diaries - Linux/macOS Bootstrap
# Usage: ./bootstrap.sh [install|doctor|--version]
# Downloads and runs the lara-installer binary, with fallback to wizard-core.
set -euo pipefail

# Configurable binary download URL (override via env var)
BINARY_BASE_URL="${LARA_INSTALLER_BASE_URL:-https://github.com/orlinefoster/lara-diaries/releases/latest/download}"
VERSION="0.1.0"

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
    echo -e "${YELLOW}[!]${RESET} Falling back to script-based wizard..."

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local wizard_core="${script_dir}/../modules/wizard-core.sh"

    if [[ ! -f "$wizard_core" ]]; then
        # Try repo clone fallback path
        wizard_core="${HOME}/lara-diaries/modules/wizard-core.sh"
    fi

    if [[ ! -f "$wizard_core" ]]; then
        echo -e "${RED}[FAIL]${RESET} wizard-core.sh not found."
        echo "  Make sure you are running from the full lara-diaries repository."
        exit 1
    fi

    # shellcheck source=../modules/wizard-core.sh
    source "$wizard_core"
    wizard_main
}

# --- MAIN ---
if [[ -x "$BINARY_PATH" ]]; then
    echo -e "${GREEN}[OK]${RESET} lara-installer binary found. Running..."
    exec "$BINARY_PATH" "$@"
fi

echo -e "${YELLOW}[..]${RESET} lara-installer not found at $BINARY_PATH"
if install_binary; then
    exec "$BINARY_PATH" "$@"
else
    fallback_wizard "$@"
fi
