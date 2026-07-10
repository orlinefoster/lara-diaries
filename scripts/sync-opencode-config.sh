#!/usr/bin/env bash
# Lara Diaries — OpenCode Config Sync Script (Linux)
# Commits and pushes changes from the opencode config directory
# The config dir (~/.config/opencode/) IS the git repo.
# Usage: ./sync-opencode-config.sh
set -euo pipefail

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
    if [[ ! -d "$OPENCODE_CONFIG/.git" ]]; then
        error_exit "Config directory is not a git repository at $OPENCODE_CONFIG."
    fi

    log "Starting opencode config sync..."

    cd "$OPENCODE_CONFIG"

    # Pull latest from remote (merge, don't rebase — config is shared)
    git pull 2>>"$LOG_FILE" || log "WARNING: git pull failed, continuing..."

    # Stage all changes (respects .gitignore: excludes node_modules, lock files)
    git add -A 2>>"$LOG_FILE" || true

    if ! git diff --cached --quiet 2>/dev/null; then
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
