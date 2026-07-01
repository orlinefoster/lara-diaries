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

**No necesitás saber programar.** Si llegaste hasta acá, ya está.

---

## 🚀 Instalación (3 pasos)

### Paso 1: Instalá opencode

> opencode es el "motor" que hace funcionar a Lara.

**Windows:**
```
winget install OpenCode
```

**Linux:**
```bash
curl -fsSL https://opencode.ai/install.sh | sh
```

> Si `winget` no funciona en Windows, bajalo de [opencode.ai](https://opencode.ai) y ejecutá el installer.

### Paso 2: Cloná este repositorio

```
git clone https://github.com/orlinefoster/lara-diaries.git
cd lara-diaries
```

> 💡 **Tip**: Si no sabés qué es "git" o "terminal", no te preocupes. Abrí PowerShell (Windows) o Terminal (Linux) y pegá los comandos de arriba, uno por uno.

### Paso 3: Iniciá la magia

Abrí opencode:
```
opencode
```

Y dentro de opencode, escribí este mensaje:

> **"Baja e inicia este repositorio"**

O si querés ser más específica:

> **"Baja e inicia este repo https://github.com/orlinefoster/lara-diaries"**

Lara va a tomar el control desde ahí. Te va a hacer **7 preguntas** (cosas como tu nombre, nivel de experiencia, si querés VSCode, etc.) y en **5-10 minutos** vas a tener todo configurado.

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

## 🧭 Estructura del proyecto (para curiosas)

```
lara-diaries/
├── bootstrap-agent.md     # El "plan" que sigue Lara en tu primer uso
├── bootstrap/             # Scripts de instalación (Windows y Linux)
├── modules/               # Lógica del asistente de configuración
├── templates/             # Plantillas para crear agentes personalizados
├── guardian/              # Reglas de seguridad del sistema
├── scripts/               # Sincronización de memorias
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

---

## 📜 Licencia

MIT — hacé lo que quieras con esto.

---

Hecho con 🧉 y mucho cariño para quienes se animan a empezar.
