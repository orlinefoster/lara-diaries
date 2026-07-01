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

# ── PROGRESS ──────────────────────────────────
$script:ProgressSteps = @(
    "Login de GitHub",
    "Directorio de proyectos",
    "Gentle AI",
    "Preferencias personales",
    "Gestion de repos",
    "Disenio y estilo",
    "Mision del equipo",
    "Instalacion",
    "Sincronizacion",
    "Resumen final"
)
$script:ProgressTotal = 10

function Set-Progress {
    param([int]$Step, [string]$Status = "...")
    $pct = [math]::Min(100, [math]::Max(0, [int](($Step / $script:ProgressTotal) * 100)))
    $label = $script:ProgressSteps[$Step]
    Write-Progress -Activity "Lara Diaries - Configuracion" -Status $label -CurrentOperation $Status -PercentComplete $pct
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

    $null = & gh auth status 2>&1
    if ($LASTEXITCODE -eq 0) {
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
        $username = & gh api user --jq .login 2>$null
        if (-not $username -or $LASTEXITCODE -ne 0) {
            $json = & gh api user 2>$null
            $obj = $json | ConvertFrom-Json
            $username = $obj.login
        }
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

    # Gentleman Guardian Angel (optional code review tool)
    $installGGA = Read-Host "  Instalar Gentleman Guardian Angel? (revision automatica de codigo, s/N, predeterminado: N)"
    $val4 = ($installGGA -like "S*" -or $installGGA -like "s*")
    $script:WizardAnswers.InstallGGA = $val4
    if ($val4) { Write-Success "Gentleman Guardian Angel incluido" }
    else { Write-Info "Gentleman Guardian Angel omitido (se puede instalar despues)" }
    $script:UserProfile.InstallGGA = $val4

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

# ── SAVE USER PROFILE ────────────────────────
function Save-UserProfile {
    $profileDir = Join-Path $env:LOCALAPPDATA "lara-diaries"
    if (-not (Test-Path -LiteralPath $profileDir)) {
        $null = New-Item -ItemType Directory -Path $profileDir -Force
    }
    $profilePath = Join-Path $profileDir "user-profile.json"
    try {
        $json = $script:UserProfile | ConvertTo-Json -Compress
        $json | Set-Content -Path $profilePath -Encoding UTF8 -Force
        Write-Info "Perfil guardado en: $profilePath"
    } catch {
        Write-Warn "No se pudo guardar el perfil: $_"
    }
}

# ── DRY-RUN / STATUS HELPERS ─────────────────
$script:IsDryRun = if ($script:IsDryRun -eq $true) { $true } else { $false }

function Write-Status {
    param([string]$Component, [string]$Status)
    $icon = switch ($Status) {
        "INSTALADO"  { "✅" }
        "INSTALAR"   { "⬇️ " }
        "OMITIDO"    { "⏭️ " }
        "OPCIONAL"   { "🔧" }
        "ERROR"      { "❌" }
        default      { "❓" }
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
        [switch]$Optional
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
        return $false
    }
}

# ── 8. INSTALL COMPONENTS ────────────────────
function Install-Components {
    Write-Step "Paso 8/10 - Instalacion de componentes"
    Set-Progress -Step 7 -Status "Instalando componentes..."

    if ($script:IsDryRun) {
        Write-Host "  [DRY-RUN] No se instalara nada. Reportando estado actual...`n" -ForegroundColor Cyan
    }

    $opencodeSkillsDir = Join-Path $env:APPDATA "opencode\skills"
    $opencodeAgentsDir = Join-Path $env:APPDATA "opencode\agents"

    # Gentle AI
    if ($script:WizardAnswers.InstallGentleAI) {
        $gaDir = Join-Path $HOME "gentle-ai"
        $null = Install-Component -Name "Gentle AI" `
            -CheckBlock { Test-Path -LiteralPath $gaDir } `
            -InstallBlock {
                $null = & git clone "https://github.com/Gentleman-Programming/gentle-ai.git" $gaDir 2>&1
                if ($LASTEXITCODE -eq 0) { Write-Success "Gentle AI clonado en: $gaDir" }
                else { throw "Error clonando Gentle AI" }
                $gaInstaller = Join-Path $gaDir "install.ps1"
                if (Test-Path -LiteralPath $gaInstaller) {
                    Write-Info "Ejecutando instalador de Gentle AI..."
                    $null = & $gaInstaller 2>&1
                    Write-Success "Instalador ejecutado."
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
            $winget = Get-Command "winget" -ErrorAction SilentlyContinue
            if ($winget) {
                $null = & winget install "engram" --accept-source-agreements --accept-package-agreements 2>&1
                $reCheck = Get-Command "engram" -ErrorAction SilentlyContinue
                if (-not $reCheck) { throw "No se pudo instalar engram con winget." }
            } else {
                throw "winget no disponible. Descarga desde: https://github.com/Gentleman-Programming/engram/releases"
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
                    $reCheck = Get-Command "code" -ErrorAction SilentlyContinue
                    if (-not $reCheck) { throw "VSCode instalado pero 'code' no esta en PATH." }
                } else {
                    throw "winget no disponible. Descarga desde: https://code.visualstudio.com/"
                }
            }
    } else {
        Write-Status -Component "VSCode" -Status "OMITIDO"
    }

    # Gentleman Guardian Angel (optional)
    if ($script:WizardAnswers.InstallGGA) {
        $ggaDir = Join-Path $HOME "gentleman-guardian-angel"
        $null = Install-Component -Name "Gentleman Guardian Angel" -Optional `
            -CheckBlock { Test-Path -LiteralPath $ggaDir } `
            -InstallBlock {
                $null = & git clone "https://github.com/Gentleman-Programming/gentleman-guardian-angel.git" $ggaDir 2>&1
                if ($LASTEXITCODE -ne 0) { throw "Error clonando GGA" }
                $ggaInstall = Join-Path $ggaDir "install.ps1"
                if (Test-Path -LiteralPath $ggaInstall) {
                    $null = & $ggaInstall 2>&1
                } else {
                    $ggaSh = Join-Path $ggaDir "install.sh"
                    if (Test-Path -LiteralPath $ggaSh) {
                        $null = & "bash" $ggaSh 2>&1
                    }
                }
                Write-Success "GGA instalado. Para activarlo: gga init en tu proyecto."
            }
    } else {
        Write-Status -Component "Gentleman Guardian Angel" -Status "OMITIDO"
    }

    # Create agents from templates
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

    # GitHub repos
    $ghUser = $script:WizardAnswers.GitHubUser
    if (-not [string]::IsNullOrWhiteSpace($ghUser)) {
        $reposToCheck = @("engram-memories", "opencode-config")
        foreach ($repoName in $reposToCheck) {
            Write-Info "Verificando repo: $ghUser/$repoName..."
            $repoCheck = & gh repo view "$ghUser/$repoName" --json name 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Repo $repoName ya existe."
            } else {
                Write-Info "Creando repo privado: $repoName..."
                try {
                    $null = & gh repo create "$repoName" --private --clone 2>&1
                    if ($LASTEXITCODE -eq 0) { Write-Success "Repo $repoName creado." }
                    else { Write-ErrorMsg "Error creando repo $repoName."; continue }
                } catch { Write-ErrorMsg "Error creando repo $($repoName): $_"; continue }
            }
            $localRepo = Join-Path $HOME $repoName
            if (-not (Test-Path -LiteralPath $localRepo)) {
                try {
                    Push-Location $HOME
                    $null = & gh repo clone "$ghUser/$repoName" 2>&1
                    if ($LASTEXITCODE -eq 0) { Write-Success "Repo clonado en: $localRepo" }
                    Pop-Location
                } catch { Write-Warn "Error clonando $repoName"; try { Pop-Location } catch {} }
            } else { Write-Info "Repo ya clonado en: $localRepo" }
        }
    } else {
        Write-Warn "Usuario de GitHub no disponible. Saltando creacion de repos."
    }

    # First backup
    $configRepoDir = Join-Path $HOME "opencode-config"
    if (Test-Path -LiteralPath $configRepoDir) {
        Write-Info "Ejecutando primer backup..."
        try {
            Push-Location $configRepoDir
            $opencodeConfig = Join-Path $env:APPDATA "opencode\opencode.json"
            $agentsMd = Join-Path $env:APPDATA "opencode\AGENTS.md"
            $agentsDir = Join-Path $env:APPDATA "opencode\agents"
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

# ── 10. SHOW SUMMARY ─────────────────────────
function Show-Summary {
    Write-Step "Paso 10/10 - Resumen final"
    Set-Progress -Step 9 -Status "Mostrando resumen..."

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
    $gga = $script:WizardAnswers.InstallGGA

    if ($vscode) { Write-Host "  [x] VSCode" -ForegroundColor Green }
    else { Write-Host "  [ ] VSCode" -ForegroundColor Gray }

    if ($gga) { Write-Host "  [x] Gentleman Guardian Angel" -ForegroundColor Green }
    else { Write-Host "  [ ] Gentleman Guardian Angel" -ForegroundColor Gray }

    if ($c3) { Write-Host "  [x] design.md" -ForegroundColor Green }
    else { Write-Host "  [ ] design.md" -ForegroundColor Gray }

    Write-Host "`n  [Directorios]" -ForegroundColor Magenta
    Write-Host "  Proyectos : $($script:WizardAnswers.DevDir)" -ForegroundColor White
    Write-Host "  Agentes   : $(Join-Path $env:APPDATA 'opencode\agents')" -ForegroundColor White
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

# ── MAIN WIZARD ORCHESTRATOR ──────────────────
function Start-Wizard {
    Write-Host "`n"
    Write-Host "+---------------------------------------------+" -ForegroundColor Magenta
    Write-Host "|        ASISTENTE DE CONFIGURACION            |" -ForegroundColor Magenta
    Write-Host "|     Te voy a hacer 10 preguntas              |" -ForegroundColor Magenta
    Write-Host "+---------------------------------------------+" -ForegroundColor Magenta
    Write-Host "  Responde con el numero de opcion." -ForegroundColor Gray
    Write-Host "  Los valores predeterminados estan entre parentesis.`n" -ForegroundColor Gray

    try {
        Set-Progress -Step 0 -Status "Login GitHub..."
        Invoke-GitHubLogin

        Set-Progress -Step 1 -Status "Directorio..."
        Invoke-DevDirectoryPrompt

        Set-Progress -Step 2 -Status "Gentle AI..."
        Invoke-GentleAIPrompt

        Set-Progress -Step 3 -Status "Preferencias..."
        Invoke-RecognitionQuestions

        Set-Progress -Step 4 -Status "Repos..."
        Invoke-RepoManagementPrompt

        Set-Progress -Step 5 -Status "Disenio..."
        Invoke-DesignOrientationPrompt

        Set-Progress -Step 6 -Status "Mision..."
        Invoke-MissionPrompt

        Set-Progress -Step 7 -Status "Instalando..."
        Install-Components

        Set-Progress -Step 8 -Status "Sincronizacion..."
        Setup-Sync

        Set-Progress -Step 9 -Status "Resumen..."
        Show-Summary

        Write-Progress -Activity "Lara Diaries" -Completed
        Write-Host "  Gracias por usar Lara Diaries." -ForegroundColor Cyan
        Write-Host ""
    } catch {
        Write-Progress -Activity "Lara Diaries" -Completed
        Write-ErrorMsg "Error: $_"
        Write-Host ""
        Write-Warn "Podes volver a ejecutar el wizard cuando quieras."
        Write-Host ""
        throw
    }
}

# No Export-ModuleMember needed - this is dot-sourced as a .ps1 script
