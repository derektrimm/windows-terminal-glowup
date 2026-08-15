<#
.SYNOPSIS
    Restore what install.ps1 replaced.

.DESCRIPTION
    Puts back the *.bak-glowup backups the installer made: your previous
    PowerShell profile and each Windows Terminal settings.json. Removes the
    installed prompt theme. Backups are point-in-time — anything you changed
    in Windows Terminal since installing is replaced by the backup, and the
    restored file overwrites the current one.

    Deliberately left alone: winget packages (eza, bat, ...), PowerShell
    modules, and the Nerd Font. Remove those with e.g.
      winget uninstall eza-community.eza
      Uninstall-Module Terminal-Icons

.EXAMPLE
    pwsh -File .\uninstall.ps1
.EXAMPLE
    pwsh -File .\uninstall.ps1 -WhatIf    # show what would be restored
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Import-Module (Join-Path $root 'modules' 'WtSettings') -Force

Write-Host ""
Write-Host "  windows-terminal-glowup uninstall" -ForegroundColor Cyan
Write-Host "  ---------------------------------" -ForegroundColor Cyan

$restored = 0

# --- PowerShell profile ------------------------------------------------------
$profilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
$profileBak = "$profilePath.bak-glowup"
if (Test-Path $profileBak) {
    if ($PSCmdlet.ShouldProcess($profilePath, "restore from $profileBak")) {
        Copy-Item $profileBak $profilePath -Force
        Remove-Item $profileBak -Force
        Write-Host "Profile restored <- $profileBak" -ForegroundColor Green
        $restored++
    }
} elseif (Test-Path $profilePath) {
    # No backup means there was no previous profile. Only delete the file if
    # it is still ours, byte for byte — never a profile the user has edited.
    $ours = Get-Content (Join-Path $root 'powershell' 'Microsoft.PowerShell_profile.ps1') -Raw
    if ((Get-Content $profilePath -Raw) -eq $ours) {
        if ($PSCmdlet.ShouldProcess($profilePath, 'remove glowup profile (no backup existed)')) {
            Remove-Item $profilePath -Force
            Write-Host "Profile removed (no previous profile to restore)" -ForegroundColor Green
            $restored++
        }
    } else {
        Write-Host "Profile has local edits and no backup exists - leaving it in place: $profilePath" -ForegroundColor DarkYellow
    }
}

# --- Windows Terminal settings ----------------------------------------------
foreach ($wt in @(Get-WtSettingsPath)) {
    $bak = "$wt.bak-glowup"
    if (-not (Test-Path $bak)) { continue }
    if ($PSCmdlet.ShouldProcess($wt, "restore from $bak (point-in-time backup)")) {
        Copy-Item $bak $wt -Force
        Remove-Item $bak -Force
        Write-Host "Windows Terminal settings restored <- $bak" -ForegroundColor Green
        $restored++
    }
}

# --- Prompt theme ------------------------------------------------------------
$theme = "$env:LOCALAPPDATA\oh-my-posh\themes\two-line.omp.json"
if ($env:LOCALAPPDATA -and (Test-Path $theme)) {
    if ($PSCmdlet.ShouldProcess($theme, 'remove prompt theme')) {
        Remove-Item $theme -Force
        Write-Host "Theme removed -> $theme" -ForegroundColor Green
        $restored++
    }
}

Write-Host ""
if ($restored -eq 0) {
    Write-Host "  Nothing to restore - no glowup backups or files found." -ForegroundColor DarkYellow
} else {
    Write-Host "  Done. Fully close Windows Terminal and open a new tab." -ForegroundColor Cyan
}
Write-Host ""
