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
| Repos GitHub | `gh repo view $USER/$repo` |

### 2. Orden inmodificable

```
LO MÍNIMO PARA INSTALAR:
  1. GitHub Login
  2. Directorio de desarrollo
  3. Qué componentes instalar (Gentle AI, Skills, VSCode)
  4. Backup de config existente (si aplica)

INSTALACIÓN:
  5. Instalar componentes (verificando cada uno antes)
  6. Repos: crear/clonar engram-memories + opencode-config
   7. Sync: configurar cron (Linux) / Scheduled Tasks (Windows) + sync inicial
  8. Verificar que todo funciona

TODO AL FINAL — SOLO SI NUNCA SE CONFIGURÓ:
  9. ¿Ya existe perfil guardado en opencode-config?
       ├── Sí → ⏭️ saltar TODO, no preguntar nada
       └── No → preguntar en orden:
             a. Modo repos (Auto/Ask/Manual)
             b. Estilo y Design Doc
             c. Tipo de PC (misión)
             d. Pronombres
             e. Nivel de informática
             f. Modo de asistencia
           → Guardar perfil + sincronizar a opencode-config
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
