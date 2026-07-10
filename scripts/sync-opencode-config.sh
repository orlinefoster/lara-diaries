#!/usr/bin/env bash
# Lara Diaries — OpenCode Config Sync Script (Linux)
# Backs up ~/.config/opencode/ to opencode-config GitHub repo
# Usage: ./sync-opencode-config.sh
set -euo pipefail

CONFIG_REPO="$HOME/opencode-config"
OPENCODE_CONFIG="$HOME/.config/opencode"
LOG_FILE="$HOME/.local/share/lara-diaries/sync-opencode.log"

log() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$timestamp] $*" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $*"
    exit 1
}

main() {
    if [[ ! -d "$CONFIG_REPO/.git" ]]; then
        error_exit "Config repo not found at $CONFIG_REPO."
    fi
    if [[ ! -d "$OPENCODE_CONFIG" ]]; then
        error_exit "OpenCode config not found at $OPENCODE_CONFIG."
    fi

    log "Starting opencode config sync..."

    cd "$CONFIG_REPO"

    # Pull latest
    git pull --rebase 2>>"$LOG_FILE" || log "WARNING: git pull failed, continuing..."

    # Copy config files (exclude node_modules, .git, and large dirs)
    rsync -a --delete \
        --exclude='node_modules/' \
        --exclude='.git/' \
        --exclude='package-lock.json' \
        "$OPENCODE_CONFIG/" ./config/

    if [[ -n "$(git status --porcelain)" ]]; then
        git add .
        git commit -m "sync: opencode config $(date '+%Y-%m-%d %H:%M')"
        log "Changes committed locally."

        if ! git push 2>>"$LOG_FILE"; then
            log "WARNING: git push failed. Will retry next cycle."
            exit 1
        fi
        log "Sync complete: changes pushed to remote."
    else
        log "No changes to sync. Repository is up to date."
    fi
}

main "$@"
