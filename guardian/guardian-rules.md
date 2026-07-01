# Guardian Rules — Safety Interceptor System

> **Purpose**: Prevent dangerous operations before they happen  
> **Applied to**: Lara-Plan and Lara-VIP agent prompts  
> **Version**: 1.0.0

---

## Overview

The Guardian is NOT a separate agent — it's a set of rules embedded into both Lara agents that activate before executing operations. Think of it as the "check engine light" for system operations.

```
User Request ──▶ Guardian Check ──▶ Safe? ──▶ Execute
                      │
                  Dangerous?
                      │
                  ⚠️  WARN USER
                      │
                  Confirm? ──Yes──▶ Execute
                      │
                     No
                      │
                   🛑 ABORT
```

---

## Rule Categories

### 🏴 CRITICAL — Must block, require explicit confirmation

| Rule ID | Pattern | Warning Message |
|---------|---------|----------------|
| G-NET-01 | Router/firewall access | "⛔ Alto — estás por abrir/configurar el router. Si luego olvidás qué hiciste, quedamos expuestas permanentemente." |
| G-SYS-01 | Remove sudo password | "🚨 No es recomendable quitar la contraseña de sudo. Al reiniciar hay altas chances de corromper el inicio del sistema." |
| G-SEC-01 | Expose credentials | "🔐 Cuidado — esto puede exponer credenciales en el historial de la terminal." |
| G-GIT-01 | Destructive git operations | "⚠️ Esto es destructivo en git. Si hay cambios sin pushear, se pierden para siempre." |
| G-DATA-01 | Working in temp directories | "⚠️ ESPERA — estás trabajando en /tmp/ o /temp/. Si reiniciás la máquina, esto se pierde. ¿Querés moverlo a un lugar seguro?" |

### 🟡 WARNING — Warn but don't block

| Rule ID | Pattern | Warning Message |
|---------|---------|----------------|
| G-DATA-02 | Deleting files without backup | "📂 Vas a borrar archivos. ¿Estás segura de que no necesitás backup?" |
| G-NET-02 | Opening ports | "🌐 Vas a abrir puertos en el firewall. Recordá cerrarlos cuando termines." |
| G-CONFIG-01 | Modifying system config | "⚙️ Vas a modificar configuración del sistema. Anotá lo que cambiaste por si necesitás revertir." |
| G-GIT-02 | Large uncommitted changes | "📦 Tenés cambios sin commitear. ¿Querés que los commitee antes de seguir?" |

### 🟢 INFO — Just notify

| Rule ID | Pattern | Notification |
|---------|---------|--------------|
| G-INFO-01 | Installing packages | "📦 Instalando paquetes nuevos. Te aviso cuando termine." |
| G-INFO-02 | Cloning repos | "📋 Clonando repositorio. Un toque..." |
| G-INFO-03 | Running tests | "🧪 Corriendo tests. Voy a informarte si algo falla." |

---

## Pattern Detection Reference

### Shell Command Patterns (regex)

```json
{
  "critical": {
    "network_exposure": [
      "(router|modem|gateway|192\\.168\\.\\d+\\.\\d+|iptables|ufw|firewall-cmd|nmap)",
      "(socat|nc\\s+-lv|netcat|telnetd)",
      "(iptables -P INPUT DROP|ufw default deny)"
    ],
    "system_integrity": [
      "(sudo.*passwd|chmod\\s+777|passwd\\s+-d|usermod.*sudo|visudo)",
      "(systemctl disable.*sudo|rm\\s+/etc/sudoers)",
      "(dd\\s+if=|mkfs\\.|fdisk.*/dev/sd[a-z])"
    ],
    "credential_exposure": [
      "(cat.*\\.env|echo.*(API_KEY|SECRET|PASSWORD|TOKEN))",
      "(printenv|set\\s+SECRET|export.*SECRET)",
      "(git log -p|git diff HEAD~1)"
    ],
    "destructive_git": [
      "(git push --force|git push -f|git reset --hard)",
      "(git rebase --onto|git branch -D|git tag -d)"
    ],
    "data_loss": [
      "(rm\\s+-rf\\s+/?$|rm\\s+-rf\\s+/[^ ]*[^/]$)",
      "(del\\s+/[fps]\\s+|remove-item -recurse)",
      "(format|diskpart|clean-all)"
    ]
  },
  "warning": {
    "temp_directories": [
      "(/tmp/|/temp/|C:\\\\Windows\\\\Temp|%TEMP%)",
      "(mktemp|tempfile)"
    ],
    "system_config": [
      "(/etc/|/sys/|/proc/|HKEY_LOCAL_MACHINE)",
      "(systemctl|service.*restart|reboot|shutdown)"
    ],
    "bulk_delete": [
      "(rm\\s+-rf|del.*/s|remove-item.*-recurse)",
      "(find.*-delete|find.*-exec rm)"
    ],
    "port_exposure": [
      "(ufw allow|iptables -A INPUT -p tcp --dport)",
      "(netsh advfirewall firewall add rule)"
    ]
  }
}
```

---

## Implementation

These rules are injected into the Lara agent prompts as:

### For Lara-VIP (active guardian):

```markdown
## 🛡 GUARDIAN MODE — ACTIVE

Before every `bash` command, scan it against these patterns:

CRITICAL patterns ALWAYS require user confirmation.
WARNING patterns require confirmation if running in `full` assistance mode.
INFO patterns just notify.

Example flow:
1. User: "Borrá la carpeta temp"
2. YOU scan: "rm -rf /tmp/project" → matches G-DATA-01 (TEMP)
3. YOU warn: "⚠️ ESPERA — /tmp/ se borra al reiniciar. ¿Seguro?"
4. Wait for confirmation
5. Only proceed if user says yes
```

### For Lara-Plan (passive guardian):

```markdown
## 🛡 GUARDIAN MODE — PLANNING

Before delegating any task, check if it involves:
- Network/firewall changes → flag for user review
- Destructive operations → flag for user review
- Working in temp directories → suggest safe location
- System config changes → note for backup

If any checklist item triggers, warn the user BEFORE delegating.
```

---

## Escalation Path

If the user is unsure about a warning:

1. **Explain** in simple terms why it's dangerous
2. **Suggest** a safer alternative
3. **Offer** to make a backup first
4. **Document** what was done so it can be reversed

If the user insists despite warnings:
1. Make a backup first (if applicable)
2. Log the operation to `~/.config/lara-diaries/audit.log`
3. Proceed with the operation
4. Offer to create a restore point

---

## Audit Logging

All guardian-triggered events are logged:

```json
{
  "timestamp": "2026-07-01T12:00:00Z",
  "rule_id": "G-DATA-01",
  "severity": "critical",
  "command": "rm -rf /tmp/project",
  "user_response": "confirmed",
  "backup_made": true,
  "user_action": "proceeded"
}
```

Log location: `~/.config/lara-diaries/guardian-audit.jsonl`
