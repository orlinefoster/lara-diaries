#!/usr/bin/env bash
# Lara Diaries — Memory Sync Script (Linux)
# Syncs engram memories to GitHub private repo via cron
# Usage: ./sync-memories.sh
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
ENGRAM_REPO="$HOME/engram-memories"
ENGRAM_DATA="$HOME/.local/share/engram"
LOG_FILE="$HOME/.local/share/lara-diaries/sync.log"

# =============================================================================
# Logging
# =============================================================================
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

# =============================================================================
# Main
# =============================================================================
main() {
    # Step 0: Verify repo exists
    if [[ ! -d "$ENGRAM_REPO/.git" ]]; then
        error_exit "Engram repo not found at $ENGRAM_REPO. Run bootstrap first."
    fi

    log "Starting memory sync..."

    # Step 1: Pull latest changes from remote
    cd "$ENGRAM_REPO"
    if ! git pull --rebase 2>>"$LOG_FILE"; then
        log "WARNING: git pull --rebase failed. Possible conflicts or network issue."
        log "Skipping push this cycle to avoid losing local changes."
        exit 1
    fi
    log "Remote changes pulled successfully."

    # Step 2: Copy engram database files into repo
    if [[ -d "$ENGRAM_DATA" ]]; then
        local copied=0
        shopt -s nullglob
        local db_file
        for db_file in "$ENGRAM_DATA"/*.db; do
            cp "$db_file" "$ENGRAM_REPO/"
            log "Copied: $(basename "$db_file")"
            ((copied++))
        done
        shopt -u nullglob
        if [[ $copied -eq 0 ]]; then
            log "No .db files found in $ENGRAM_DATA."
        fi
    else
        log "No engram data directory at $ENGRAM_DATA — skipping file copy."
    fi

    # Step 3: Commit and push if there are changes
    if [[ -n "$(git status --porcelain)" ]]; then
        git add .
        git commit -m "sync: memories $(date '+%Y-%m-%d %H:%M')"
        log "Changes committed locally."

        if ! git push 2>>"$LOG_FILE"; then
            log "WARNING: git push failed. Changes are committed locally and will be pushed on next cycle."
            exit 1
        fi
        log "Sync complete: changes pushed to remote."
    else
        log "No changes to sync. Repository is up to date."
    fi
}

main "$@"
