# Lara Diaries - Wizard Core (PowerShell)
# Import: . .\modules\wizard-core.ps1
#
# Compatible with Windows PowerShell 5.1 and PowerShell Core 7+.

# ── SCRIPT STATE ──────────────────────────────
$script:UserProfile = @{}
$script:WizardAnswers = @{}

# ── COLOR HELPERS ─────────────────────────────
function Write-Success  { Write-Host "+ $($args[0])" -ForegroundColor Green }
function Write-Warn     { Write-Host "! $($args[0])" -ForegroundColor Yellow }
function Write-Info     { Write-Host "-> $($args[0])" -ForegroundColor Cyan }
function Write-ErrorMsg { Write-Host "x $($args[0])" -ForegroundColor Red }
function Write-Step     { Write-Host "`n  == $($args[0])" -ForegroundColor Magenta }

# ── STEP STATE ────────────────────────────────
function Write-StepState {
    param(
        [string]$StepName,
        [string]$Status,
        [string]$ErrorMsg = $null,
        [string]$Rollback = $null
    )
    # Use bootstrap.ps1's Update-StepState if available, otherwise work standalone
    if (Get-Command "Update-StepState" -ErrorAction SilentlyContinue) {
        Update-StepState -StepName $StepName -Status $Status -ErrorMsg $ErrorMsg -Rollback $Rollback
        return
    }
    # Standalone fallback
    $stateDir = Join-Path $env:LOCALAPPDATA "LaraDiaries"
    $stateFile = Join-Path $stateDir "state.json"
    if (-not (Test-Path -LiteralPath $stateDir)) {
        $null = New-Item -ItemType Directory -Path $stateDir -Force -ErrorAction SilentlyContinue
    }
    $state = $null
    if (Test-Path -LiteralPath $stateFile) {
        try {
            $state = Get-Content -Path $stateFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Warn "[!] state.json corrupto en wizard-core -- regenerando."
            Remove-Item -Path $stateFile -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $state) {
        $state = [PSCustomObject]@{
            version      = 1
            install_id   = [guid]::NewGuid().ToString()
            created_at   = (Get-Date).ToString("o")
            updated_at   = (Get-Date).ToString("o")
            install_type = "unknown"
            steps        = [PSCustomObject]@{}
        }
    }
    $now = (Get-Date).ToString("o")
    if (-not $state.steps.$StepName) {
        $state.steps | Add-Member -NotePropertyName $StepName -NotePropertyValue ([PSCustomObject]@{
            status       = "pending"
            started_at   = $now
            completed_at = $null
            error        = $null
            rollback     = $null
        }) -Force
    }
    $state.steps.$StepName.status = $Status
    $state.updated_at = $now
    if ($Status -in @("success","failed","skipped")) {
        $state.steps.$StepName.completed_at = $now
    }
    if ($ErrorMsg) { $state.steps.$StepName.error = $ErrorMsg }
    if ($Rollback) { $state.steps.$StepName.rollback = $Rollback }
    try {
        $json = $state | ConvertTo-Json -Compress
        $json | Set-Content -Path $stateFile -Encoding UTF8 -Force
    } catch {
        Write-Warn "[!] No se pudo escribir state.json desde wizard-core: $_"
    }
}

# ── ROLLBACK HELPERS ──────────────────────────
function Rollback-GitClone {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Write-Warn "  Rollback: eliminando $Path"
        Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Rollback-ConfigChange {
    param([string]$BackupPath, [string]$OriginalPath)
    if (Test-Path -LiteralPath $BackupPath) {
        Write-Warn "  Rollback: restaurando $OriginalPath desde backup"
        Copy-Item -Path $BackupPath -Destination $OriginalPath -Force -ErrorAction SilentlyContinue
    }
}

# ── PROGRESS ──────────────────────────────────
$script:ProgressSteps = @(
    "Login de GitHub",
    "Directorio de proyectos",
    "Gentle AI",
    "Preferencias personales",
    "Gestion de repos",
    "Disenio y estilo",
    "Mision del equipo",
    "Backup de config existente",
    "Instalacion",
    "Sincronizacion",
    "Resumen final",
    "Verificacion post-instalacion"
)
$script:ProgressTotal = 12

function Set-Progress {
    param([int]$Step, [string]$Status = "...")
    $pct = [math]::Min(100, [math]::Max(0, [int](($Step / $script:ProgressTotal) * 100)))
    $label = $script:ProgressSteps[$Step]
    Write-Progress -Activity "Lara Diaries - Configuracion" -Status $label -CurrentOperation $Status -PercentComplete $pct
}

# ── DRY-RUN HELPERS ──────────────────────────
function Read-HostOrDefault {
    param([string]$Prompt, [string]$Default = "")
    if ($script:IsDryRun) {
        Write-Host "  $Prompt [$Default] (dry-run, usando default)" -ForegroundColor Gray
        return $Default
    }
    $input = Read-Host "  $Prompt"
    if ([string]::IsNullOrWhiteSpace($input)) { return $Default }
    return $input.Trim()
}

# ── CROSS-PLATFORM CONFIG PATH ────────────────
function Get-OpencodeConfigDir {
    <#
    .SYNOPSIS
        Returns the cross-platform opencode config directory.
        opencode 1.17+ uses ~/.config/opencode/ on ALL platforms (including Windows).
    .EXAMPLE
        $dir = Get-OpencodeConfigDir
    #>
    if ($env:XDG_CONFIG_HOME) {
        return Join-Path $env:XDG_CONFIG_HOME "opencode"
    }
    # opencode 1.17+ uses ~/.config/opencode/ even on Windows
    return Join-Path $HOME ".config/opencode"
}

# ── 1. GITHUB LOGIN ──────────────────────────
function Invoke-GitHubLogin {
    Write-Step "Paso 1/10 - Login de GitHub"
    Set-Progress -Step 0 -Status "Verificando autenticacion..."

    $gh = Get-Command "gh" -ErrorAction SilentlyContinue
    if (-not $gh) {
        Write-ErrorMsg "gh CLI no esta instalado. Ejecuta bootstrap.ps1 primero."
        throw "gh CLI not found"
    }

    $oldEAP = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $null = & gh auth status 2>$null
    $isAuthed = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $oldEAP

    if ($isAuthed) {
        Write-Success "Ya estas autenticado en GitHub."
    } else {
        Write-Warn "No estas autenticado. Iniciando login..."
        try {
            $null = & gh auth login --web
            if ($LASTEXITCODE -ne 0) { throw "gh auth login fallo" }
            Write-Success "Autenticacion exitosa."
        } catch {
            Write-ErrorMsg "Error en autenticacion: $_"
            throw
        }
    }

    try {
        $oldEAP = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        $username = & gh api user --jq .login 2>$null
        if (-not $username -or $LASTEXITCODE -ne 0) {
            $json = & gh api user 2>$null
            if ($json) {
                $obj = $json | ConvertFrom-Json
                $username = $obj.login
            }
        }
        $ErrorActionPreference = $oldEAP
        if ($username) {
            $script:WizardAnswers.GitHubUser = $username.Trim()
            Write-Success "Usuario: $($script:WizardAnswers.GitHubUser)"
        } else {
            Write-Warn "No se pudo capturar el username de GitHub."
            $script:WizardAnswers.GitHubUser = ""
        }
    } catch {
        Write-Warn "No se pudo obtener el usuario de GitHub: $_"
        $script:WizardAnswers.GitHubUser = ""
    }
}

# ── 2. DEV DIRECTORY ─────────────────────────
function Invoke-DevDirectoryPrompt {
    Write-Step "Paso 2/10 - Directorio de proyectos"
    Set-Progress -Step 1 -Status "Preguntando directorio..."

    $suggested = Join-Path $HOME "Documents\Develops"
    Write-Host "  Donde queres guardar tus proyectos?" -ForegroundColor White
    Write-Host "  (predeterminado: $suggested)" -ForegroundColor Gray
    $input = Read-Host "  Ruta"

    if ([string]::IsNullOrWhiteSpace($input)) {
        $script:WizardAnswers.DevDir = $suggested
    } else {
        $script:WizardAnswers.DevDir = $input.Trim()
    }

    if (-not (Test-Path -LiteralPath $script:WizardAnswers.DevDir)) {
        try {
            $null = New-Item -ItemType Directory -Path $script:WizardAnswers.DevDir -Force
            Write-Success "Creado: $($script:WizardAnswers.DevDir)"
        } catch {
            Write-ErrorMsg "No se pudo crear el directorio: $_"
            throw
        }
    } else {
        Write-Success "Ya existe: $($script:WizardAnswers.DevDir)"
    }
}

# ── 3. GENTLE AI ─────────────────────────────
function Invoke-GentleAIPrompt {
    Write-Step "Paso 3/10 - Gentle AI"
    Set-Progress -Step 2 -Status "Preguntando por Gentle AI..."

    $installAI = Read-Host "  Queres instalar Gentle AI? (S/N, predeterminado: S)"
    $val = ($installAI -eq "" -or $installAI -like "S*" -or $installAI -like "s*")
    $script:WizardAnswers.InstallGentleAI = $val

    if ($val) {
        $installSkills = Read-Host "  Instalar tambien Gentleman Skills? (S/N, predeterminado: S)"
        $val2 = ($installSkills -eq "" -or $installSkills -like "S*" -or $installSkills -like "s*")
        $script:WizardAnswers.InstallGentlemanSkills = $val2
        if ($val2) { Write-Success "Gentle AI + Gentleman Skills" }
        else { Write-Info "Solo Gentle AI" }
    } else {
        $script:WizardAnswers.InstallGentlemanSkills = $false
        Write-Info "Instalacion basica (solo engram)"
    }

    # VSCode (optional but recommended)
    $installVSCode = Read-Host "  Instalar VSCode? (editor de codigo, S/N, predeterminado: S)"
    $val3 = ($installVSCode -eq "" -or $installVSCode -like "S*" -or $installVSCode -like "s*")
    $script:WizardAnswers.InstallVSCode = $val3
    if ($val3) { Write-Success "VSCode incluido" }
    else { Write-Info "VSCode omitido" }
    $script:UserProfile.InstallVSCode = $val3

    Save-UserProfile
}

# ── 4. RECOGNITION QUESTIONS ─────────────────
function Invoke-RecognitionQuestions {
    Write-Step "Paso 4/10 - Preferencias personales"
    Set-Progress -Step 3 -Status "Preguntas de reconocimiento..."

    # Q1: Pronouns
    Write-Host "`n  1. Que pronombres usas?" -ForegroundColor White
    Write-Host "     1) she/her" -ForegroundColor Gray
    Write-Host "     2) they/them" -ForegroundColor Gray
    Write-Host "     3) he/him" -ForegroundColor Gray
    Write-Host "     4) it/its" -ForegroundColor Gray
    Write-Host "     5) other" -ForegroundColor Gray
    $choice = Read-Host "  Opcion (1-5, predeterminado: 2)"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "2" }
    switch ($choice.Trim()) {
        "1" { $script:WizardAnswers.Pronoun = "she/her" }
        "2" { $script:WizardAnswers.Pronoun = "they/them" }
        "3" { $script:WizardAnswers.Pronoun = "he/him" }
        "4" { $script:WizardAnswers.Pronoun = "it/its" }
        "5" {
            $custom = Read-Host "    Decime cual"
            if ([string]::IsNullOrWhiteSpace($custom)) { $custom = "they/them" }
            $script:WizardAnswers.Pronoun = $custom.Trim()
        }
        default {
            Write-Warn "Opcion invalida, usando they/them"
            $script:WizardAnswers.Pronoun = "they/them"
        }
    }
    Write-Success "Pronombres: $($script:WizardAnswers.Pronoun)"

    # Q2: Tech skill level
    Write-Host "`n  2. Cuanto sabes de informatica?" -ForegroundColor White
    Write-Host "     1) full-fearless" -ForegroundColor Gray
    Write-Host "     2) me-defiendo" -ForegroundColor Gray
    Write-Host "     3) me-invito-un-amigo" -ForegroundColor Gray
    $choice2 = Read-Host "  Opcion (1-3, predeterminado: 2)"
    if ([string]::IsNullOrWhiteSpace($choice2)) { $choice2 = "2" }
    switch ($choice2.Trim()) {
        "1" { $script:WizardAnswers.SkillLevel = "full-fearless" }
        "2" { $script:WizardAnswers.SkillLevel = "me-defiendo" }
        "3" { $script:WizardAnswers.SkillLevel = "me-invito-un-amigo" }
        default {
            Write-Warn "Opcion invalida, usando me-defiendo"
            $script:WizardAnswers.SkillLevel = "me-defiendo"
        }
    }
    Write-Success "Nivel: $($script:WizardAnswers.SkillLevel)"

    # Skill level description
    $desc = $script:WizardAnswers.SkillLevel
    if ($desc -eq "full-fearless") { $script:WizardAnswers.SkillLevelDesc = "Assume competence, focus on trade-offs" }
    elseif ($desc -eq "me-defiendo") { $script:WizardAnswers.SkillLevelDesc = "Explain the why behind each decision" }
    else { $script:WizardAnswers.SkillLevelDesc = "Start from basics, be gentle" }

    # Q3: Assistance level
    Write-Host "`n  3. Cuanta asistencia queres?" -ForegroundColor White
    Write-Host "     1) full (explica todo)" -ForegroundColor Gray
    Write-Host "     2) medium (resume y chequea)" -ForegroundColor Gray
    Write-Host "     3) minimal (confianza)" -ForegroundColor Gray
    $choice3 = Read-Host "  Opcion (1-3, predeterminado: 2)"
    if ([string]::IsNullOrWhiteSpace($choice3)) { $choice3 = "2" }
    switch ($choice3.Trim()) {
        "1" { $script:WizardAnswers.AssistanceMode = "full" }
        "2" { $script:WizardAnswers.AssistanceMode = "medium" }
        "3" { $script:WizardAnswers.AssistanceMode = "minimal" }
        default {
            Write-Warn "Opcion invalida, usando medium"
            $script:WizardAnswers.AssistanceMode = "medium"
        }
    }
    Write-Success "Asistencia: $($script:WizardAnswers.AssistanceMode)"

    $script:UserProfile.Pronoun = $script:WizardAnswers.Pronoun
    $script:UserProfile.SkillLevel = $script:WizardAnswers.SkillLevel
    $script:UserProfile.SkillLevelDesc = $script:WizardAnswers.SkillLevelDesc
    $script:UserProfile.AssistanceMode = $script:WizardAnswers.AssistanceMode
    Save-UserProfile
}

# ── 5. REPO MANAGEMENT ───────────────────────
function Invoke-RepoManagementPrompt {
    Write-Step "Paso 5/10 - Gestion de repos"
    Set-Progress -Step 4 -Status "Preguntando gestion de repos..."

    Write-Host "  Como queres manejar los repos?" -ForegroundColor White
    Write-Host "     1) auto (Lara gestiona todo)" -ForegroundColor Gray
    Write-Host "     2) ask (preguntar antes)" -ForegroundColor Gray
    Write-Host "     3) manual (yo manejo git)" -ForegroundColor Gray
    $choice = Read-Host "  Opcion (1-3, predeterminado: 1)"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }
    switch ($choice.Trim()) {
        "1" { $script:WizardAnswers.RepoMode = "auto" }
        "2" { $script:WizardAnswers.RepoMode = "ask" }
        "3" { $script:WizardAnswers.RepoMode = "manual" }
        default { $script:WizardAnswers.RepoMode = "auto" }
    }
    Write-Success "Modo repos: $($script:WizardAnswers.RepoMode)"
}

# ── 6. DESIGN ORIENTATION ────────────────────
function Invoke-DesignOrientationPrompt {
    Write-Step "Paso 6/10 - Disenio y estilo"
    Set-Progress -Step 5 -Status "Preguntando preferencias de disenio..."

    $useDesign = Read-Host "  Usar design.md como guia? (S/N, predeterminado: S)"
    $val = ($useDesign -eq "" -or $useDesign -like "S*" -or $useDesign -like "s*")
    $script:WizardAnswers.UseDesignDoc = $val
    if ($val) { Write-Success "design.md: habilitado" }
    else { Write-Info "design.md: deshabilitado" }

    Write-Host "`n  Que estilo visual te gusta?" -ForegroundColor White
    Write-Host "     1) clean-ui" -ForegroundColor Gray
    Write-Host "     2) pink-kawaii" -ForegroundColor Gray
    Write-Host "     3) dark-academia" -ForegroundColor Gray
    Write-Host "     4) retro-futuristic" -ForegroundColor Gray
    Write-Host "     5) business" -ForegroundColor Gray
    Write-Host "     6) full-backend" -ForegroundColor Gray
    $choice = Read-Host "  Opcion (1-6, predeterminado: 1)"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }
    switch ($choice.Trim()) {
        "1" { $script:WizardAnswers.Style = "clean-ui" }
        "2" { $script:WizardAnswers.Style = "pink-kawaii" }
        "3" { $script:WizardAnswers.Style = "dark-academia" }
        "4" { $script:WizardAnswers.Style = "retro-futuristic" }
        "5" { $script:WizardAnswers.Style = "business" }
        "6" { $script:WizardAnswers.Style = "full-backend" }
        default { $script:WizardAnswers.Style = "clean-ui" }
    }
    Write-Success "Estilo: $($script:WizardAnswers.Style)"
}

# ── 7. MISSION ────────────────────────────────
function Invoke-MissionPrompt {
    Write-Step "Paso 7/10 - Mision del equipo"
    Set-Progress -Step 6 -Status "Preguntando mision..."

    Write-Host "  Esta PC es:" -ForegroundColor White
    Write-Host "     1) personal-important" -ForegroundColor Gray
    Write-Host "     2) work" -ForegroundColor Gray
    Write-Host "     3) vm" -ForegroundColor Gray
    Write-Host "     4) lab-raspberry" -ForegroundColor Gray
    $choice = Read-Host "  Opcion (1-4, predeterminado: 1)"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }
    switch ($choice.Trim()) {
        "1" { $script:WizardAnswers.Mission = "personal-important" }
        "2" { $script:WizardAnswers.Mission = "work" }
        "3" { $script:WizardAnswers.Mission = "vm" }
        "4" { $script:WizardAnswers.Mission = "lab-raspberry" }
        default { $script:WizardAnswers.Mission = "personal-important" }
    }

    $m = $script:WizardAnswers.Mission
    if ($m -eq "personal-important") { $script:WizardAnswers.Discretion = "high-caution" }
    elseif ($m -eq "work") { $script:WizardAnswers.Discretion = "moderate" }
    elseif ($m -eq "vm") { $script:WizardAnswers.Discretion = "relaxed" }
    else { $script:WizardAnswers.Discretion = "very-relaxed" }

    Write-Success "Mision: $($script:WizardAnswers.Mission)"

    $script:UserProfile.Mission = $script:WizardAnswers.Mission
    $script:UserProfile.Discretion = $script:WizardAnswers.Discretion
    Save-UserProfile
}

# ── TEST USER PROFILE EXISTS ─────────────────
function Test-UserProfileExists {
    # Priority 1: profile synced to opencode-config repo
    $configRepoProfile = Join-Path $HOME "opencode-config\config\lara-diaries\user-profile.json"
    if (Test-Path -LiteralPath $configRepoProfile) {
        Write-Info "Perfil encontrado en opencode-config (sincronizado desde otro dispositivo)."
        return $true
    }

    # Priority 2: local profile
    $localProfile = Join-Path $env:LOCALAPPDATA "lara-diaries\user-profile.json"
    if (Test-Path -LiteralPath $localProfile) {
        Write-Info "Perfil encontrado localmente."
        return $true
    }

    return $false
}

# ── VERIFY INSTALLATION ─────────────────────
function Invoke-VerifyInstallation {
    Write-Host "`n  == Post-Install Verification" -ForegroundColor Magenta
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    $allOk = $true

    # 1. Engram
    if (Get-Command "engram" -ErrorAction SilentlyContinue) {
        Write-Success "Engram: instalado"
    } else {
        Write-Warn "Engram no encontrado en PATH."
        $allOk = $false
    }

    # 2. Gentle AI
    if (Get-Command "gentle-ai" -ErrorAction SilentlyContinue) {
        Write-Success "Gentle AI: instalado"
    } else {
        Write-Warn "Gentle AI no encontrado en PATH."
        $allOk = $false
    }

    # 3. GitHub auth
    $ghAuth = & gh auth status 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "GitHub: autenticado"
    } else {
        Write-Warn "GitHub no autenticado."
        $allOk = $false
    }

    # 4. Repos
    if (Test-Path -LiteralPath (Join-Path $HOME "engram-memories\.git")) {
        Write-Success "Repo engram-memories: clonado"
    } else {
        Write-Warn "Repo engram-memories no clonado."
        $allOk = $false
    }
    if (Test-Path -LiteralPath (Join-Path $HOME "opencode-config\.git")) {
        Write-Success "Repo opencode-config: clonado"
    } else {
        Write-Warn "Repo opencode-config no clonado."
        $allOk = $false
    }

    # 5. Scheduled tasks
    $tasks = Get-ScheduledTask -TaskPath "\LaraDiaries\" -ErrorAction SilentlyContinue
    if ($tasks) {
        Write-Success "Scheduled Tasks: configurados"
    } else {
        Write-Warn "No se encontraron Scheduled Tasks de Lara."
    }

    if ($allOk) {
        Write-Success "Todos los sistemas operacionales."
    } else {
        Write-Warn "Algunas verificaciones fallaron — revisar advertencias."
    }
}

# ── SAVE USER PROFILE (local + opencode-config) ──
function Save-UserProfile {
    $profileDir = Join-Path $env:LOCALAPPDATA "lara-diaries"
    if (-not (Test-Path -LiteralPath $profileDir)) {
        $null = New-Item -ItemType Directory -Path $profileDir -Force
    }
    $profilePath = Join-Path $profileDir "user-profile.json"
    try {
        $profile = [Ordered]@{
            version          = "1.0.0"
            created_at       = (Get-Date -Format "o")
            github_user      = $script:WizardAnswers.GitHubUser
            dev_directory    = $script:WizardAnswers.DevDir
            gentle_ai        = ($script:WizardAnswers.InstallGentleAI -eq $true)
            gentleman_skills = ($script:WizardAnswers.InstallGentlemanSkills -eq $true)
            vscode           = ($script:WizardAnswers.InstallVSCode -eq $true)
            pronouns         = $script:WizardAnswers.Pronoun
            skill_level      = $script:WizardAnswers.SkillLevel
            assistance_mode  = $script:WizardAnswers.AssistanceMode
            repo_management  = $script:WizardAnswers.RepoMode
            use_design_doc   = ($script:WizardAnswers.UseDesignDoc -ne $false)
            style            = $script:WizardAnswers.Style
            mission          = $script:WizardAnswers.Mission
        }
        $json = $profile | ConvertTo-Json -Compress
        $json | Set-Content -Path $profilePath -Encoding UTF8 -Force
        Write-Info "Perfil guardado en: $profilePath"

        # Also save to opencode-config repo if cloned
        $configRepoDir = Join-Path $HOME "opencode-config"
        if (Test-Path -LiteralPath (Join-Path $configRepoDir ".git")) {
            $configProfileDir = Join-Path $configRepoDir "config\lara-diaries"
            $null = New-Item -ItemType Directory -Path $configProfileDir -Force
            Copy-Item -Path $profilePath -Destination (Join-Path $configProfileDir "user-profile.json") -Force
            Push-Location $configRepoDir
            & git add "config/lara-diaries/user-profile.json"
            & git commit -m "profile: save Lara user profile" 2>$null
            & git push 2>$null
            Pop-Location
            Write-Info "Perfil sincronizado a opencode-config."
        }
    } catch {
        Write-Warn "No se pudo guardar el perfil: $_"
    }
}

# ── BACKUP EXISTING CONFIG ───────────────────
function Backup-ExistingConfig {
    param([string]$Mode = "full")

    $configDir = Join-Path $HOME ".config\opencode"
    $backupDir = Join-Path $PSScriptRoot "..\backups"
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $backupDir "opencode-config-$timestamp"

    if (-not (Test-Path -LiteralPath $configDir)) {
        Write-Info "No hay config existente para backupear."
        return $null
    }

    try {
        $null = New-Item -ItemType Directory -Path $backupPath -Force
        Write-Info "Backupeando config en: $backupPath"

        # Always backup main config
        $configFile = Join-Path $configDir "opencode.json"
        if (Test-Path -LiteralPath $configFile) {
            Copy-Item -Path $configFile -Destination (Join-Path $backupPath "opencode.json") -Force
            Write-Success "  opencode.json respaldado"
        }

        # Always backup AGENTS.md
        $agentsMd = Join-Path $configDir "AGENTS.md"
        if (Test-Path -LiteralPath $agentsMd) {
            Copy-Item -Path $agentsMd -Destination (Join-Path $backupPath "AGENTS.md") -Force
            Write-Success "  AGENTS.md respaldado"
        }

        # Backup agents directory
        $agentsDir = Join-Path $configDir "agents"
        if (Test-Path -LiteralPath $agentsDir) {
            $destAgents = Join-Path $backupPath "agents"
            $null = New-Item -ItemType Directory -Path $destAgents -Force
            Get-ChildItem -Path $agentsDir -Filter "*.md" | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination (Join-Path $destAgents $_.Name) -Force
            }
            Write-Success "  agents/ respaldados"
        }

        # Full mode: also backup plugins, commands, skills (metadata only)
        if ($Mode -eq "full") {
            $pluginsDir = Join-Path $configDir "plugins"
            if (Test-Path -LiteralPath $pluginsDir) {
                $destPlugins = Join-Path $backupPath "plugins"
                $null = New-Item -ItemType Directory -Path $destPlugins -Force
                Get-ChildItem -Path $pluginsDir -Filter "*.ts" | ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination (Join-Path $destPlugins $_.Name) -Force
                }
                Write-Success "  plugins/ respaldados"
            }

            $commandsDir = Join-Path $configDir "commands"
            if (Test-Path -LiteralPath $commandsDir) {
                $destCommands = Join-Path $backupPath "commands"
                $null = New-Item -ItemType Directory -Path $destCommands -Force
                Get-ChildItem -Path $commandsDir -Filter "*.md" | ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination (Join-Path $destCommands $_.Name) -Force
                }
                Write-Success "  commands/ respaldados"
            }

            $skillsDir = Join-Path $configDir "skills"
            if (Test-Path -LiteralPath $skillsDir) {
                $destSkills = Join-Path $backupPath "skills"
                $null = New-Item -ItemType Directory -Path $destSkills -Force
                Get-ChildItem -Path $skillsDir -Directory | ForEach-Object {
                    $skillMeta = Join-Path $_.FullName "SKILL.md"
                    if (Test-Path -LiteralPath $skillMeta) {
                        $destSkillDir = Join-Path $destSkills $_.Name
                        $null = New-Item -ItemType Directory -Path $destSkillDir -Force
                        Copy-Item -Path $skillMeta -Destination (Join-Path $destSkillDir "SKILL.md") -Force
                    }
                }
                Write-Success "  skills/ metadata respaldada"
            }
        }

        Write-Success "Backup completo en: $backupPath"
        return $backupPath
    } catch {
        Write-Warn "Error durante backup: $_"
        return $null
    }
}

# ── SYNC ENGRAM MEMORIES ─────────────────────
function Sync-EngramMemories {
    Write-Step "Sincronizando memorias de Engram..."

    $engramCmd = Get-Command "engram" -ErrorAction SilentlyContinue
    if (-not $engramCmd) {
        Write-Warn "Engram no esta instalado. No se puede sincronizar."
        return $false
    }

    $engramDb = Join-Path $HOME ".engram\engram.db"
    if (-not (Test-Path -LiteralPath $engramDb)) {
        Write-Info "No hay datos de Engram para sincronizar."
        return $false
    }

    $memoriesRepo = Join-Path $HOME "engram-memories"
    if (-not (Test-Path -LiteralPath $memoriesRepo)) {
        Write-Warn "Repo de memorias no encontrado en $memoriesRepo"
        Write-Info "Crea el repo primero desde el wizard principal."
        return $false
    }

    try {
        Push-Location $memoriesRepo
        Write-Info "Actualizando repo local..."
        $null = & git pull --rebase 2>&1

        Write-Info "Exportando memorias..."
        $exportFile = Join-Path $memoriesRepo "engram-export-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $null = & $engramCmd.Source export $exportFile 2>&1

        if (Test-Path -LiteralPath $exportFile) {
            Write-Success "Exportadas: $exportFile"
            $null = & git add -A 2>&1
            $status = & git status --porcelain
            if ($status) {
                $null = & git commit -m "sync: memorias $(Get-Date -Format 'yyyy-MM-dd HH:mm')" 2>&1
                $null = & git push 2>&1
                Write-Success "Memorias sincronizadas a GitHub."
            } else {
                Write-Info "Sin cambios nuevos en memorias."
            }
        }
        Pop-Location
        return $true
    } catch {
        Write-Warn "Error en sync de memorias: $_"
        try { Pop-Location } catch {}
        return $false
    }
}

# ── DRY-RUN / STATUS HELPERS ─────────────────
$script:IsDryRun = if ($script:IsDryRun -eq $true) { $true } else { $false }

function Write-Status {
    param([string]$Component, [string]$Status)
    $icon = switch ($Status) {
        "INSTALADO"  { "[OK]" }
        "INSTALAR"   { "[+]" }
        "OMITIDO"    { "[-]" }
        "OPCIONAL"   { "[?]" }
        "ERROR"      { "[!]" }
        default      { "[?]" }
    }
    if ($script:IsDryRun) {
        Write-Host "  $icon [$Status] $Component" -ForegroundColor $(if ($Status -eq "INSTALADO") { 'Green' } elseif ($Status -eq "INSTALAR") { 'Yellow' } else { 'Gray' })
    } else {
        Write-Host "  $icon [$Status] $Component" -ForegroundColor $(if ($Status -in @("INSTALADO","INSTALAR")) { 'Green' } else { 'Gray' })
    }
}

function Install-Component {
    param(
        [string]$Name,
        [scriptblock]$CheckBlock,
        [scriptblock]$InstallBlock,
        [switch]$Optional,
        [scriptblock]$RollbackBlock = $null
    )

    $alreadyInstalled = & $CheckBlock
    if ($alreadyInstalled) {
        Write-Status -Component $Name -Status "INSTALADO"
        return $true
    }

    if (-not $Optional) {
        Write-Status -Component $Name -Status "INSTALAR"
    } else {
        Write-Status -Component $Name -Status "OPCIONAL"
    }

    if ($script:IsDryRun) {
        return $null  # simulated
    }

    try {
        & $InstallBlock
        return $true
    } catch {
        Write-Status -Component $Name -Status "ERROR"
        Write-Warn "  $($_.Exception.Message)"
        if ($RollbackBlock) {
            Write-Warn "  Ejecutando rollback para $Name..."
            try {
                & $RollbackBlock
            } catch {
                Write-Warn "  Rollback fallo: $_"
            }
        }
        return $false
    }
}

# ── 8. BACKUP EXISTING CONFIG ────────────────
function Invoke-BackupPrompt {
    Write-Step "Paso 8/11 - Backup de config existente"
    Set-Progress -Step 7 -Status "Verificando config existente..."

    $configDir = Join-Path $HOME ".config\opencode"
    if (-not (Test-Path -LiteralPath $configDir)) {
        Write-Info "No hay config existente. Continuamos con instalacion fresh."
        $script:WizardAnswers.InstallType = "fresh"
        return
    }

    Write-Host "  Encontre una configuracion existente en: $configDir" -ForegroundColor Yellow
    $backupChoice = Read-Host "  Queres backupearla antes de continuar? (S/N, predeterminado: S)"
    $doBackup = ($backupChoice -eq "" -or $backupChoice -like "S*" -or $backupChoice -like "s*")

    if ($doBackup) {
        Write-Host "  Que tipo de backup?" -ForegroundColor White
        Write-Host "     1) Completo (config, plugins, commands, skills metadata)" -ForegroundColor Gray
        Write-Host "     2) Solo agentes" -ForegroundColor Gray
        $backupModeChoice = Read-Host "  Opcion (1-2, predeterminado: 1)"
        $backupMode = if ($backupModeChoice -eq "2") { "agents-only" } else { "full" }
        $backupPath = Backup-ExistingConfig -Mode $backupMode
        if ($backupPath) {
            Write-Success "Config respaldada en: $backupPath"
        }
        $script:WizardAnswers.InstallType = "upgrade"
    } else {
        Write-Info "Backup omitido. Instalando sobre config existente."
        $script:WizardAnswers.InstallType = "upgrade"
    }
}

# ── GENERATE OPENCODE.JSON ─────────────────────
function Generate-OpencodeJson {
    Write-Info "Generando opencode.json..."

    # Locate template
    $templateDir = Join-Path $PSScriptRoot "..\templates\configs"
    try { $templateDir = (Resolve-Path $templateDir -ErrorAction Stop).Path } catch {
        Write-Warn "No se encontro templates/configs/ — saltando generacion."
        return
    }
    $templateFile = Join-Path $templateDir "opencode.json"
    if (-not (Test-Path -LiteralPath $templateFile)) {
        Write-Warn "Template no encontrado: $templateFile"
        return
    }

    # Read template
    try {
        $config = Get-Content -Path $templateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-ErrorMsg "Error leyendo template: $_"
        return
    }

    # Git permission levels from repo management preference
    $repoMode = $script:WizardAnswers.RepoMode
    $gitCommitLevel = "ask"
    $gitPushLevel = "ask"
    switch ($repoMode) {
        "auto"   { $gitCommitLevel = "allow"; $gitPushLevel = "allow" }
        "ask"    { $gitCommitLevel = "ask";   $gitPushLevel = "ask" }
        "manual" { $gitCommitLevel = "deny";  $gitPushLevel = "deny" }
    }
    $config.permission.bash."git commit *" = $gitCommitLevel
    $config.permission.bash."git push" = $gitPushLevel
    $config.permission.bash."git push *" = $gitPushLevel

    # Agent prompts — use {file:...} references instead of inline content
    # The template should already have {file:./agents/lara-plan.md}
    # Just ensure the agents are in the right directory

    # Write output to cross-platform config dir
    $configDir = Get-OpencodeConfigDir
    if (-not (Test-Path -LiteralPath $configDir)) {
        $null = New-Item -ItemType Directory -Path $configDir -Force
    }
    $outputFile = Join-Path $configDir "opencode.json"
    $config | ConvertTo-Json -Depth 10 | Set-Content -Path $outputFile -Encoding UTF8 -Force
    Write-Success "opencode.json generado en: $outputFile"
}

# ── 9. INSTALL COMPONENTS ────────────────────
function Install-Components {
    Write-Step "Paso 8/10 - Instalacion de componentes"
    Set-Progress -Step 7 -Status "Instalando componentes..."

    if ($script:IsDryRun) {
        Write-Host "  [DRY-RUN] No se instalara nada. Reportando estado actual...`n" -ForegroundColor Cyan
    }

    $opencodeConfigDir = Get-OpencodeConfigDir
    $opencodeSkillsDir = Join-Path $opencodeConfigDir "skills"
    $opencodeAgentsDir = Join-Path $opencodeConfigDir "agents"

    # Gentle AI
    if ($script:WizardAnswers.InstallGentleAI) {
        $gaDir = Join-Path $HOME "gentle-ai"
        $null = Install-Component -Name "Gentle AI" `
            -CheckBlock { Test-Path -LiteralPath $gaDir } `
            -InstallBlock {
                $null = & git clone "https://github.com/Gentleman-Programming/gentle-ai.git" $gaDir 2>&1
                if ($LASTEXITCODE -eq 0) { Write-Success "Gentle AI clonado en: $gaDir" }
                else { throw "Error clonando Gentle AI" }
                # Try scripts/install.ps1 first (official path), fallback to root
                $gaInstaller = Join-Path $gaDir "scripts\install.ps1"
                if (-not (Test-Path -LiteralPath $gaInstaller)) {
                    $gaInstaller = Join-Path $gaDir "install.ps1"
                }
                if (Test-Path -LiteralPath $gaInstaller) {
                    Write-Info "Ejecutando instalador de Gentle AI..."
                    $null = & $gaInstaller 2>&1
                    Write-Success "Instalador ejecutado."
                } else {
                    Write-Warn "Installer script not found. Try: scoop bucket add gentleman https://github.com/Gentleman-Programming/scoop-bucket"
                    Write-Warn "Then: scoop install gentle-ai"
                }
            }
    } else {
        Write-Status -Component "Gentle AI" -Status "OMITIDO"
    }

    # Gentleman Skills
    if ($script:WizardAnswers.InstallGentlemanSkills) {
        $skillsRepo = Join-Path $opencodeSkillsDir "Gentleman-Skills"
        $null = Install-Component -Name "Gentleman Skills" `
            -CheckBlock { Test-Path -LiteralPath $skillsRepo } `
            -InstallBlock {
                if (-not (Test-Path -LiteralPath $opencodeSkillsDir)) {
                    $null = New-Item -ItemType Directory -Path $opencodeSkillsDir -Force
                }
                $null = & git clone "https://github.com/Gentleman-Programming/Gentleman-Skills.git" $skillsRepo 2>&1
                if ($LASTEXITCODE -eq 0) { Write-Success "Gentleman Skills clonado" }
                else { throw "Error clonando Gentleman Skills" }
            }
    } else {
        Write-Status -Component "Gentleman Skills" -Status "OMITIDO"
    }

    # Engram
    $null = Install-Component -Name "Engram (memoria persistente)" `
        -CheckBlock { Get-Command "engram" -ErrorAction SilentlyContinue } `
        -InstallBlock {
            $engramOk = $false

            # Priority 1: Download from GitHub Releases (zero deps — just PowerShell)
            Write-Info "Downloading Engram from GitHub Releases..."
            try {
                $releasesUrl = "https://api.github.com/repos/Gentleman-Programming/engram/releases"
                $releases = Invoke-RestMethod -Uri $releasesUrl -ErrorAction Stop
                $releaseInfo = $releases | Where-Object { $_.tag_name -like "v*" } | Select-Object -First 1
                if (-not $releaseInfo) { throw "No se encontraron releases validos de Engram." }
                $tag = $releaseInfo.tag_name
                $version = $tag.TrimStart('v')

                # Detect architecture
                $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { "arm64" } else { "amd64" }
                $archiveName = "engram_${version}_windows_${arch}.zip"

                $dlUrl = "https://github.com/Gentleman-Programming/engram/releases/download/${tag}/${archiveName}"
                $tmpDir = Join-Path $env:TEMP "engram-install-$([System.IO.Path]::GetRandomFileName())"
                $null = New-Item -ItemType Directory -Path $tmpDir -Force
                $zipPath = Join-Path $tmpDir $archiveName

                Write-Info "Downloading $archiveName ..."
                Invoke-WebRequest -Uri $dlUrl -OutFile $zipPath -ErrorAction Stop

                # Extract
                Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
                $installBinDir = Join-Path $HOME "bin"
                if (-not (Test-Path -LiteralPath $installBinDir)) {
                    $null = New-Item -ItemType Directory -Path $installBinDir -Force
                }
                Copy-Item -Path (Join-Path $tmpDir "engram.exe") -Destination (Join-Path $installBinDir "engram.exe") -Force
                Write-Success "Engram installed to: $(Join-Path $installBinDir 'engram.exe')"

                # Cleanup
                Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

                # Check if install dir is in PATH
                $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
                if ($userPath -notlike "*$installBinDir*") {
                    Write-Warn "Add $installBinDir to your PATH to use 'engram' from anywhere."
                }
                $engramOk = $true
            } catch {
                Write-Warn "Binary download failed: $_"
            }

            # Priority 2: go install (if Go toolchain is available)
            if (-not $engramOk) {
                $goCmd = Get-Command "go" -ErrorAction SilentlyContinue
                if ($goCmd) {
                    Write-Info "Falling back to go install..."
                    $null = & go install github.com/Gentleman-Programming/engram/cmd/engram@latest 2>&1
                    $reCheck = Get-Command "engram" -ErrorAction SilentlyContinue
                    if ($reCheck) {
                        Write-Success "Engram installed via go install."
                        $engramOk = $true
                    } else {
                        $gopath = & go env GOPATH 2>$null
                        $gobin = Join-Path $gopath "bin\engram.exe"
                        if (Test-Path -LiteralPath $gobin) {
                            Write-Success "Engram installed at: $gobin"
                            Write-Warn "Add $gopath\bin to your PATH if not already there."
                            $engramOk = $true
                        }
                    }
                }
            }

            if (-not $engramOk) {
                throw "Could not install Engram. Download from: https://github.com/Gentleman-Programming/engram/releases"
            }
        }

    # VSCode
    if ($script:WizardAnswers.InstallVSCode) {
        $null = Install-Component -Name "VSCode" -Optional `
            -CheckBlock { Get-Command "code" -ErrorAction SilentlyContinue } `
            -InstallBlock {
                $winget = Get-Command "winget" -ErrorAction SilentlyContinue
                if ($winget) {
                    $null = & winget install "Microsoft.VisualStudioCode" --accept-source-agreements --accept-package-agreements 2>&1
                    # Refresh PATH env var to detect new installation without restart
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                    $reCheck = Get-Command "code" -ErrorAction SilentlyContinue
                    if (-not $reCheck) { throw "VSCode instalado pero 'code' no esta en PATH. Por favor reinicia la consola." }
                } else {
                    throw "winget no disponible. Descarga desde: https://code.visualstudio.com/"
                }
            }
    } else {
        Write-Status -Component "VSCode" -Status "OMITIDO"
    }

    # Create agents from templates
    $restoreAgents = $script:WizardAnswers.RestoreAgents
    if ($restoreAgents -eq "keep") {
        Write-Info "Conservando agentes personalizados existentes (no se actualizan templates)."
    } else {
        Write-Info "Creando agentes Lara-Plan y Lara-VIP..."
        if (-not (Test-Path -LiteralPath $opencodeAgentsDir)) {
            $null = New-Item -ItemType Directory -Path $opencodeAgentsDir -Force
        }
        $templatesDir = Join-Path $PSScriptRoot "..\templates\agents"
        try { $templatesDir = (Resolve-Path $templatesDir -ErrorAction Stop).Path } catch {
            Write-Warn "No se encontro templates/agents"
        }

        $agentTemplates = @("lara-plan.md", "lara-vip.md")
        foreach ($agent in $agentTemplates) {
            $templatePath = Join-Path $templatesDir $agent
            $outputPath = Join-Path $opencodeAgentsDir $agent
            if (-not (Test-Path -LiteralPath $templatePath)) {
                Write-Warn "Template no encontrado: $templatePath"
                continue
            }
            try {
                $content = Get-Content -Path $templatePath -Raw -Encoding UTF8
                $content = $content -replace [regex]::Escape("{{PRONOUN}}"), $script:WizardAnswers.Pronoun
                $content = $content -replace [regex]::Escape("{{SKILL_LEVEL}}"), $script:WizardAnswers.SkillLevel
                $content = $content -replace [regex]::Escape("{{ASSISTANCE_MODE}}"), $script:WizardAnswers.AssistanceMode
                $content = $content -replace [regex]::Escape("{{DISCRETION}}"), $script:WizardAnswers.Discretion
                $content = $content -replace [regex]::Escape("{{STYLE}}"), $script:WizardAnswers.Style
                $content = $content -replace [regex]::Escape("{skill_level_description}"), $script:WizardAnswers.SkillLevelDesc
                $content | Set-Content -Path $outputPath -Encoding UTF8 -Force
                Write-Success "Agente creado: $outputPath"
            } catch {
                Write-ErrorMsg ("Error creando agente $($agent): $_")
            }
        }
    }

    # GitHub repos
    $ghUser = $script:WizardAnswers.GitHubUser
    if (-not [string]::IsNullOrWhiteSpace($ghUser)) {
        $reposToCheck = @("engram-memories", "opencode-config")
        foreach ($repoName in $reposToCheck) {
            Write-Info "Verificando repo: $ghUser/$repoName..."
            $oldEAP = $ErrorActionPreference
            $ErrorActionPreference = "SilentlyContinue"
            $null = & gh repo view "$ghUser/$repoName" --json name 2>$null
            $repoExists = ($LASTEXITCODE -eq 0)
            $ErrorActionPreference = $oldEAP
            if ($repoExists) {
                Write-Success "Repo $repoName ya existe."
            } else {
                Write-Info "Creando repo privado: $repoName..."
                try {
                    $oldEAP = $ErrorActionPreference
                    $ErrorActionPreference = "SilentlyContinue"
                    $null = & gh repo create "$repoName" --private --clone 2>$null
                    $createSuccess = ($LASTEXITCODE -eq 0)
                    $ErrorActionPreference = $oldEAP
                    if ($createSuccess) { Write-Success "Repo $repoName creado." }
                    else { Write-ErrorMsg "Error creando repo $repoName."; continue }
                } catch { Write-ErrorMsg "Error creando repo $($repoName): $_"; continue }
            }
            $localRepo = Join-Path $HOME $repoName
            if (-not (Test-Path -LiteralPath $localRepo)) {
                try {
                    $oldEAP = $ErrorActionPreference
                    $ErrorActionPreference = "SilentlyContinue"
                    $null = & gh repo clone "$ghUser/$repoName" 2>$null
                    $cloneSuccess = ($LASTEXITCODE -eq 0)
                    $ErrorActionPreference = $oldEAP
                    if ($cloneSuccess) {
                        Write-Success "Repo clonado en: $localRepo"
                        # Copy engram-memories .gitignore template if present
                        if ($repoName -eq "engram-memories") {
                            $gitignoreTemplate = Join-Path $PSScriptRoot "..\templates\engram\gitignore"
                            try { $gitignoreTemplate = (Resolve-Path $gitignoreTemplate -ErrorAction Stop).Path } catch { $gitignoreTemplate = $null }
                            $gitignoreDest = Join-Path $localRepo ".gitignore"
                            if ($gitignoreTemplate -and (Test-Path -LiteralPath $gitignoreTemplate) -and -not (Test-Path -LiteralPath $gitignoreDest)) {
                                Copy-Item -Path $gitignoreTemplate -Destination $gitignoreDest -Force
                                Push-Location $localRepo
                                $null = & git add .gitignore 2>&1
                                $null = & git commit -m "init: add .gitignore for sync chunks" 2>&1
                                $null = & git push 2>&1
                                Pop-Location
                                Write-Success ".gitignore template applied"
                            }
                        }
                    }
                    Pop-Location
                } catch { Write-Warn "Error clonando $repoName"; try { Pop-Location } catch {} }
            } else { Write-Info "Repo ya clonado en: $localRepo" }
        }
    } else {
        Write-Warn "Usuario de GitHub no disponible. Saltando creacion de repos."
    }

    # Generate opencode.json configuration
    Generate-OpencodeJson

    # First backup
    $configRepoDir = Join-Path $HOME "opencode-config"
    if (Test-Path -LiteralPath $configRepoDir) {
        Write-Info "Ejecutando primer backup..."
        try {
            Push-Location $configRepoDir
            $opencodeConfigDir = Get-OpencodeConfigDir
            $opencodeConfig = Join-Path $opencodeConfigDir "opencode.json"
            $agentsMd = Join-Path $opencodeConfigDir "AGENTS.md"
            $agentsDir = Join-Path $opencodeConfigDir "agents"
            if (Test-Path -LiteralPath $opencodeConfig) {
                Copy-Item -Path $opencodeConfig -Destination (Join-Path $configRepoDir "opencode.json") -Force
            }
            if (Test-Path -LiteralPath $agentsMd) {
                Copy-Item -Path $agentsMd -Destination (Join-Path $configRepoDir "AGENTS.md") -Force
            }
            if (Test-Path -LiteralPath $agentsDir) {
                $destAgents = Join-Path $configRepoDir "agents"
                if (-not (Test-Path -LiteralPath $destAgents)) {
                    $null = New-Item -ItemType Directory -Path $destAgents -Force
                }
                Get-ChildItem -Path $agentsDir -Filter "*.md" | ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination (Join-Path $destAgents $_.Name) -Force
                }
            }
            $null = & git add -A 2>&1
            $status = & git status --porcelain
            if ($status) {
                $dateStr = Get-Date -Format "yyyy-MM-dd HH:mm"
                $null = & git commit -m "backup: config inicial $dateStr" 2>&1
                $null = & git push 2>&1
                Write-Success "Primer backup subido."
            } else { Write-Info "Sin cambios para backup inicial." }
            Pop-Location
        } catch {
            Write-Warn "Error en primer backup: $_"
            try { Pop-Location } catch {} }
    }

    # ── Gentle AI post-install ────────────────────────────────
    if ($script:WizardAnswers.InstallGentleAI) {
        $gaBin = Get-Command "gentle-ai" -ErrorAction SilentlyContinue
        if ($gaBin) {
            Write-Step "Registrando Gentle AI en opencode..."
            try {
                $null = & gentle-ai install --agents opencode --scope global --sdd-mode multi 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Gentle AI integrado con opencode (rosa, SDD, skills)"
                } else {
                    Write-Warn "gentle-ai install reporto exit code: $LASTEXITCODE"
                }
            } catch {
                Write-Warn "gentle-ai install fallo: $_"
                Write-Info "Podes ejecutarlo manualmente: gentle-ai install --agents opencode --scope global --sdd-mode multi"
            }
        } else {
            Write-Warn "gentle-ai binario no encontrado en PATH. Ejecuta el install script primero."
        }
    }

    # ── Engram serve (background) ─────────────────────────────
    $engramBin = Get-Command "engram" -ErrorAction SilentlyContinue
    if ($engramBin) {
        $engramServe = Get-Process -Name "engram" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*serve*" }
        if (-not $engramServe) {
            Write-Info "Iniciando engram serve en segundo plano..."
            try {
                $null = Start-Process -FilePath $engramBin.Source -ArgumentList "serve" -WindowStyle Hidden -PassThru
                Write-Success "engram serve iniciado (PID: $($engramServe.Id))"
            } catch {
                Write-Warn "No se pudo iniciar engram serve: $_"
            }
        } else {
            Write-Success "engram serve ya esta corriendo (PID: $($engramServe.Id))"
        }
    }
}

# ── 9. SETUP SYNC ────────────────────────────
function Setup-Sync {
    Write-Step "Paso 9/10 - Sincronizacion"
    Set-Progress -Step 8 -Status "Configurando sincronizacion..."

    $syncDir = Join-Path $HOME "lara-sync"
    if (-not (Test-Path -LiteralPath $syncDir)) {
        $null = New-Item -ItemType Directory -Path $syncDir -Force
    }

    $syncScript = Join-Path $PSScriptRoot "..\scripts\sync-memories.ps1"
    if (Test-Path -LiteralPath $syncScript) {
        $destScript = Join-Path $syncDir "sync-memories.ps1"
        try {
            Copy-Item -Path $syncScript -Destination $destScript -Force
            Write-Success "Script copiado a: $destScript"
        } catch { Write-ErrorMsg "Error copiando: $_" }
    } else {
        Write-Warn "Script no encontrado: $syncScript"
    }

    Write-Info "Creando tarea programada Lara-MemorySync..."
    try {
        $taskName = "Lara-MemorySync"
        $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existing) {
            $null = Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$syncDir\sync-memories.ps1`""
        $trigger = New-ScheduledTaskTrigger -Daily -At "09:00" -RepetitionInterval (New-TimeSpan -Minutes 30)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        $null = Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force
        Write-Success "Tarea programada creada: $taskName"
    } catch {
        Write-Warn "No se pudo crear la tarea programada: $_"
    }

    Write-Info "Ejecutando sync inicial..."
    try {
        $null = & "$syncDir\sync-memories.ps1" 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Success "Sync inicial exitosa." }
        else { Write-Warn "Sync inicial con warnings (exit code: $LASTEXITCODE)." }
    } catch { Write-Warn "Error en sync inicial: $_" }
}

# ── 11. SHOW SUMMARY ─────────────────────────
function Show-Summary {
    Write-Step "Paso 11/11 - Resumen final"
    Set-Progress -Step 10 -Status "Mostrando resumen..."

    Write-Host "`n"
    Write-Host "+---------------------------------------------+" -ForegroundColor Cyan
    Write-Host "|    LARA DIARIES - RESUMEN DE INSTALACION    |" -ForegroundColor Cyan
    Write-Host "+---------------------------------------------+" -ForegroundColor Cyan

    Write-Host "`n  [Perfil]" -ForegroundColor Magenta
    Write-Host "  Pronombres : $($script:UserProfile.Pronoun)" -ForegroundColor White
    Write-Host "  Nivel      : $($script:UserProfile.SkillLevel)" -ForegroundColor White
    Write-Host "  Asistencia : $($script:UserProfile.AssistanceMode)" -ForegroundColor White
    Write-Host "  Mision     : $($script:UserProfile.Mission)" -ForegroundColor White
    Write-Host "  Discrecion : $($script:UserProfile.Discretion)" -ForegroundColor White

    Write-Host "`n  [Componentes]" -ForegroundColor Magenta
    $c1 = $script:WizardAnswers.InstallGentleAI
    $c2 = $script:WizardAnswers.InstallGentlemanSkills
    $c3 = $script:WizardAnswers.UseDesignDoc

    if ($c1) { Write-Host "  [x] Gentle AI" -ForegroundColor Green }
    else { Write-Host "  [ ] Gentle AI" -ForegroundColor Gray }

    if ($c2) { Write-Host "  [x] Gentleman Skills" -ForegroundColor Green }
    else { Write-Host "  [ ] Gentleman Skills" -ForegroundColor Gray }

    Write-Host "  [x] Engram (memoria)" -ForegroundColor Green
    Write-Host "  [x] Lara-Plan (agente)" -ForegroundColor Green
    Write-Host "  [x] Lara-VIP (agente)" -ForegroundColor Green
    Write-Host "  [x] engram-memories repo" -ForegroundColor Green
    Write-Host "  [x] opencode-config repo" -ForegroundColor Green
    Write-Host "  [x] Sync programado" -ForegroundColor Green

    $vscode = $script:WizardAnswers.InstallVSCode
    if ($vscode) { Write-Host "  [x] VSCode" -ForegroundColor Green }
    else { Write-Host "  [ ] VSCode" -ForegroundColor Gray }

    if ($c3) { Write-Host "  [x] design.md" -ForegroundColor Green }
    else { Write-Host "  [ ] design.md" -ForegroundColor Gray }

    $installType = $script:WizardAnswers.InstallType
    if ($installType -eq "upgrade") {
        Write-Host "`n  [Backup]" -ForegroundColor Magenta
        Write-Host "  [x] Config existente respaldada antes de instalar" -ForegroundColor Green
    }

    Write-Host "`n  [Directorios]" -ForegroundColor Magenta
    Write-Host "  Proyectos : $($script:WizardAnswers.DevDir)" -ForegroundColor White
    Write-Host "  Agentes   : $(Join-Path (Get-OpencodeConfigDir) 'agents')" -ForegroundColor White
    Write-Host "  Sync      : $(Join-Path $HOME 'lara-sync\sync-memories.ps1')" -ForegroundColor White
    Write-Host "  Memoria   : $(Join-Path $env:LOCALAPPDATA 'engram')" -ForegroundColor White

    Write-Host "`n"
    Write-Host "+---------------------------------------------+" -ForegroundColor Green
    Write-Host "|         LARA DIARIES ESTA LISTA!             |" -ForegroundColor Green
    Write-Host "+---------------------------------------------+" -ForegroundColor Green
    Write-Host "| Ya podes abrir opencode y empezar a usar     |" -ForegroundColor Green
    Write-Host "| Lara. Tus agentes estan configurados y la    |" -ForegroundColor Green
    Write-Host "| memoria sincroniza cada 30 minutos.          |" -ForegroundColor Green
    Write-Host "+---------------------------------------------+" -ForegroundColor Green
    Write-Host "`n"
}

# ── 12. POST-INSTALL VERIFICATION ────────────
function Invoke-PostInstallVerification {
    Write-Step "Paso 12/12 - Verificacion post-instalacion"
    Set-Progress -Step 11 -Status "Verificando instalacion..."

    Write-Host "`n  =============================================" -ForegroundColor Yellow
    Write-Host "  |   VERIFICACION POST-INSTALACION            |" -ForegroundColor Yellow
    Write-Host "  =============================================" -ForegroundColor Yellow
    Write-Host "`n  Para que todo funcione correctamente, necesito" -ForegroundColor White
    Write-Host "  que cierres esta terminal y abras una NUEVA." -ForegroundColor White
    Write-Host "  (Esto actualiza el PATH con los binarios nuevos)" -ForegroundColor Gray
    Write-Host "`n  Despues de reiniciar, ejecuta este comando:" -ForegroundColor Cyan
    Write-Host "    lara-diaries doctor" -ForegroundColor Green
    Write-Host "`n  Tambien quiero repreguntarte algunas cosas" -ForegroundColor White
    Write-Host "  para ajustar bien a tu perfil.`n" -ForegroundColor White

    # ── Re-preguntas de reconocimiento ─────
    $reask = Read-Host "  Queres configurar tus preferencias ahora? (S/N, predeterminado: S)"
    if ($reask -eq "" -or $reask -like "S*" -or $reask -like "s*") {
        # Re-ask pronouns
        Write-Host "`n  1. Que pronombres usas?" -ForegroundColor White
        Write-Host "     1) she/her" -ForegroundColor Gray
        Write-Host "     2) they/them" -ForegroundColor Gray
        Write-Host "     3) he/him" -ForegroundColor Gray
        Write-Host "     4) it/its" -ForegroundColor Gray
        Write-Host "     5) other" -ForegroundColor Gray
        $choice = Read-Host "  Opcion (1-5, predeterminado: 2)"
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "2" }
        switch ($choice.Trim()) {
            "1" { $script:WizardAnswers.Pronoun = "she/her" }
            "2" { $script:WizardAnswers.Pronoun = "they/them" }
            "3" { $script:WizardAnswers.Pronoun = "he/him" }
            "4" { $script:WizardAnswers.Pronoun = "it/its" }
            "5" {
                $custom = Read-Host "    Decime cual"
                if ([string]::IsNullOrWhiteSpace($custom)) { $custom = "they/them" }
                $script:WizardAnswers.Pronoun = $custom.Trim()
            }
            default { $script:WizardAnswers.Pronoun = "they/them" }
        }
        Write-Success "Pronombres: $($script:WizardAnswers.Pronoun)"

        # Re-ask skill level
        Write-Host "`n  2. Cuanto sabes de informatica?" -ForegroundColor White
        Write-Host "     1) full-fearless" -ForegroundColor Gray
        Write-Host "     2) me-defiendo" -ForegroundColor Gray
        Write-Host "     3) me-invito-un-amigo" -ForegroundColor Gray
        $choice2 = Read-Host "  Opcion (1-3, predeterminado: 2)"
        if ([string]::IsNullOrWhiteSpace($choice2)) { $choice2 = "2" }
        switch ($choice2.Trim()) {
            "1" { $script:WizardAnswers.SkillLevel = "full-fearless" }
            "2" { $script:WizardAnswers.SkillLevel = "me-defiendo" }
            "3" { $script:WizardAnswers.SkillLevel = "me-invito-un-amigo" }
            default { $script:WizardAnswers.SkillLevel = "me-defiendo" }
        }
        Write-Success "Nivel: $($script:WizardAnswers.SkillLevel)"
        $desc = $script:WizardAnswers.SkillLevel
        if ($desc -eq "full-fearless") { $script:WizardAnswers.SkillLevelDesc = "Assume competence, focus on trade-offs" }
        elseif ($desc -eq "me-defiendo") { $script:WizardAnswers.SkillLevelDesc = "Explain the why behind each decision" }
        else { $script:WizardAnswers.SkillLevelDesc = "Start from basics, be gentle" }

        # Re-ask assistance mode
        Write-Host "`n  3. Cuanta asistencia queres?" -ForegroundColor White
        Write-Host "     1) full (explica todo)" -ForegroundColor Gray
        Write-Host "     2) medium (resume y chequea)" -ForegroundColor Gray
        Write-Host "     3) minimal (confianza)" -ForegroundColor Gray
        $choice3 = Read-Host "  Opcion (1-3, predeterminado: 2)"
        if ([string]::IsNullOrWhiteSpace($choice3)) { $choice3 = "2" }
        switch ($choice3.Trim()) {
            "1" { $script:WizardAnswers.AssistanceMode = "full" }
            "2" { $script:WizardAnswers.AssistanceMode = "medium" }
            "3" { $script:WizardAnswers.AssistanceMode = "minimal" }
            default { $script:WizardAnswers.AssistanceMode = "medium" }
        }
        Write-Success "Asistencia: $($script:WizardAnswers.AssistanceMode)"

        # Save updated profile
        $script:UserProfile.Pronoun = $script:WizardAnswers.Pronoun
        $script:UserProfile.SkillLevel = $script:WizardAnswers.SkillLevel
        $script:UserProfile.SkillLevelDesc = $script:WizardAnswers.SkillLevelDesc
        $script:UserProfile.AssistanceMode = $script:WizardAnswers.AssistanceMode
        Save-UserProfile

        # Re-generate agent files with updated preferences
        Write-Host "`n  Actualizando agentes con tus preferencias..." -ForegroundColor Cyan
        $configDir = Get-OpencodeConfigDir
        $agentsDir = Join-Path $configDir "agents"
        if (Test-Path -LiteralPath $agentsDir) {
            $templatesDir = Join-Path $PSScriptRoot "..\templates\agents"
            try { $templatesDir = (Resolve-Path $templatesDir -ErrorAction Stop).Path } catch { }
            $agentTemplates = @("lara-plan.md", "lara-vip.md")
            foreach ($agent in $agentTemplates) {
                $templatePath = Join-Path $templatesDir $agent
                $outputPath = Join-Path $agentsDir $agent
                if (-not (Test-Path -LiteralPath $templatePath)) {
                    Write-Warn "Template no encontrado: $templatePath"
                    continue
                }
                try {
                    $content = Get-Content -Path $templatePath -Raw -Encoding UTF8
                    $content = $content -replace [regex]::Escape("{{PRONOUN}}"), $script:WizardAnswers.Pronoun
                    $content = $content -replace [regex]::Escape("{{SKILL_LEVEL}}"), $script:WizardAnswers.SkillLevel
                    $content = $content -replace [regex]::Escape("{{ASSISTANCE_MODE}}"), $script:WizardAnswers.AssistanceMode
                    $content = $content -replace [regex]::Escape("{{DISCRETION}}"), $script:WizardAnswers.Discretion
                    $content = $content -replace [regex]::Escape("{{STYLE}}"), $script:WizardAnswers.Style
                    $content = $content -replace [regex]::Escape("{skill_level_description}"), $script:WizardAnswers.SkillLevelDesc
                    $content | Set-Content -Path $outputPath -Encoding UTF8 -Force
                    Write-Success "Agente actualizado: $outputPath"
                } catch {
                    Write-Warn "Error actualizando agente $($agent): $_"
                }
            }
        }
        Write-Success "Preferencias actualizadas."
    } else {
        Write-Info "Podes cambiar tus preferencias despues editando los templates de agentes."
    }

    # ── Run health checks ─────────────────────
    Write-Host "`n  Ejecutando chequeos de salud..." -ForegroundColor Cyan

    $checks = @(
        @{Name = "opencode"; Command = { Get-Command "opencode" -ErrorAction SilentlyContinue } }
        @{Name = "gentle-ai"; Command = { Get-Command "gentle-ai" -ErrorAction SilentlyContinue } }
        @{Name = "engram"; Command = { Get-Command "engram" -ErrorAction SilentlyContinue } }
        @{Name = "gh (GitHub CLI)"; Command = { Get-Command "gh" -ErrorAction SilentlyContinue } }
        @{Name = "git"; Command = { Get-Command "git" -ErrorAction SilentlyContinue } }
    )

    $allOk = $true
    foreach ($check in $checks) {
        $found = & $check.Command
        if ($found) {
            Write-Host "    [OK] $($check.Name)" -ForegroundColor Green
        } else {
            Write-Host "    [..] $($check.Name) — se vera al reiniciar terminal" -ForegroundColor Yellow
            $allOk = $false
        }
    }

    # ── Final message ─────────────────────────
    Write-Host "`n"
    Write-Host "+---------------------------------------------+" -ForegroundColor Green
    Write-Host "|         LARA DIARIES — INSTALACION COMPLETA  |" -ForegroundColor Green
    Write-Host "+---------------------------------------------+" -ForegroundColor Green
    Write-Host "|                                            |" -ForegroundColor Green
    Write-Host "|  1. Cerra esta terminal                     |" -ForegroundColor White
    Write-Host "|  2. Abri una NUEVA terminal                 |" -ForegroundColor White
    Write-Host "|  3. Ejecuta: opencode                       |" -ForegroundColor Green
    Write-Host "|     (vas a ver la ROSA de gentle-ai)        |" -ForegroundColor White
    Write-Host "|                                            |" -ForegroundColor Green
    Write-Host "|  Verificacion rapida:                       |" -ForegroundColor White
    Write-Host "|    lara-diaries doctor                      |" -ForegroundColor Green
    Write-Host "|                                            |" -ForegroundColor Green
    Write-Host "+---------------------------------------------+" -ForegroundColor Green
    Write-Host "`n"
}

# ── NON-INTERACTIVE WIZARD ──────────────────
function Start-NonInteractiveWizard {
    param([string]$ConfigJson)

    Write-Host "  [NON-INTERACTIVE] Procesando configuracion..." -ForegroundColor Cyan

    # Parse JSON config
    try {
        $config = $ConfigJson | ConvertFrom-Json
    } catch {
        Write-ErrorMsg "Error parseando JSON: $_"
        Write-Host "  JSON recibido: $ConfigJson" -ForegroundColor Gray
        throw "Invalid JSON config"
    }

    # Validate GitHub auth (no interactive login)
    $gh = Get-Command "gh" -ErrorAction SilentlyContinue
    if (-not $gh) { throw "gh CLI not found" }
    $null = & gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "GitHub no autenticado. El usuario debe hacer 'gh auth login' primero."
        throw "GitHub auth required"
    }
    $ghUser = & gh api user --jq .login 2>$null
    if (-not $ghUser) { throw "Could not get GitHub username" }

    # Resolve dev directory
    $devDir = if ($config.dev_dir) { $config.dev_dir } else { Join-Path $HOME "Documents\Develops" }
    if (-not (Test-Path -LiteralPath $devDir)) {
        $null = New-Item -ItemType Directory -Path $devDir -Force
    }

    # Map mission to discretion
    $discretion = switch ($config.mission) {
        "personal-important" { "high-caution" }
        "work"               { "moderate" }
        "vm"                 { "relaxed" }
        "lab-raspberry"      { "very-relaxed" }
        default              { "moderate" }
    }

    # Detect install type and backup config if needed
    $installType = if ($config.install_type) { $config.install_type } else { "fresh" }
    $backupExisting = if ($config.backup_existing) { $config.backup_existing } else { $false }
    $syncMemories = if ($config.sync_memories -eq $true) { $true } else { $false }
    $restoreAgents = if ($config.restore_agents) { $config.restore_agents } else { "update" }

    # Backup existing config before install (if upgrade)
    if ($installType -ne "fresh" -and $backupExisting -ne $false) {
        Write-Host "`n  [PRE-FLIGHT] Backupeando config existente..." -ForegroundColor Cyan
        $backupPath = Backup-ExistingConfig -Mode $backupExisting
        if ($backupPath) {
            Write-Success "Config respaldada en: $backupPath"
        }
    } else {
        Write-Info "Instalacion fresh o backup omitido por el usuario."
    }

    # Sync Engram memories if requested
    if ($syncMemories) {
        Write-Host "`n  [PRE-FLIGHT] Sincronizando memorias de Engram..." -ForegroundColor Cyan
        $null = Sync-EngramMemories
    }

    # Set up WizardAnswers
    $script:WizardAnswers = @{
        GitHubUser             = $ghUser
        DevDir                 = $devDir
        Pronoun                = if ($config.pronoun) { $config.pronoun } else { "they/them" }
        SkillLevel             = if ($config.skill_level) { $config.skill_level } else { "me-defiendo" }
        SkillLevelDesc         = switch ($config.skill_level) {
            "full-fearless"    { "Assume competence, focus on trade-offs" }
            "me-defiendo"      { "Explain the why behind each decision" }
            "me-invito-un-amigo" { "Start from basics, be gentle" }
            default            { "Explain the why behind each decision" }
        }
        AssistanceMode         = if ($config.assistance_mode) { $config.assistance_mode } else { "medium" }
        RepoMode               = if ($config.repo_mode) { $config.repo_mode } else { "auto" }
        UseDesignDoc           = if ($config.use_design_doc -eq $false) { $false } else { $true }
        Style                  = if ($config.style) { $config.style } else { "clean-ui" }
        Mission                = if ($config.mission) { $config.mission } else { "personal-important" }
        Discretion             = $discretion
        InstallGentleAI        = if ($config.install_gentle_ai -eq $false) { $false } else { $true }
        InstallGentlemanSkills = if ($config.install_gentleman_skills -eq $false) { $false } else { $true }
        InstallVSCode          = if ($config.install_vscode -eq $false) { $false } else { $true }
        RestoreAgents          = $restoreAgents
        InstallType            = $installType
    }

    $script:UserProfile = @{
        Pronoun         = $script:WizardAnswers.Pronoun
        SkillLevel      = $script:WizardAnswers.SkillLevel
        SkillLevelDesc  = $script:WizardAnswers.SkillLevelDesc
        AssistanceMode  = $script:WizardAnswers.AssistanceMode
        Mission         = $script:WizardAnswers.Mission
        Discretion      = $script:WizardAnswers.Discretion
    }

    # Run install steps
    Write-Host "`n  [1/5] Instalando componentes..." -ForegroundColor Cyan
    Install-Components

    Write-Host "`n  [2/5] Configurando sincronizacion..." -ForegroundColor Cyan
    Setup-Sync

    Write-Host "`n  [3/5] Verificando instalacion..." -ForegroundColor Cyan
    Invoke-VerifyInstallation

    Write-Host "`n  [4/5] Configurando perfil de Lara..." -ForegroundColor Cyan
    if (Test-UserProfileExists) {
        Write-Host "  [SKIP] Perfil ya existe — saltando personalizacion." -ForegroundColor Yellow
    } else {
        Save-UserProfile
    }

    Write-Host "`n  [5/5] Mostrando resumen..." -ForegroundColor Cyan
    Show-Summary
}

# ── MAIN WIZARD ORCHESTRATOR ──────────────────
function Start-Wizard {
    param([string[]]$CompletedSteps = @())
    Write-Host "`n"
    Write-Host "+---------------------------------------------+" -ForegroundColor Magenta
    if ($script:IsDryRun) {
        Write-Host "|     MODO SIMULACION (DRY-RUN)              |" -ForegroundColor Yellow
        Write-Host "|     Usando valores predeterminados         |" -ForegroundColor Yellow
    } else {
        Write-Host "|        ASISTENTE DE CONFIGURACION            |" -ForegroundColor Magenta
        Write-Host "|     Te voy a hacer algunas preguntas         |" -ForegroundColor Magenta
    }
    Write-Host "+---------------------------------------------+" -ForegroundColor Magenta
    if (-not $script:IsDryRun) {
        Write-Host "  Responde con el numero de opcion." -ForegroundColor Gray
        Write-Host "  Los valores predeterminados estan entre parentesis.`n" -ForegroundColor Gray
    }

    function Step-Skipped { param([string]$Name) return $Name -in $CompletedSteps }
    function Run-Step {
        param([string]$Name, [scriptblock]$Action)
        if (Step-Skipped -Name $Name) {
            Write-Host "  [SKIP] $Name ya completado." -ForegroundColor DarkYellow
            return
        }
        $script:CurrentStep = $Name
        Write-StepState -StepName $Name -Status "running"
        & $Action
        Write-StepState -StepName $Name -Status "success"
    }

    try {
        $script:CurrentStep = $null

        Run-Step -Name "github_login" -Action {
            Set-Progress -Step 0 -Status "Login GitHub..."
            Invoke-GitHubLogin
        }
        Run-Step -Name "dev_directory" -Action {
            Set-Progress -Step 1 -Status "Directorio..."
            Invoke-DevDirectoryPrompt
        }
        Run-Step -Name "gentle_ai_prompt" -Action {
            Set-Progress -Step 2 -Status "Gentle AI..."
            Invoke-GentleAIPrompt
        }
        Run-Step -Name "backup" -Action {
            Set-Progress -Step 3 -Status "Backup..."
            Invoke-BackupPrompt
        }
        Run-Step -Name "install_components" -Action {
            Set-Progress -Step 4 -Status "Instalando..."
            Install-Components
        }
        Run-Step -Name "setup_sync" -Action {
            Set-Progress -Step 5 -Status "Sincronizacion..."
            Setup-Sync
        }
        Run-Step -Name "verify_install" -Action {
            Set-Progress -Step 6 -Status "Verificacion..."
            Invoke-VerifyInstallation
        }
        Run-Step -Name "config_questions" -Action {
            if (Test-UserProfileExists) {
                Write-Host "  [SKIP] Perfil ya existe — saltando configuracion." -ForegroundColor DarkYellow
            } else {
                Set-Progress -Step 7 -Status "Repos..."
                Invoke-RepoManagementPrompt
                Set-Progress -Step 8 -Status "Disenio..."
                Invoke-DesignOrientationPrompt
                Set-Progress -Step 9 -Status "Mision..."
                Invoke-MissionPrompt
                Set-Progress -Step 10 -Status "Preferencias..."
                Invoke-RecognitionQuestions
                Save-UserProfile
            }
        }
        Run-Step -Name "show_summary" -Action {
            Set-Progress -Step 11 -Status "Resumen..."
            Show-Summary
        }

        Write-Progress -Activity "Lara Diaries" -Completed
        if ($script:IsDryRun) {
            Write-Host "  [DRY-RUN] Simulacion completada. Nada se instalo." -ForegroundColor Yellow
        } else {
            Write-Host "  Gracias por usar Lara Diaries." -ForegroundColor Cyan
        }
        Write-Host ""
    } catch {
        Write-Progress -Activity "Lara Diaries" -Completed
        if ($script:CurrentStep) {
            Write-StepState -StepName $script:CurrentStep -Status "failed" -ErrorMsg $_.Exception.Message
        }
        Write-ErrorMsg "Error: $_"
        Write-Host ""
        Write-Warn "Podes volver a ejecutar el wizard cuando quieras."
        Write-Host ""
        throw
    }
}

# No Export-ModuleMember needed - this is dot-sourced as a .ps1 script
