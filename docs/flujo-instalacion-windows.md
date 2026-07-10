# Flujo de Instalación — Windows

```mermaid
flowchart TD
    %% ===== ESTILOS =====
    classDef prompt fill:#e1f5fe,stroke:#0288d1,stroke-width:2px
    classDef check fill:#fff3e0,stroke:#f57c00,stroke-width:2px
    classDef install fill:#e8f5e9,stroke:#388e3c,stroke-width:2px
    classDef repo fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    classDef sync fill:#fff8e1,stroke:#f9a825,stroke-width:2px
    classDef personal fill:#fce4ec,stroke:#c62828,stroke-width:2px
    classDef done fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#2e7d32
    classDef skip fill:#f5f5f5,stroke:#9e9e9e,stroke-width:1px,color:#9e9e9e
    classDef error fill:#ffebee,stroke:#c62828,stroke-width:2px

    %% ===== INICIO =====
    start([Inicio]) --> gh_login

    %% ===== 1. GITHUB =====
    gh_login["🔐 GitHub Login"]:::prompt
    gh_login --> gh_check{gh auth válido?}:::check
    gh_check -- Sí --> gh_ok[✓ Autenticado]:::done
    gh_check -- No --> gh_auth[gh auth login]:::install
    gh_auth --> gh_ok

    %% ===== 2. DEV DIR =====
    gh_ok --> dev_dir["📁 Directorio de desarrollo"]:::prompt

    %% ===== 3. COMPONENT SELECTION =====
    dev_dir --> comp_sel["🤖 ¿Qué instalar?
    • Gentle AI & Skills
    • VSCode
    • Guardian Angel"]:::prompt

    %% ===== 4. REPO MODE =====
    comp_sel --> repo_mode["📦 Modo repos:
    • Auto
    • Ask
    • Manual"]:::prompt

    %% ===== 5. DESIGN & STYLE =====
    repo_mode --> design["🎨 Estilo y Design Doc"]:::prompt

    %% ===== 6. MISSION =====
    design --> mission["💻 Tipo de PC:
    • Personal
    • Trabajo
    • VM/Lab
    • Raspberry Pi"]:::prompt

    %% ===== 7. BACKUP =====
    mission --> backup_check{¿Config opencode
    existe en
    %APPDATA%\\opencode?}:::check
    backup_check -- Sí --> backup_prompt["💾 ¿Respaldar config existente?"]:::prompt
    backup_prompt --> backup_do[Respaldo en backups\\]:::install
    backup_check -- No --> skip_backup[Fresh install — sin backup]:::skip

    backup_do --> install_phase
    skip_backup --> install_phase

    %% ===== 8. INSTALL PHASE =====
    install_phase:::install --> ga_check{¿Gentle AI
    instalado?}:::check

    ga_check -- Sí --> ga_skip[Skip]:::skip
    ga_check -- No --> ga_install[Instalar Gentle AI]:::install
    ga_install --> skills_q{¿Gentleman Skills?}
    ga_skip --> engram_check

    skills_q -- No --> engram_check
    skills_q -- Sí --> skills_check{¿Ya instalados?}:::check
    skills_check -- Sí --> skills_skip[Skip]:::skip
    skills_check -- No --> skills_install[Instalar Skills]:::install
    skills_skip --> engram_check
    skills_install --> engram_check

    engram_check:::check --> engram_q{¿Engram
    instalado?}:::check
    engram_q -- Sí --> engram_skip[Skip]:::skip
    engram_q -- No --> engram_dl[Descargar de GitHub Releases]:::install
    engram_dl --> engram_verify[Verificar SHA256]:::check
    engram_verify --> engram_install[Instalar en PATH]:::install
    engram_skip --> vscode_q
    engram_install --> vscode_q

    vscode_q{¿Instalar VSCode?}
    vscode_q -- No --> gga_q
    vscode_q -- Sí --> vscode_check{¿Ya instalado?}:::check
    vscode_check -- Sí --> vscode_skip[Skip]:::skip
    vscode_check -- No --> vscode_do[Instalar VSCode
    (winget / chocolatey)]:::install
    vscode_skip --> gga_q
    vscode_do --> gga_q

    gga_q:::check --> gga_ask{¿Instalar
    Guardian Angel?}
    gga_ask -- No --> templates
    gga_ask -- Sí --> gga_check_inst{¿Ya instalado?}:::check
    gga_check_inst -- Sí --> gga_skip[Skip]:::skip
    gga_check_inst -- No --> gga_do[Instalar GGA]:::install
    gga_skip --> templates
    gga_do --> templates

    templates[📝 Copiar templates de agente
    y generar opencode.json]:::install

    %% ===== 9. REPO PHASE =====
    templates --> repo_phase:::repo

    repo_phase --> repo_engram_check{¿Repo
    engram-memories
    existe en GitHub?}:::check
    repo_engram_check -- Sí --> repo_engram_clone_check{¿Clonado
    localmente?}:::check
    repo_engram_check -- No --> repo_engram_create[Crear repo privado]:::repo
    repo_engram_create --> repo_engram_clone[Clonar a
    ~\\engram-memories\\]:::repo
    repo_engram_clone_check -- Sí --> repo_engram_pull[git pull]:::repo
    repo_engram_clone_check -- No --> repo_engram_clone
    repo_engram_pull --> repo_opencode_check

    repo_engram_clone --> repo_opencode_check
    repo_opencode_check:::check --> repo_opencode_q{¿Repo
    opencode-config
    existe en GitHub?}:::check
    repo_opencode_q -- Sí --> repo_opencode_clone_check{¿Clonado
    localmente?}:::check
    repo_opencode_q -- No --> repo_opencode_create[Crear repo privado]:::repo
    repo_opencode_create --> repo_opencode_first_push[Backup inicial de config]:::repo
    repo_opencode_first_push --> sync_phase
    repo_opencode_clone_check -- Sí --> repo_opencode_pull[git pull]:::repo
    repo_opencode_clone_check -- No --> repo_opencode_clone[Clonar a
    ~\\opencode-config\\]:::repo
    repo_opencode_pull --> sync_phase
    repo_opencode_clone --> sync_phase

    %% ===== 10. SYNC PHASE =====
    sync_phase:::sync --> sync_setup["🔄 Configurar
    Scheduled Task de Windows
    (cada 30 min)"]:::sync
    sync_setup --> sync_engram[Ejecutar sync.ps1
    de engram-memories]:::sync
    sync_engram --> sync_config[Ejecutar
    sync-opencode-config.ps1]:::sync

    %% ===== 11. PERSONALIZATION PHASE =====
    sync_config --> check_profile{¿Perfil de Lara
    ya guardado en
    opencode-config?}:::check
    check_profile -- Sí --> personal_skip["⏭️ Saltar personalización
    (usar perfil existente)"]:::skip
    check_profile -- No --> personal_start:::personal

    personal_start --> pronouns["👤 Pronombres"]:::personal
    pronouns --> skill["📚 Nivel de informática"]:::personal
    skill --> assistance["🤝 Modo de asistencia"]:::personal
    assistance --> save_profile[💾 Guardar perfil
    en $env:LOCALAPPDATA\\LaraDiaries\\]:::personal

    personal_skip --> summary
    save_profile --> summary

    %% ===== 12. SUMMARY =====
    summary["📋 Mostrar resumen final"]:::done
    summary --> verify["🔍 Verificación post-instalación
    • ¿engram en PATH?
    • ¿Scheduled Tasks activos?
    • ¿repos clonados?"]:::check
    verify --> done([✅ Instalación completa]):::done

    %% ===== NOTAS =====
    subgraph Legend
        direction LR
        L1:::prompt
        L2:::install
        L3:::check
        L4:::repo
        L5:::sync
        L6:::personal
        L7:::done
    end
```
