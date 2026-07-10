# Cuaderno de Campo — Instalación de Lara Diaries en Windows

> **Fecha**: 2026-07-10  
> **Sistema**: Windows 10.0.22631 x64, PowerShell 5.1  
> **Repo**: [orlinefoster/lara-diaries](https://github.com/orlinefoster/lara-diaries)  
> **Autor**: Notas de campo durante instalación asistida por AI

---

## Resumen

La instalación de Lara Diaries en Windows mostró **4 problemas críticos** que impiden
que el sistema funcione out-of-the-box. Este documento detalla cada uno, su causa raíz,
y la solución aplicada.

---

## Problema 1 — Config directory incorrecto

### Síntoma

- `opencode agent list` solo muestra los agentes built-in (`build`, `compaction`,
  `explore`, `general`, `plan`, `summary`, `title`)
- `opencode mcp list` dice `"No MCP servers configured"`
- `opencode debug config` muestra `"agent": {}` vacío
- Los archivos `opencode.json`, `AGENTS.md`, `plugins/`, `agents/` existen en
  `%APPDATA%\opencode\` pero opencode no los lee

### Causa raíz

**En Windows, el script `Generate-OpencodeJson` del wizard escribe los archivos en
`%APPDATA%\opencode\`** (línea 746 de `modules/wizard-core.ps1`):

```powershell
$configDir = Join-Path $env:APPDATA "opencode"
```

Pero **opencode v1.17.15 espera la config global en `~/.config/opencode/` en TODAS
las plataformas**, incluyendo Windows. Lo confirma:

- `opencode debug paths` → `config C:\Users\<user>\.config\opencode`
- [Documentación oficial](https://opencode.ai/docs/config/): "Place your global
  OpenCode config in `~/.config/opencode/opencode.json`"
- [Issue #535](https://github.com/NoeFabris/opencode-antigravity-auth/issues/251):
  "opencode config path on Windows uses `%APPDATA%` instead of `~/.config/opencode/`"

### Solución aplicada

Copiar todo el contenido de `%APPDATA%\opencode\` a `%USERPROFILE%\.config\opencode\`:

```powershell
$src = "$env:APPDATA\opencode"
$dst = "$env:USERPROFILE\.config\opencode"
New-Item -ItemType Directory -Path $dst -Force
Copy-Item "$src\opencode.json" "$dst\" -Force
Copy-Item "$src\AGENTS.md" "$dst\" -Force
Copy-Item "$src\tui.json" "$dst\" -Force
Copy-Item "$src\opencode.jsonc" "$dst\" -Force
Copy-Item "$src\agents\*" "$dst\agents\" -Force
Copy-Item -Recurse "$src\plugins" "$dst\" -Force
```

### Lección

El wizard de Lara Diaries (y potencialmente gentle-ai) tienen hardcodeado
`%APPDATA%` para Windows, pero opencode 1.17+ usa `~/.config/opencode/` cross-platform.
**Fix propuesto**: cambiar `modules/wizard-core.ps1` línea 746 para que detecte
la plataforma y use la ruta correcta:

```powershell
function Get-OpencodeConfigDir {
    if ($env:XDG_CONFIG_HOME) {
        return Join-Path $env:XDG_CONFIG_HOME "opencode"
    }
    # opencode 1.17+ usa ~/.config/opencode/ incluso en Windows
    return Join-Path $HOME ".config\opencode"
}
```

---

## Problema 2 — Placeholders de prompts sin resolver

### Síntoma

El `opencode.json` generado contiene `"prompt": "{{LARA_PLAN_PROMPT}}"` y
`"prompt": "{{LARA_VIP_PROMPT}}"` en lugar de referencias a los archivos de agentes.

### Causa raíz

La función `Generate-OpencodeJson` en `modules/wizard-core.ps1` intenta reemplazar
los placeholders con el contenido de los archivos de agente (líneas 730-739):

```powershell
$planPromptFile = Join-Path $agentsDir "lara-plan.md"
if (Test-Path -LiteralPath $planPromptFile) {
    $planPrompt = Get-Content -Path $planPromptFile -Raw -Encoding UTF8
    $config.agent."lara-plan".prompt = $planPrompt
}
```

Pero esta función **nunca se ejecutó correctamente** porque el proceso principal
(`bootstrap.ps1 --non-interactive`) hizo timeout antes de llegar a generar el JSON.
Además, el template base (`templates/configs/opencode.json`) usa placeholders
`{{LARA_PLAN_PROMPT}}` pero la referencia viva (`opencode-config/config/opencode.json`)
usa `{file:./agents/lara-plan.md}` (referencia a archivo externo).

### Solución aplicada

Usar el `opencode.json` de referencia del propio repo, que ya tiene las referencias
correctas:

```powershell
Copy-Item "C:\lara-diaries\opencode-config\config\opencode.json" "$configDir\opencode.json" -Force
```

Este archivo reference usa `{file:./agents/lara-plan.md}` que opencode resuelve
relativo al directorio de config.

### Lección

El template base y el config de referencia **divergieron**. El template usa
placeholders inline, el config de referencia usa `{file:...}`. El wizard debería
generar usando el config de referencia o actualizar el template para coincidir.
Fix propuesto:

1. `templates/configs/opencode.json` debería usar `{file:./agents/...}` como
   el config de referencia
2. `Generate-OpencodeJson` debería copiar el config de referencia y solo
   modificar los permisos según preferencias, no reemplazar prompts

---

## Problema 3 — MCP Context7 faltante

### Síntoma

- `opencode mcp list` solo muestra Engram MCP
- El template base no incluye Context7

### Causa raíz

El template `templates/configs/opencode.json` solo define Engram en la sección
`mcp`. El config de referencia (`opencode-config/config/opencode.json`) también
incluye **Context7**:

```json
"mcp": {
    "context7": {
        "enabled": true,
        "type": "remote",
        "url": "https://mcp.context7.com/mcp"
    },
    "engram": {
        "command": ["engram", "mcp", "--tools=agent"],
        "type": "local"
    }
}
```

### Solución aplicada

Copiar el config de referencia (misma solución que Problema 2).

### Lección

El template base está desactualizado respecto al config de referencia. Cualquier
nuevo MCP debe agregarse en AMBOS lugares, o el installer debe usar el config de
referencia como source of truth.

---

## Problema 4 — Agentes extra faltantes

### Síntoma

El `opencode.json` generado solo tiene 12 agentes (lara-plan, lara-vip, y 10
SDD sub-agents). El config de referencia tiene 20:
- `gentle-orchestrator` (hidden orchestrator)
- `jd-fix-agent`, `jd-judge-a`, `jd-judge-b` (judgment-day)
- `review-readability`, `review-reliability`, `review-resilience`, `review-risk`
- SDD agents con prompts mejorados (referencian SKILL.md)

### Causa raíz

El template base (`templates/configs/opencode.json`) no incluye los agents de
revisión ni el orchestrator con los prompts correctos.

### Solución aplicada

Copiar el config de referencia (misma solución que Problema 2 y 3).

---

## Problema 5 — SDD Skills no instaladas

### Síntoma

Los sub-agentes SDD tienen prompts que dicen:
`"Read your skill file at ~/.config/opencode/skills/sdd-apply/SKILL.md and follow it exactly."`

Pero ese archivo no existe.

### Causa raíz

Las SDD skills están en el repo de gentle-ai como templates embebidos en
`internal/assets/skills/sdd-*/SKILL.md`, pero el installer de Lara Diaries no
las copia al directorio de skills de opencode.

### Solución aplicada

Copiar las skills desde gentle-ai:

```powershell
$srcSkills = "C:\Users\Administrator\gentle-ai\internal\assets\skills"
$dstSkills = "$env:USERPROFILE\.config\opencode\skills"

$sddSkills = @("sdd-apply", "sdd-archive", "sdd-design", "sdd-explore",
               "sdd-init", "sdd-onboard", "sdd-propose", "sdd-spec",
               "sdd-tasks", "sdd-verify")

foreach ($skill in $sddSkills) {
    $src = "$srcSkills\$skill\SKILL.md"
    $destDir = "$dstSkills\$skill"
    New-Item -ItemType Directory -Path $destDir -Force
    Copy-Item $src "$destDir\SKILL.md" -Force
}
```

También copiar `_shared/SKILL.md` que es referenciado por varios SDD skills.

---

## Problema 6 — gentle-ai binario no instalado

### Síntoma

- `gentle-ai` no está en PATH
- `gentle-ai doctor` reporta `state file found with no installed agents`
- El directorio `C:\Users\Administrator\gentle-ai` existe pero solo tiene
  el source code (clonado vía git)

### Causa raíz

El wizard de Lara Diaries (`modules/wizard-core.ps1`, función `Install-Components`)
clona gentle-ai vía git pero **no ejecuta el install script** para descargar el
binario pre-compilado. El código relevante:

```powershell
$gaDir = Join-Path $HOME "gentle-ai"
$null = & git clone "https://github.com/Gentleman-Programming/gentle-ai.git" $gaDir 2>&1
# Intenta ejecutar install.ps1 pero falla silenciosamente
$gaInstaller = Join-Path $gaDir "scripts\install.ps1"
if (Test-Path -LiteralPath $gaInstaller) {
    $null = & $gaInstaller 2>&1
}
```

El problema es que `$null = & $gaInstaller 2>&1` descarta TODO el output del
installer, incluyendo errores. Además, el install.ps1 de gentle-ai requiere
`curl`, que puede no estar en PATH en Windows fresh.

### Solución aplicada

Ejecutar el install script de gentle-ai directamente:

```powershell
Set-Location "C:\Users\Administrator\gentle-ai"
.\scripts\install.ps1
```

Esto descarga el binario pre-compilado desde GitHub Releases y lo agrega al PATH.

### Lección

El wizard debería:
1. Verificar que `gentle-ai --version` funcione después de clonar
2. NO descartar el output del install script con `$null =`
3. Buscar el binario en `%LOCALAPPDATA%\gentle-ai\bin\` como fallback
4. Agregar `gentle-ai doctor` como verificación post-instalación

---

## Problema 7 — Engram serve no iniciado como servicio

### Síntoma

- El plugin `engram.ts` intenta iniciar `engram serve` vía `Bun.spawn()`
- Pero opencode en Windows no usa Bun, usa Node.js
- `Bun` no está definido → el plugin falla silenciosamente
- Engram MCP funciona (vía `engram mcp --tools=agent` en la config) pero
  el servidor HTTP de Engram (necesario para el plugin) no arranca

### Causa raíz

El plugin `plugins/engram.ts` usa APIs específicas de Bun:
- `Bun.which()`, `Bun.spawn()`, `Bun.spawnSync()`, `Bun.file()`
- opencode corre sobre Node.js, no Bun

### Solución aplicada

Iniciar `engram serve` manualmente como proceso de fondo:

```powershell
$engramBin = "C:\Users\Administrator\bin\engram.exe"
Start-Process -FilePath $engramBin -ArgumentList "serve" -WindowStyle Hidden
```

Y verificar con:

```powershell
Invoke-WebRequest -Uri "http://127.0.0.1:7437/health" -UseBasicParsing
```

### Lección

El plugin `engram.ts` necesita ser transpilado a JS puro o opencode necesita
soportar Bun APIs. Mientras tanto, el instalador de Lara Diaries debería
iniciar `engram serve` como servicio/configuración de inicio.

---

## Problema 8 — Permisos git incorrectos

### Síntoma

El template base tiene `"git commit *": "allow"` y `"git push": "allow"`.
El config de referencia tiene `"git commit *": "ask"` y `"git push": "ask"`.

### Causa raíz

El wizard configuró permisos "allow" según la preferencia "auto" del usuario.
Pero el config de referencia usa "ask" como default más seguro.

### Solución aplicada

Copiar el config de referencia con sus permisos "ask" por defecto.

### Lección

El usuario puede cambiar permisos después con `opencode config set`, pero el
default debería ser conservador ("ask").

---

## Problema 9 — Sin AGENTS.md ni tui.json

### Síntoma

Faltaban `AGENTS.md` (persona + protocolo Engram) y `tui.json` (subagent
statusline) en el directorio de config.

### Causa raíz

`Generate-OpencodeJson` solo genera `opencode.json`, no copia los archivos
auxiliares necesarios.

### Solución aplicada

Copiar desde el config de referencia:

```powershell
Copy-Item "$refDir\AGENTS.md" "$configDir\AGENTS.md" -Force
Copy-Item "$refDir\tui.json" "$configDir\tui.json" -Force
Copy-Item "$refDir\opencode.jsonc" "$configDir\opencode.jsonc" -Force
```

---

## Problema 10 — `gentle-ai install` no ejecutado

### Síntoma

- `gentle-ai doctor` muestra: `state file found with no installed agents`
- Los agents de opencode están configurados, pero gentle-ai no tiene registro
  de qué agents/configs gestiona

### Causa raíz

El wizard de Lara Diaries nunca ejecuta `gentle-ai install` para registrar
la instalación.

### Solución aplicada

Ejecutar:

```powershell
gentle-ai install --agents opencode --scope global --sdd-mode multi
```

### Resultado

```
✓ Installed opencode plugin (3 files)
  → C:\Users\Administrator\.config\opencode\plugins
✓ opencode-subagent-statusline in tui.json
✓ GGA installed to C:\Users\Administrator\bin\gga.bat
✓ Verification checks: 57 passed, 0 failed, 0 warnings, 0 skipped
```

**Qué instaló `gentle-ai install`:**
1. **Rosa ASCII** → `tui-plugins/gentle-logo.tsx` (reemplaza título de opencode)
2. **10 comandos SDD** → `commands/sdd-init.md`, `sdd-new.md`, `sdd-continue.md`, etc.
3. **Plugins extra** → `plugins/skill-registry.ts`, `plugins/model-variants.ts`
4. **22 skills** (antes 11) → agrega `branch-pr`, `chained-pr`, `cognitive-doc-design`, `comment-writer`, `go-testing`, `issue-creation`, `judgment-day`, `skill-creator`, `skill-improver`, `skill-registry`, `work-unit-commits`
5. **Prompts SDD** → `prompts/sdd/sdd-*.md`
6. **GGA** → `bin/gga.bat` (Gentleman Guardian Angel para git hooks)
7. **tui.json actualizado** → referencia `gentle-logo.tsx` + `opencode-subagent-statusline`

**No rompió**: los agentes `lara-plan` y `lara-vip` sobrevivieron con sus prompts `{file:./agents/lara-plan.md}` intactos.

### Lección

El wizard debería ejecutar `gentle-ai install --agents opencode --scope global --sdd-mode multi` como paso final de instalación.

---

## Problema 11 — gentle-ai doctor "unhealthy" por falta de Claude

### Síntoma

`gentle-ai doctor` reporta `Status: unhealthy` aunque todo funciona correctamente.

### Causa raíz

La única verificación que falla es `tool:claude` → `claude not found in PATH`.
En un entorno que solo usa opencode (no Claude CLI), esto es esperable y no
indica un problema real. Las otras 7 verificaciones pasan:

```
[ok] tool:gentle-ai     — gentle-ai found
[ok] tool:engram        — engram found
[ok] tool:gga           — gga found
[xx] tool:claude        — claude not in PATH (IRRELEVANTE)
[ok] tool:opencode      — opencode found
[ok] state:json         — 1 agent(s) installed: opencode
[ok] engram:reachable   — HTTP 200 at localhost:7437
[ok] disk:space         — 122 GB free
```

### Lección

`gentle-ai doctor` debería marcar `tool:claude` como opcional/warning, no como
failure. O al menos ignorarlo cuando opencode está presente.

---

## Problema 12 — Instalador no verifica que los agentes de lara sobrevivan

### Síntoma

`gentle-ai install` podría sobrescribir `opencode.json` y perder los agentes
de lara-diaries si el orden de instalación no es cuidadoso.

### Causa raíz

El wizard de lara escribe `opencode.json` primero, luego `gentle-ai install`
lo regenera. Si gentle-ai no preserva agentes externos (como `lara-plan`,
`lara-vip`), se pierden.

### Verificación

En este caso **los agentes sobrevivieron** (lara-plan.md + lara-vip.md intactos
en `agents/`, referencias `{file:...}` preservadas en `opencode.json`). Pero no
hay verificación explícita en el wizard.

### Lección

Agregar verificación post-instalación: `opencode agent list` debe mostrar
`lara-plan` y `lara-vip` después de `gentle-ai install`.

---

## Checklist de verificación post-instalación

```powershell
# 1. opencode funciona
opencode --version

# 2. Config cargada correctamente
opencode debug config | Select-String "lara-plan"

# 3. Agentes visibles (lara-plan, lara-vip)
opencode agent list

# 4. MCPs conectados (context7, engram)
opencode mcp list

# 5. gentle-ai instalado
gentle-ai --version

# 6. Engram server corriendo
curl -s http://127.0.0.1:7437/health

# 7. SDD skills instaladas
Get-ChildItem "$env:USERPROFILE\.config\opencode\skills\*\SKILL.md" | Measure-Line | % { $_.Count }

# 8. Rosa visible (abrir opencode y verificar)
#    → El título de opencode debe mostrar la rosa ASCII

# 9. Plugin Engram cargado
opencode debug info | Select-String "engram"

# 10. gentle-ai doctor (ignorar falta de claude)
gentle-ai doctor | Select-String "passed|failed"
```

---

## Archivos involucrados

| Archivo | Rol |
|---------|-----|
| `bootstrap/bootstrap.ps1` | Entry point de instalación |
| `modules/wizard-core.ps1` | Lógica del wizard (genera config, instala componentes) |
| `templates/configs/opencode.json` | Template base (desactualizado vs referencia) |
| `opencode-config/config/opencode.json` | Config de referencia (source of truth) |
| `opencode-config/config/AGENTS.md` | Persona + protocolo Engram |
| `opencode-config/config/plugins/engram.ts` | Plugin de memoria (usa Bun APIs) |
| `opencode-config/config/tui.json` | Subagent statusline |
| `scripts/sync-memories.ps1` | Sync de memorias vía git |

---

## Contribución propuesta

Para el PR a [orlinefoster/lara-diaries](https://github.com/orlinefoster/lara-diaries):

1. **Fix `Generate-OpencodeJson`**: usar `~/.config/opencode/` cross-platform
   en vez de `%APPDATA%\opencode\`
2. **Actualizar `templates/configs/opencode.json`**: sincronizar con
   `opencode-config/config/opencode.json` (agregar context7, JD agents, etc.)
3. **Fix `Install-Components`**: ejecutar `scripts/install.ps1` de gentle-ai
   y verificar resultado, no descartar output
4. **Agregar paso post-instalación**: copiar SDD skills desde gentle-ai a
   `~/.config/opencode/skills/`
5. **Iniciar `engram serve`** como parte del setup
6. **Agregar `AGENTS.md`** y `tui.json` al listado de archivos a copiar
