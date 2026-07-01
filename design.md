# Lara Diaries — System Design

> **Version**: 1.0.0  
> **Date**: 2026-07-01  
> **Status**: Draft  
> **Author**: Lara (Bootstrap Persona)

---

## 1. Purpose

**Lara Diaries** is a self-bootstrapping, portable AI companion system built on top of [opencode](https://opencode.ai) and [Gentle AI](https://github.com/Gentleman-Programming/gentle-ai). It allows a non-technical user to:

1. Install opencode on a fresh machine
2. Clone this repo and run one command
3. Answer a few questions about preferences
4. Get a fully configured AI agent system with:
   - Persistent memory sync (via engram + GitHub private repo)
   - Config backup (via separate GitHub repo)
   - Safety interceptors (guardian agent)
   - Two specialized Lara agents (Plan & VIP)
   - Cross-device memory synchronization

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     USER'S MACHINE                          │
│                                                             │
│  ┌──────────┐   ┌──────────────┐   ┌───────────────────┐   │
│  │ opencode │──▶│  gentle-ai   │──▶│     engram        │   │
│  │  (CLI)   │   │  (orchestr.) │   │  (memory store)   │   │
│  └──────────┘   └──────────────┘   └────────┬──────────┘   │
│        │                                     │              │
│        ▼                                     ▼              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │               Lara Agent System                       │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐ │   │
│  │  │ Lara-Plan   │  │ Lara-VIP    │  │ Guardian     │ │   │
│  │  │ (Analyst)   │  │ (Executor)  │  │ (Interceptor)│ │   │
│  │  └─────────────┘  └─────────────┘  └──────────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │         Sync Layer (git + gh CLI)                    │   │
│  │  ┌─────────────────┐  ┌──────────────────────────┐  │   │
│  │  │ engram-memories  │  │  opencode-config         │  │   │
│  │  │ (private repo)   │  │  (private repo)          │  │   │
│  │  └─────────────────┘  └──────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 2.1 Component Descriptions

| Component | Role | Tech |
|-----------|------|------|
| **opencode** | CLI runtime for AI agents | Node.js |
| **gentle-ai** | Agent orchestration & SDD workflow | GitHub repo + CLI |
| **engram** | Persistent memory across sessions | Go binary + MCP |
| **Lara-Plan** | Planning/analysis agent — thinks before acting | opencode agent |
| **Lara-VIP** | Hands-on executor — full system access | opencode agent |
| **Guardian** | Safety interceptor — prevents dangerous ops | opencode agent |
| **engram-memories** | Private repo syncing memory across devices | GitHub + git |
| **opencode-config** | Private repo backing up agent configs | GitHub + git |

---

## 3. User Flow — First Run

```
User installs opencode (3 steps in README)
        │
        ▼
User opens opencode, says:
"Baja e inicia este repo https://github.com/orlinefoster/lara-diaries"
        │
        ▼
┌─────────────────────────────────────────────────────┐
│              BOOTSTRAP AGENT RUNS                   │
├─────────────────────────────────────────────────────┤
│  1. Detect OS (Windows / Linux)                     │
│  2. Check prerequisites (git, gh, node)             │
│  3. Clone this repo if not already done             │
│  4. Run bootstrap.[ps1|sh]                          │
│  5. Launch interactive wizard                       │
└─────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────┐
│              SETUP WIZARD                           │
├─────────────────────────────────────────────────────┤
│  1. GitHub login (gh auth)                          │
│  2. Choose dev directory                            │
│  3. Gentle AI? (default: yes)                       │
│  4. 3 Recognition questions:                        │
│     - Pronouns                                      │
│     - Tech skill level                              │
│     - Assistance level                              │
│  5. Repo management preference                      │
│  6. Design orientation & style                      │
│  7. Mission: personal/work/lab                      │
└─────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────┐
│              INSTALLATION                           │
├─────────────────────────────────────────────────────┤
│  1. Install gentle-ai (if selected)                 │
│  2. Install engram memory                           │
│  3. Install Gentleman Skills                        │
│  4. Create Lara-Plan agent                          │
│  5. Create Lara-VIP agent                           │
│  6. Configure Guardian interceptor                  │
│  7. Check/create engram-memories repo               │
│  8. Check/create opencode-config repo               │
│  9. Set up sync hooks / cron                        │
│  10. First memory sync                              │
└─────────────────────────────────────────────────────┘
        │
        ▼
    ✅ READY — User has a full Lara system
```

---

## 4. Directory Structure (This Repo)

```
lara-diaries/
├── design.md                      # This file
├── README.md                      # User-facing instructions
├── .gitignore
│
├── bootstrap-agent.md             # Prompt template for the bootstrap agent
│
├── bootstrap/
│   ├── bootstrap.ps1              # Windows bootstrapper (PowerShell)
│   └── bootstrap.sh               # Linux bootstrapper (Bash)
│
├── modules/
│   ├── wizard-core.ps1            # Shared wizard functions (PS)
│   └── wizard-core.sh             # Shared wizard functions (Bash)
│
├── templates/
│   ├── agents/
│   │   ├── lara-plan.md           # Lara-Plan: analyst/planner
│   │   └── lara-vip.md            # Lara-VIP: executor with full access
│   ├── configs/
│   │   └── opencode.json          # Base opencode config template
│   └── engram/
│       └── sync-config.yaml       # Engram sync configuration
│
├── scripts/
│   ├── sync-memories.ps1          # Memory sync (Windows)
│   └── sync-memories.sh           # Memory sync (Linux)
│
├── guardian/
│   ├── guardian-rules.md          # Safety rules for Lara interceptor
│   └── patterns.json              # Dangerous patterns to watch for
│
└── docs/                          # Optional: extended docs
    ├── ARCHITECTURE_DECISIONS.md  # Trade-offs and rationale
    └── TROUBLESHOOTING.md         # Common issues
```

---

## 5. Agent Design

### 5.1 Lara-Plan (Analyst/Planner)

```
Purpose:     Analyze, plan, document, think before acting
Mode:        primary (visible to user)
Personality: Lara persona — warm, didactic, meticulous
Tools:       read, glob, grep, question, task (to sdd-agents)
Key trait:   "Mide dos veces, corta una" — always checks before acting
```

**Responsibilities:**
- Codebase analysis and architecture understanding
- SDD exploration and proposal generation
- Teaching concepts with diagrams and examples
- Writing design docs and specs
- Coordinating via sub-agents (not doing the heavy lifting)

### 5.2 Lara-VIP (Executor)

```
Purpose:     Get things done — full system access
Mode:        primary (visible to user)  
Personality: Lara persona — direct, efficient, protective
Tools:       bash, edit, write, read, glob, grep, webfetch, websearch
Key trait:   "Manos a la obra" — executes with minimal overhead
```

**Responsibilities:**
- Quick edits and mechanical changes
- Emergency fixes and urgent tasks
- System operations and configuration
- Memory sync and repo management
- Guardian-like safety checks before dangerous operations

### 5.3 Guardian Interceptor (Safety Layer)

The Guardian is NOT a separate agent in opencode — it's a set of **rules** embedded into both Lara agents that activate before dangerous operations. Think of it as:

```
User request ──▶ Guardian Check ──▶ Safe? ──▶ Execute
                      │                   
                  Dangerous?              
                      │                   
                  ⚠️ WARN USER           
                      │                   
                  Confirm? ──Yes──▶ Execute
                      │
                     No
                      │
                   ABORT
```

**Guardian Rules:**
1. **Network exposure**: Warn before opening router configs, firewall changes
2. **Data loss**: Warn before working in /tmp, temp folders, unrecoverable locations
3. **System integrity**: Warn before `sudo rm -rf`, `chmod 777`, removing sudo, etc.
4. **Session awareness**: Track what projects are open and warn about context switches
5. **Git safety**: Warn before force push, rebase, reset --hard

---

## 6. Memory Sync Architecture

### 6.1 How Engram Works

Engram stores memories as SQLite/FTS5 files locally. The sync mechanism:

```
┌─ Machine A ───┐       ┌─ GitHub ───┐       ┌─ Machine B ───┐
│ engram.db      │──push─▶│ private    │◀─pull─│ engram.db      │
│ (local store)  │       │ repo       │       │ (local store)  │
│                │       │ engram-    │       │                │
│ cron: push     │       │ memories   │       │ cron: pull     │
│ every 30min    │       │            │       │ every 30min    │
└────────────────┘       └────────────┘       └────────────────┘
```

### 6.2 Sync Strategy

| Aspect | Decision |
|--------|----------|
| **Frequency** | Every 30 min (cron / task scheduler) + on opencode close |
| **Conflict** | Last-write-wins (engram handles per-entry timestamps) |
| **Auth** | gh CLI (already logged in) |
| **Repo** | `engram-memories` — private, auto-created |
| **Path** | `~/.local/share/engram/` (Linux) or `%APPDATA%/engram/` (Windows) |

### 6.3 Sync Script

A simple script that:
1. `cd ~/engram-memories`
2. `git pull --rebase` (or fetch + merge)
3. Copy engram DB files to repo
4. `git add . && git commit -m "sync: memories $(date)"`
5. `git push`

---

## 7. Config Backup Architecture

### 7.1 opencode-config Repo

Stores:
- `~/.config/opencode/opencode.json` (main config)
- `~/.config/opencode/agents/*.md` (agent prompts)
- `~/.config/opencode/skills/` (custom skills)
- `~/.config/opencode/AGENTS.md` (master agent list)

**Sync strategy**: Same as engram — git-based, cron-driven, private repo.

---

## 8. Question System (Wizard)

The wizard asks these questions in order:

### 8.1 GitHub Login
- Check if `gh` is authenticated
- If not, run `gh auth login`
- Verify with `gh auth status`

### 8.2 Dev Directory
- Suggest: `~/Documents/Develops` (Linux) or `$HOME\Documents\Develops` (Windows)
- Allow custom path
- Create directory if it doesn't exist

### 8.3 Gentle AI
- Default: Yes
- If yes: install from GitHub + install Gentleman Skills
- If no: install only engram

### 8.4 Recognition Questions

| # | Question | Options |
|---|----------|---------|
| 1 | Pronouns | she/her, they/them, he/him, it/its, other |
| 2 | Tech skill level | Full fearless, Me defiendo, Me invitó un amigo |
| 3 | Assistance level | Full (no assumptions), Medium (explain + check), Minimal (trust user) |

These affect how verbose and explanatory the agents are.

### 8.5 Repo Management
- "I manage repos myself" (least intervention)
- "Let Lara handle everything" (auto commit/push)
- "Ask before each commit"

### 8.6 Style & Design
- clean-ui, pink-kawaii, dark-academia, retro-futuristic, business, full-backend
- Whether to use design.md

### 8.7 Mission
- Personal machine (important data)
- Work machine
- VM / disposable
- Lab / Raspberry Pi / server

This determines **discretion level** — how freely agents can modify system config.

---

## 9. Personality Injection

The answers from Section 8 affect agent prompts:

```
Template: "You are Lara, a {{pronoun}} developer..."
          "User skill level: {{skill_level}}"
          "Assistance mode: {{assistance_mode}}"
          "System discretion: {{discretion_level}}"
          "Preferred style: {{style}}"
```

Pronouns affect narration (she/her, they/them, etc.).  
Skill level affects how much explanation is given.  
Discretion level affects guardian triggers.

---

## 10. Cross-Platform Strategy

| Aspect | Windows | Linux |
|--------|---------|-------|
| **Shell** | PowerShell 5.1+ | Bash 4+ |
| **Git** | git-for-windows | system git |
| **gh CLI** | gh.exe | gh |
| **Cron** | Task Scheduler | crontab / systemd timer |
| **Config path** | `%APPDATA%\opencode` | `~/.config/opencode` |
| **Engram path** | `%LOCALAPPDATA%\engram` | `~/.local/share/engram` |
| **Bootstrap** | `bootstrap.ps1` | `bootstrap.sh` |
| **Sync trigger** | Task Scheduler + pwsh | cron + bash |

---

## 11. Security & Privacy

| Concern | Mitigation |
|---------|------------|
| GitHub token exposure | Stored by gh CLI securely; never in config files |
| Memory data privacy | Repo is PRIVATE; user owns all data |
| Dangerous commands | Guardian intercepts before execution |
| Config secrets | opencode.json permission deny rules for .env, .ssh, etc. |
| Sync over HTTPS | GitHub uses HTTPS + SSH; gh CLI handles auth |

---

## 12. Future Considerations

- **Docker support**: A containerized version for instant spin-up
- **One-click install**: A `.exe` / `.AppImage` that installs everything
- **Multi-device merge**: Smarter conflict resolution for engram
- **Offline mode**: Full functionality without internet
- **Web dashboard**: Visual memory browser

---

## 13. File Dependency Graph

```
bootstrap-agent.md
  └── references bootstrap.ps1 / bootstrap.sh
        └── sources modules/wizard-core.ps1 / wizard-core.sh
              └── uses templates/agents/*.md
              └── uses templates/configs/opencode.json
              └── uses templates/engram/sync-config.yaml
              └── runs scripts/sync-memories.ps1 / sync-memories.sh
              └── applies guardian/guardian-rules.md
```

---

*This design document evolves as the system grows. Keep it in sync with implementation.*
