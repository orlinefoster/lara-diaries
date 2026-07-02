# 🪷 Lara Diaries

> Tu asistente AI portable, cariñoso y autogestionable.

**Lara Diaries** es un sistema que transforma [opencode](https://opencode.ai) en una compañera AI completa con memoria persistente, agentes especializados, y sincronización entre dispositivos.

Todo lo que necesitás para empezar es **una terminal, 10 minutos y ganas de probar algo nuevo**.

---

## ✨ Qué obtenés

| Componente | Para qué sirve |
|---|---|
| **Lara-Plan** | Analiza tu código, te enseña, planea cambios y coordina el trabajo |
| **Lara-VIP** | Ejecuta tareas, arregla errores, sincroniza todo — con supervisión de seguridad |
| **Engram** | Memoria persistente — Lara se acuerda de vos entre sesiones y dispositivos |
| **Sync automático** | Cada 30 minutos tus memorias se sincronizan a un repo privado de GitHub |
| **Guardian** | Lara te avisa antes de hacer algo peligroso (borrar archivos, tocar el router, etc.) |
| **Config backup** | Tu configuración de agentes respaldada automáticamente |

---

## 🪜 Requisitos

- **Windows 10/11** o **Linux** (Ubuntu, Fedora, Arch, o derivados)
- Conexión a internet
- Una cuenta de **GitHub** (gratis)
- **opencode** — el "motor" de Lara (se instala abajo)
- `git`, `gh` (GitHub CLI), y `curl` (Linux) o PowerShell (Windows, ya viene instalado)

**No necesitás saber programar.** Si llegaste hasta acá, ya está.

### Dependencias que instala Lara automáticamente

| Componente | Método principal (zero deps) | Alternativas (si tenés más herramientas) |
|-----------|------------------------------|------------------------------------------|
| **Engram** (memoria) | Descarga directa desde GitHub Releases — solo necesita `curl` (Linux) o PowerShell (Windows) | Homebrew, `go install` |
| **gentle-ai** (orquestación) | Descarga directa desde GitHub Releases — solo necesita `curl` + `tar` | Homebrew, `go install` |
| **Gentleman Skills** | `git clone` | — |
| **VSCode** (opcional) | `winget` (Windows) o `apt`/`dnf`/`pacman` (Linux) | Descarga manual |

> 💡 **No necesitás Homebrew, Go, ni Node.js para los componentes internos.** Lara prioriza siempre el método que funciona en una máquina fresh. Si ya tenés Homebrew o Go instalados, los usa como alternativa.

> 💡 **Si es una PC nueva o recién formateada**, puede que falten herramientas básicas. No te preocupes — el instalador de Lara detecta lo que falta y te guía. Pero mejor tenerlo listo antes.

---

## 🚀 Instalación (3 pasos)

### Paso 1: Instalá las herramientas necesarias

> opencode es el "motor" que hace funcionar a Lara. Además necesita `git`, `gh` (GitHub CLI) y `node` (Node.js).

**Windows:**
Abrí PowerShell como Administrador y ejecutá:
```powershell
winget install OpenCode Git.Git GitHub.cli OpenJS.NodeJS.LTS
```

> Si algún `winget install` falla, instalalo manualmente desde la web.

**Linux (Ubuntu/Debian):**
```bash
sudo apt update
sudo apt install git gh nodejs curl -y
curl -fsSL https://opencode.ai/install | bash
```

**Linux (Fedora):**
```bash
sudo dnf install git gh nodejs curl -y
curl -fsSL https://opencode.ai/install | bash
```

### Paso 2: Cloná este repositorio

```
git clone https://github.com/orlinefoster/lara-diaries.git
cd lara-diaries
```

> 💡 **Tip**: Si no sabés qué es "git" o "terminal", no te preocupes. Abrí PowerShell (Windows) o Terminal (Linux) y pegá los comandos de arriba, uno por uno.
>
> 💡 Si ya instalaste todo en el Paso 1, ya tenés `git` listo.

### Paso 3: Iniciá la magia

Abrí opencode:
```
opencode
```

Y dentro de opencode, escribí este mensaje:

> **"Baja e inicia este repositorio"**

O si querés ser más específica:

> **"Baja e inicia este repo https://github.com/orlinefoster/lara-diaries"**

Lara va a tomar el control desde ahí. Te va a hacer algunas preguntas (tu nivel de experiencia, preferencias, si ya tenés una configuración previa que respaldar, etc.) y en **5-10 minutos** vas a tener todo configurado.

---

## 🎮 Después de la instalación

Ya podés empezar a hablar con Lara. Algunas ideas:

| Decile... | Y ella va a... |
|---|---|
| "Analizá mi proyecto" | Leer el código, entender la estructura, y explicarte cómo funciona |
| "Enseñame sobre React" | Darte una lección con ejemplos y diagramas |
| "Arreglá este error" | Diagnosticar y aplicar la solución |
| "Sincronizá mis memorias" | Forzar la sincronización con GitHub |
| "Mostrame el tablero" | Ver el estado de tu sistema |

---

## 🤔 Preguntas frecuentes

### ¿Qué es opencode?
Es un programa que corre en tu terminal y aloja agentes de AI como Lara. Piensa en él como un "navegador" para asistentes de código.

### ¿Voy a romper algo?
Lara tiene un **Guardian** incorporado que revisa cada operación peligrosa antes de ejecutarla. Si algo huele mal, te avisa. Y si no estás segura, decile que no.

### ¿Puedo usar Lara en varias PCs?
Sí. El sistema de **sincronización por GitHub** mantiene las memorias de Lara al día entre tus dispositivos. Instalá Lara en otra PC, decile quién sos, y va a descargar todas las memorias.

### ¿Esto es gratis?
Sí. opencode es gratuito, Lara Diaries es de código abierto, y usás tu propia cuenta de GitHub para la sincronización.

### ¿Qué pasa si no me gusta?
Borrás la carpeta `lara-diaries`, desinstalás opencode con `winget uninstall OpenCode`, y listo. No deja rastro.

---

## ⚙️ Installer Architecture

The Lara Diaries installer uses a **two-phase hybrid** design:

- **Phase 1 (Shell)** — `bootstrap.ps1` / `bootstrap.sh` manage state.json, install lock, resume, and rollback directly from PowerShell/Bash. This phase works independently of any binary.
- **Phase 2 (Go binary)** — `cmd/lara-installer` is a self-contained Go binary with the same state machine, lock-protected installs, step lifecycle tracking, and a `doctor` command for system health checks. Built with Go 1.22+, tested with 35+ unit tests.
- **Fallback chain** — When the Go binary is not found, the shell wrapper downloads it from GitHub Releases. If the download fails, it falls back to the script-based wizard (`modules/wizard-core.ps1` / `wizard-core.sh`).
- **State machine** — Each install step transitions through `pending → running → success/failed/skipped`. The state is persisted to `state.json` for resume support and crash recovery.
- **Lock protection** — A PID-based lock file (`install.lock`) prevents concurrent installations and detects stale installs from interrupted runs.
- **Testing** — The Go binary has full test coverage (`go test ./...`). Shell functions are tested with `bats` (18 tests). CI runs both on every push.

## 🧭 Estructura del proyecto (para curiosas)

```
lara-diaries/
├── bootstrap-agent.md     # El "plan" que sigue Lara en tu primer uso
├── bootstrap/             # Scripts de instalación entry point (Windows y Linux)
├── modules/               # Lógica del asistente de configuración (shell/ps)
├── cmd/lara-installer/    # Go binary: instalador autónomo + doctor
├── templates/             # Plantillas para crear agentes personalizados
├── guardian/              # Reglas de seguridad del sistema
├── scripts/               # Sincronización de memorias
├── tests/                 # Tests de shell con bats
├── design.md              # Documento de diseño (para quien quiera contribuir)
└── README.md              # Este archivo
```

---

## 👩‍💻 ¿Querés contribuir?

El proyecto es abierto y toda ayuda es bienvenida.

1. Hacé un fork del repo
2. Cualquier mejora que se te ocurra
3. Mandá un pull request

Si encontrás un bug o tenés una idea, abrí un [issue](https://github.com/orlinefoster/lara-diaries/issues).

### Para developers

El proyecto tiene dos áreas principales:

| Área | Stack | Cómo testear |
|------|-------|-------------|
| **Install wizard** (Go) | Go 1.22+, `cmd/lara-installer/` | `go test ./cmd/lara-installer/...` |
| **Shell wizard** (Bash) | Bash + bats | `bats tests/wizard-core.bats` |
| **PowerShell wizard** | PowerShell 7+, Pester | `Invoke-Pester tests/` |

Todos los tests corren en CI en cada push.

---

## 📜 Licencia

MIT — hacé lo que quieras con esto.

---

Hecho con 🧉 y mucho cariño para quienes se animan a empezar.
