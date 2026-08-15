<#
.SYNOPSIS
    windows-terminal-glowup installer.
    Sets up a themed PowerShell 7 prompt, a Nerd Font, modern CLI tools, and a
    matching Windows Terminal appearance + keybindings.

.DESCRIPTION
    Idempotent: safe to re-run. Anything it replaces is backed up next to the
    original as *.bak-glowup. Windows Terminal's settings.json is merged, not
    overwritten — your profiles, schemes, and unrelated keybindings survive.
    The merge lives in modules/WtSettings and is covered by tests/.

.PARAMETER ConfigureGitDelta
    Also configure git to use 'delta' as its diff pager.

.PARAMETER SkipTools
    Skip the optional modern CLI tools (eza, bat, fd, ripgrep, lazygit, ...).

.PARAMETER Verify
    Install nothing; report what is installed, what is missing, and whether
    Windows Terminal actually carries the glowup settings. Exits non-zero if
    a core piece is missing.

.PARAMETER Theme
    Color theme for the terminal, prompt, and shell highlighting: one folder
    under themes/. Re-run with a different -Theme any time to switch.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
.EXAMPLE
    pwsh -File .\install.ps1 -Theme gruvbox-dark
.EXAMPLE
    pwsh -File .\install.ps1 -ConfigureGitDelta
.EXAMPLE
    pwsh -File .\install.ps1 -WhatIf        # dry run: print every change, make none
.EXAMPLE
    pwsh -File .\install.ps1 -Verify        # health check after installing
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$ConfigureGitDelta,
    [switch]$SkipTools,
    [switch]$Verify,
    [ValidateSet('tokyo-night', 'catppuccin-mocha', 'gruvbox-dark', 'nord')]
    [string]$Theme = 'tokyo-night'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$themeSrc = Join-Path $root 'themes' $Theme
Import-Module (Join-Path $root 'modules' 'WtSettings') -Force

function Test-Cmd($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

function Update-SessionPath {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Refreshes $env:Path for this session only; nothing on disk changes.')]
    param()
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Install-WingetId {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Id)
    if (-not $PSCmdlet.ShouldProcess($Id, 'winget install')) { return }
    Write-Host "    - $Id" -ForegroundColor DarkGray
    winget install --id $Id -e -s winget --silent `
        --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Null
    # winget signals failure through its exit code, which $ErrorActionPreference
    # never sees. 0x8A15002B / 0x8A150061 mean "already installed, nothing to do".
    if ($LASTEXITCODE -notin 0, 0x8A15002B, 0x8A150061) {
        throw "winget failed for $Id (exit code 0x$('{0:X8}' -f $LASTEXITCODE))"
    }
}

function Get-ProfilePath {
    Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
}

# --- Verify: report state, change nothing -----------------------------------
function Invoke-Verify {
    $rows = [System.Collections.Generic.List[object]]::new()
    function Add-Check([string]$Area, [string]$Check, [bool]$Ok, [string]$Detail, [bool]$Core = $true) {
        $rows.Add([pscustomobject]@{
            Area = $Area; Check = $Check
            Status = if ($Ok) { 'OK' } else { if ($Core) { 'MISSING' } else { 'missing' } }
            Detail = $Detail; Ok = $Ok; Core = $Core
        })
    }

    Add-Check 'shell' 'PowerShell 7' ($PSVersionTable.PSVersion.Major -ge 7) "running $($PSVersionTable.PSVersion)"
    Add-Check 'prompt' 'oh-my-posh on PATH' (Test-Cmd oh-my-posh) ''
    $theme = "$env:LOCALAPPDATA\oh-my-posh\themes\two-line.omp.json"
    Add-Check 'prompt' 'theme installed' ([bool]($env:LOCALAPPDATA -and (Test-Path $theme))) $theme

    $profilePath = Get-ProfilePath
    $profileOk = (Test-Path $profilePath) -and
        (Select-String -Path $profilePath -Pattern 'two-line\.omp\.json' -Quiet)
    Add-Check 'shell' 'glowup profile' $profileOk $profilePath

    foreach ($m in 'Terminal-Icons', 'CompletionPredictor', 'PSFzf') {
        Add-Check 'modules' $m ([bool](Get-Module -ListAvailable $m)) '' $false
    }

    $themeColors = Join-Path (Split-Path $profilePath) 'theme-colors.json'
    Add-Check 'shell' 'theme colors installed' (Test-Path $themeColors) $themeColors $false

    $shimFile = Join-Path (Split-Path $profilePath) 'clipboard-image-shim.ps1'
    Add-Check 'clipboard' 'image shim installed' (Test-Path $shimFile) $shimFile $false
    $shimMutex = $null
    $shimRunning = [System.Threading.Mutex]::TryOpenExisting('Local\windows-terminal-glowup-clip-shim', [ref]$shimMutex)
    if ($shimMutex) { $shimMutex.Dispose() }
    Add-Check 'clipboard' 'image shim running' $shimRunning $(
        if ($env:GLOWUP_NO_CLIP_SHIM) { 'disabled via GLOWUP_NO_CLIP_SHIM' } else { '' }) $false

    if ($IsWindows) {
        $fontHives = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
                     'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
        $fontOk = [bool]($fontHives | ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
            ForEach-Object { $_.PSObject.Properties.Name } | Where-Object { $_ -like 'CaskaydiaCove*' })
        Add-Check 'font' 'CaskaydiaCove NF registered' $fontOk ''

        $wtPaths = @(Get-WtSettingsPath)
        Add-Check 'terminal' 'Windows Terminal settings found' ($wtPaths.Count -gt 0) ($wtPaths -join '; ')
        $shipKeys = @(Get-Content (Join-Path $root 'windows-terminal' 'keybindings.json') -Raw | ConvertFrom-Json -AsHashtable)
        foreach ($wt in $wtPaths) {
            $j = Get-Content $wt -Raw | ConvertFrom-WtJson
            $wantScheme = if ($j['profiles'] -is [System.Collections.IDictionary]) {
                $j['profiles']['defaults']['colorScheme'] } else { $null }
            $schemeOk = [bool]($wantScheme -and
                @(@($j['schemes']) | Where-Object { $_['name'] -eq $wantScheme }))
            $fontSet = $j['profiles'] -is [System.Collections.IDictionary] -and
                       $j['profiles']['defaults']['font']['face'] -eq 'CaskaydiaCove NF'
            $bound = @($j['keybindings']) | ForEach-Object { if ($_['keys']) { Get-WtNormalizedChord $_['keys'] } }
            $missingKeys = @($shipKeys | Where-Object { (Get-WtNormalizedChord $_['keys']) -notin $bound })
            $leaf = Split-Path (Split-Path $wt) -Leaf
            Add-Check 'terminal' "scheme in $leaf" $schemeOk $(
                if ($wantScheme) { $wantScheme } else { 'no colorScheme set' })
            Add-Check 'terminal' "font default in $leaf" $fontSet ''
            Add-Check 'terminal' "keybindings in $leaf" ($missingKeys.Count -eq 0) $(
                if ($missingKeys.Count) { "$($missingKeys.Count) of $($shipKeys.Count) missing" } else { "all $($shipKeys.Count) bound" })
        }
    } else {
        Add-Check 'terminal' 'Windows Terminal checks' $true 'skipped: not Windows' $false
    }

    foreach ($t in 'eza', 'bat', 'fd', 'rg', 'delta', 'lazygit', 'fzf', 'tldr', 'fastfetch', 'gsudo', 'btop', 'zoxide', 'chafa') {
        Add-Check 'tools' $t (Test-Cmd $t) '' $false
    }

    $rows | Format-Table Area, Check, Status, Detail -AutoSize
    $failedCore = @($rows | Where-Object { $_.Core -and -not $_.Ok })
    if ($failedCore.Count) {
        Write-Host "  $($failedCore.Count) core check(s) failing — run install.ps1 to fix." -ForegroundColor Red
        exit 1
    }
    Write-Host '  All core checks pass.' -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "  windows-terminal-glowup" -ForegroundColor Cyan
Write-Host "  -----------------------" -ForegroundColor Cyan

if ($Verify) { Invoke-Verify }

# --- winget is required -------------------------------------------------------
if (-not (Test-Cmd winget)) {
    throw "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
}

# --- Ensure PowerShell 7, then run the rest under it -------------------------
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "Installing PowerShell 7..." -ForegroundColor Yellow
    Install-WingetId 'Microsoft.PowerShell'
    Update-SessionPath
    if (Test-Cmd pwsh) {
        Write-Host "Relaunching under PowerShell 7..." -ForegroundColor Yellow
        $fwd = @()
        foreach ($p in 'ConfigureGitDelta', 'SkipTools', 'WhatIf') {
            if ($PSBoundParameters[$p]) { $fwd += "-$p" }
        }
        if ($PSBoundParameters['Theme']) { $fwd += '-Theme', $Theme }
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @fwd
        exit $LASTEXITCODE
    }
    throw "PowerShell 7 install did not expose 'pwsh'. Open a new terminal and re-run with pwsh."
}

# --- Core: Oh My Posh + zoxide ----------------------------------------------
Write-Host "Installing Oh My Posh + zoxide..." -ForegroundColor Yellow
Install-WingetId 'JanDeDobbeleer.OhMyPosh'
Install-WingetId 'ajeetdsouza.zoxide'

# --- Modern CLI tools (optional) --------------------------------------------
if (-not $SkipTools) {
    Write-Host "Installing modern CLI tools..." -ForegroundColor Yellow
    $tools = @(
        'eza-community.eza', 'sharkdp.bat', 'sharkdp.fd', 'BurntSushi.ripgrep.MSVC',
        'dandavison.delta', 'JesseDuffield.lazygit', 'junegunn.fzf', 'dbrgn.tealdeer',
        'Fastfetch-cli.Fastfetch', 'gerardog.gsudo', 'aristocratos.btop4win', 'hpjansson.Chafa'
    )
    foreach ($id in $tools) {
        try { Install-WingetId $id }
        catch { Write-Host "      (skipped $id — $($_.Exception.Message))" -ForegroundColor DarkYellow }
    }
}

Update-SessionPath

# --- PowerShell modules ------------------------------------------------------
Write-Host "Installing PowerShell modules..." -ForegroundColor Yellow
foreach ($m in 'Terminal-Icons', 'CompletionPredictor', 'PSFzf') {
    if (-not $PSCmdlet.ShouldProcess($m, 'install PowerShell module')) { continue }
    try {
        if (Test-Cmd Install-PSResource) { Install-PSResource $m -TrustRepository -ErrorAction Stop }
        else { Install-Module $m -Scope CurrentUser -Force -AllowClobber }
        Write-Host "    - $m" -ForegroundColor DarkGray
    } catch { Write-Host "      (module $m skipped)" -ForegroundColor DarkYellow }
}

# --- Nerd Font (CaskaydiaCove NF) -------------------------------------------
Write-Host "Installing CaskaydiaCove Nerd Font..." -ForegroundColor Yellow
if (Test-Cmd oh-my-posh) {
    if ($PSCmdlet.ShouldProcess('CascadiaCode Nerd Font', 'oh-my-posh font install')) {
        oh-my-posh font install CascadiaCode | Out-Null
    }
} else {
    Write-Host "      (oh-my-posh not on PATH yet -> open a new shell and run: oh-my-posh font install CascadiaCode)" -ForegroundColor DarkYellow
}

# --- Oh My Posh theme --------------------------------------------------------
# The chosen theme's prompt file always installs under the same name, so the
# profile needs no per-theme knowledge and re-running with -Theme switches it.
$themeDir = "$env:LOCALAPPDATA\oh-my-posh\themes"
if ($PSCmdlet.ShouldProcess("$themeDir\two-line.omp.json", "install prompt theme ($Theme)")) {
    New-Item -ItemType Directory -Force -Path $themeDir | Out-Null
    Copy-Item (Join-Path $themeSrc 'two-line.omp.json') "$themeDir\two-line.omp.json" -Force
    Write-Host "Prompt theme ($Theme) -> $themeDir\two-line.omp.json" -ForegroundColor Green
}

# --- PowerShell 7 profile ----------------------------------------------------
$profilePath = Get-ProfilePath
if ($PSCmdlet.ShouldProcess($profilePath, 'install glowup profile (backing up any existing one)')) {
    New-Item -ItemType Directory -Force -Path (Split-Path $profilePath) | Out-Null
    if (Test-Path $profilePath) {
        Copy-Item $profilePath "$profilePath.bak-glowup" -Force
        Write-Host "Backed up existing profile -> $profilePath.bak-glowup" -ForegroundColor DarkYellow
    }
    Copy-Item (Join-Path $root 'powershell' 'Microsoft.PowerShell_profile.ps1') $profilePath -Force
    Copy-Item (Join-Path $root 'powershell' 'clipboard-image-shim.ps1') (Split-Path $profilePath) -Force
    Copy-Item (Join-Path $themeSrc 'psreadline-colors.json') (Join-Path (Split-Path $profilePath) 'theme-colors.json') -Force
    Write-Host "Profile installed -> $profilePath" -ForegroundColor Green
}

# --- Windows Terminal appearance + keybindings ------------------------------
# Merged via modules/WtSettings: profiles/schemes/bindings you already have
# survive; our chords evict conflicts from both "keybindings" and "actions".
$wtPaths = @(Get-WtSettingsPath)
if ($wtPaths.Count -eq 0) {
    Write-Host "Windows Terminal not found - skipped appearance. (Install it from the Microsoft Store.)" -ForegroundColor DarkYellow
} else {
    $defaults = Get-Content (Join-Path $root 'windows-terminal' 'profile-defaults.json') -Raw | ConvertFrom-WtJson
    $scheme   = Get-Content (Join-Path $themeSrc 'color-scheme.json') -Raw | ConvertFrom-WtJson
    $kb       = @(Get-Content (Join-Path $root 'windows-terminal' 'keybindings.json') -Raw | ConvertFrom-Json -AsHashtable)
    $defaults['colorScheme'] = $scheme['name']

    foreach ($wt in $wtPaths) {
        if (-not $PSCmdlet.ShouldProcess($wt, 'merge glowup appearance + keybindings (backup first)')) { continue }
        Copy-Item $wt "$wt.bak-glowup" -Force
        $j = Get-Content $wt -Raw | ConvertFrom-WtJson
        $j = Merge-WtSettings -Settings $j -Defaults $defaults -Scheme $scheme -Keybindings $kb
        ConvertTo-WtJson -Settings $j | Set-Content $wt -Encoding UTF8
        Write-Host "Windows Terminal configured -> $wt (backup: settings.json.bak-glowup)" -ForegroundColor Green
    }
}

# --- Optional: git + delta ---------------------------------------------------
if ($ConfigureGitDelta) {
    if (Test-Cmd git) {
        if ($PSCmdlet.ShouldProcess('global git config', 'set delta as diff pager')) {
            git config --global core.pager delta
            git config --global interactive.diffFilter "delta --color-only"
            git config --global delta.navigate true
            git config --global delta.side-by-side true
            git config --global delta.line-numbers true
            git config --global delta.true-color always
            git config --global merge.conflictStyle zdiff3
            Write-Host "git configured to use delta" -ForegroundColor Green
        }
    } else {
        Write-Host "git not found - skipped delta config." -ForegroundColor DarkYellow
    }
}

Write-Host ""
Write-Host "  Done! Fully close Windows Terminal, then open a new tab." -ForegroundColor Cyan
Write-Host "  If glyphs show as boxes, set the font to 'CaskaydiaCove NF' in" -ForegroundColor Cyan
Write-Host "  Settings -> Defaults -> Appearance." -ForegroundColor Cyan
Write-Host "  Health check any time:  pwsh -File .\install.ps1 -Verify" -ForegroundColor Cyan
Write-Host ""
