#!/usr/bin/env bash
# Lara Diaries — Memory Sync Script (Linux)
# Syncs engram memories to GitHub private repo via engram sync
# Usage: ./sync-memories.sh [project-name]
set -euo pipefail

ENGRAM_REPO="$HOME/engram-memories"
LARA_DIRIES="$HOME/lara-diaries"
LOG_FILE="$HOME/.local/share/lara-diaries/sync.log"
PROJECT="${1:-lara-diaries}"

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
    if [[ ! -d "$ENGRAM_REPO/.git" ]]; then
        error_exit "Engram repo not found at $ENGRAM_REPO."
    fi

    log "Starting memory sync (project: $PROJECT)..."

    cd "$ENGRAM_REPO"

    # Pull latest
    git pull --rebase 2>>"$LOG_FILE" || log "WARNING: git pull failed, continuing..."

    # Export memories via engram sync (creates/updates .engram/ directory)
    if command -v engram &>/dev/null; then
        log "Running: engram sync --project $PROJECT"
        engram sync --project "$PROJECT" 2>>"$LOG_FILE" || log "WARNING: engram sync had issues"
    else
        log "engram not found, skipping."
    fi

    # Commit and push if there are changes
    if [[ -n "$(git status --porcelain)" ]]; then
        git add .
        git commit -m "sync: memories $(date '+%Y-%m-%d %H:%M')"
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
