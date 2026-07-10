# Lógica de Instalación — Resumen

## Principios del nuevo flujo

### 1. Verificar antes de instalar (idempotencia)

Cada componente se verifica antes de instalar. Si ya existe, se salta:

| Componente | Cómo se verifica |
|-----------|-----------------|
| Gentle AI | `command -v gentle-ai` / `Get-Command gentle-ai` |
| Engram | `command -v engram` / `Get-Command engram` |
| Gentleman Skills | `~/.config/opencode/skills/gentleman-skills/` |
| VSCode | `command -v code` / `Get-Command code` |
| GGA | `command -v guardian` / `Get-Command guardian` |
| Repos GitHub | `gh repo view $USER/$repo` |

### 2. Orden inmodificable

```
1. PREGUNTAS (configuración del usuario: modo repos, estilo, misión, qué instalar)
2. INSTALAR (todo lo que haga falta)
3. REPOS (clonar o crear si no existen)
4. SYNC (configurar automatización + sync inicial)
5. VERIFICAR (que todo funcione: engram, timers, repos)
6. PERSONALIZACIÓN — SOLO SI NUNCA SE CONFIGURÓ
   └── ¿Ya existe perfil guardado en opencode-config?
        ├── Sí → ⏭️ saltar, no preguntar nada
        └── No → preguntar pronombres, nivel, asistencia
```

### 3. Repos: primero verificar, después crear o clonar

```
¿Existe el repo en GitHub?
  ├── Sí → ¿Está clonado localmente?
  │        ├── Sí → git pull (actualizar)
  │        └── No → gh repo clone
  └── No → gh repo create --private → clonar
```

### 4. No pisar configuración existente

- Si `~/.config/opencode/` (Linux) o `%APPDATA%/opencode/` (Windows) ya existe:
  - Preguntar si respaldar antes de instalar
  - Los templates de agente se agregan, no reemplazan
  - `opencode.json` generado hace merge, no overwrite

### 5. Personalización al final — regla estricta

Las preguntas de reconocimiento (pronombres, nivel, asistencia) se hacen **al final, después de verificar** que la instalación fue exitosa. Y solo si se cumple **esta condición**:

```
SI el perfil NO existe en opencode-config → preguntar
SI el perfil SÍ existe en opencode-config → ⏭️ saltar sin preguntar nada
```

**¿Por qué después de verificar?** Porque si la instalación falla, no tiene sentido personalizar nada. Primero asegurarse de que todo funciona, luego configurar a la persona.

**¿Por qué revisar opencode-config y no el disco local?** Porque si la persona ya configuró Lara en otra PC y restauró su `opencode-config` (o modificó algo ahí), el perfil ya está disponible. Preguntar de nuevo pisaría esa configuración.

**¿Qué pasa si la persona modificó algo en opencode-config directamente?**
- El perfil existe → no se pregunta → no se pisa nada
- La persona siempre puede reconfigurar después con un comando tipo `/lara-config`

Esto permite:
- Usuarios nuevos: configuran Lara al final, después de verificar
- Usuarios existentes con backup: restauran su perfil sin repetir preguntas
- Reinstalaciones: el perfil sobrevive en opencode-config
- Modificaciones manuales: nunca se sobrescriben
