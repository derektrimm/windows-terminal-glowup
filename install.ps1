<#
.SYNOPSIS
    windows-terminal-glowup installer.
    Sets up a themed PowerShell 7 prompt, a Nerd Font, modern CLI tools, and a
    matching Windows Terminal appearance + keybindings.

.PARAMETER ConfigureGitDelta
    Also configure git to use 'delta' as its diff pager.

.PARAMETER SkipTools
    Skip the optional modern CLI tools (eza, bat, fd, ripgrep, lazygit, ...).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
.EXAMPLE
    pwsh -File .\install.ps1 -ConfigureGitDelta
#>
[CmdletBinding()]
param(
    [switch]$ConfigureGitDelta,
    [switch]$SkipTools
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Test-Cmd($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Install-WingetId($id) {
    Write-Host "    - $id" -ForegroundColor DarkGray
    winget install --id $id -e -s winget --silent `
        --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Null
}

Write-Host ""
Write-Host "  windows-terminal-glowup" -ForegroundColor Cyan
Write-Host "  -----------------------" -ForegroundColor Cyan

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
        if ($ConfigureGitDelta) { $fwd += '-ConfigureGitDelta' }
        if ($SkipTools)         { $fwd += '-SkipTools' }
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
        'Fastfetch-cli.Fastfetch', 'gerardog.gsudo', 'aristocratos.btop4win'
    )
    foreach ($id in $tools) {
        try { Install-WingetId $id }
        catch { Write-Host "      (skipped $id)" -ForegroundColor DarkYellow }
    }
}

Update-SessionPath

# --- PowerShell modules ------------------------------------------------------
Write-Host "Installing PowerShell modules..." -ForegroundColor Yellow
foreach ($m in 'Terminal-Icons', 'CompletionPredictor', 'PSFzf') {
    try {
        if (Test-Cmd Install-PSResource) { Install-PSResource $m -TrustRepository -ErrorAction Stop }
        else { Install-Module $m -Scope CurrentUser -Force -AllowClobber }
        Write-Host "    - $m" -ForegroundColor DarkGray
    } catch { Write-Host "      (module $m skipped)" -ForegroundColor DarkYellow }
}

# --- Nerd Font (CaskaydiaCove NF) -------------------------------------------
Write-Host "Installing CaskaydiaCove Nerd Font..." -ForegroundColor Yellow
if (Test-Cmd oh-my-posh) { oh-my-posh font install CascadiaCode | Out-Null }
else { Write-Host "      (oh-my-posh not on PATH yet -> open a new shell and run: oh-my-posh font install CascadiaCode)" -ForegroundColor DarkYellow }

# --- Oh My Posh theme --------------------------------------------------------
$themeDir = "$env:LOCALAPPDATA\oh-my-posh\themes"
New-Item -ItemType Directory -Force -Path $themeDir | Out-Null
Copy-Item "$root\oh-my-posh\two-line.omp.json" "$themeDir\two-line.omp.json" -Force
Write-Host "Theme installed -> $themeDir\two-line.omp.json" -ForegroundColor Green

# --- PowerShell 7 profile ----------------------------------------------------
$docs = [Environment]::GetFolderPath('MyDocuments')
$profilePath = Join-Path $docs 'PowerShell\Microsoft.PowerShell_profile.ps1'
New-Item -ItemType Directory -Force -Path (Split-Path $profilePath) | Out-Null
if (Test-Path $profilePath) {
    Copy-Item $profilePath "$profilePath.bak-glowup" -Force
    Write-Host "Backed up existing profile -> $profilePath.bak-glowup" -ForegroundColor DarkYellow
}
Copy-Item "$root\powershell\Microsoft.PowerShell_profile.ps1" $profilePath -Force
Write-Host "Profile installed -> $profilePath" -ForegroundColor Green

# --- Windows Terminal appearance + keybindings ------------------------------
$wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path $wt) {
    Copy-Item $wt "$wt.bak-glowup" -Force
    $j = Get-Content $wt -Raw | ConvertFrom-Json -AsHashtable

    if (-not $j.profiles) { $j.profiles = @{} }
    if (-not $j.profiles.defaults) { $j.profiles.defaults = @{} }
    $defaults = Get-Content "$root\windows-terminal\profile-defaults.json" -Raw | ConvertFrom-Json -AsHashtable
    foreach ($k in $defaults.Keys) { $j.profiles.defaults[$k] = $defaults[$k] }

    $scheme = Get-Content "$root\windows-terminal\color-scheme.tokyo-night.json" -Raw | ConvertFrom-Json -AsHashtable
    if (-not $j.schemes) { $j.schemes = @() }
    $j.schemes = @(@($j.schemes | Where-Object { $_.name -ne $scheme.name }) + $scheme)

    $kb = Get-Content "$root\windows-terminal\keybindings.json" -Raw | ConvertFrom-Json -AsHashtable
    if (-not $j.keybindings) { $j.keybindings = @() }
    $newKeys = $kb | ForEach-Object { $_['keys'] }
    $j.keybindings = @(@($j.keybindings | Where-Object { $_['keys'] -notin $newKeys }) + $kb)

    # Default to PowerShell 7 if its profile exists
    $ps7 = $j.profiles.list | Where-Object { $_.source -eq 'Windows.Terminal.PowershellCore' } | Select-Object -First 1
    if ($ps7) { $j.defaultProfile = $ps7.guid }

    $j.historySize = 20000

    $j | ConvertTo-Json -Depth 32 | Set-Content $wt -Encoding UTF8
    Write-Host "Windows Terminal configured (backup -> settings.json.bak-glowup)" -ForegroundColor Green
} else {
    Write-Host "Windows Terminal not found - skipped appearance. (Install it from the Microsoft Store.)" -ForegroundColor DarkYellow
}

# --- Optional: git + delta ---------------------------------------------------
if ($ConfigureGitDelta) {
    if (Test-Cmd git) {
        git config --global core.pager delta
        git config --global interactive.diffFilter "delta --color-only"
        git config --global delta.navigate true
        git config --global delta.side-by-side true
        git config --global delta.line-numbers true
        git config --global delta.true-color always
        git config --global merge.conflictStyle zdiff3
        Write-Host "git configured to use delta" -ForegroundColor Green
    } else {
        Write-Host "git not found - skipped delta config." -ForegroundColor DarkYellow
    }
}

Write-Host ""
Write-Host "  Done! Fully close Windows Terminal, then open a new tab." -ForegroundColor Cyan
Write-Host "  If glyphs show as boxes, set the font to 'CaskaydiaCove NF' in" -ForegroundColor Cyan
Write-Host "  Settings -> Defaults -> Appearance." -ForegroundColor Cyan
Write-Host ""
