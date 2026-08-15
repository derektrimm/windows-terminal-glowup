# ============================================================================
#  PowerShell 7 profile (windows-terminal-glowup)  —  visual + quality-of-life setup
#  Safe to edit. Reload with:  . $PROFILE
# ============================================================================

# --- Oh My Posh : themed two-line Tokyo Night prompt -------------------------
$ompTheme = "$env:LOCALAPPDATA\oh-my-posh\themes\two-line.omp.json"
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config $ompTheme | Invoke-Expression
}

# --- Terminal-Icons : file-type glyphs in ls / dir --------------------------
Import-Module Terminal-Icons -ErrorAction SilentlyContinue

# --- PSReadLine : predictive IntelliSense, syntax colors, smarter keys -------
if ((Get-Module -ListAvailable PSReadLine) -and $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected) {
    Import-Module PSReadLine
    Import-Module CompletionPredictor -ErrorAction SilentlyContinue
    try { Set-PSReadLineOption -PredictionSource HistoryAndPlugin } catch { Set-PSReadLineOption -PredictionSource History }
    Set-PSReadLineOption -PredictionViewStyle ListView         # dropdown of suggestions
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -BellStyle None

    # Tokyo Night syntax-highlight palette
    Set-PSReadLineOption -Colors @{
        Command            = "#7AA2F7"
        Parameter          = "#BB9AF7"
        Operator           = "#89DDFF"
        Variable           = "#9ECE6A"
        String             = "#9ECE6A"
        Number             = "#FF9E64"
        Type               = "#2AC3DE"
        Comment            = "#565F89"
        Keyword            = "#BB9AF7"
        Error              = "#F7768E"
        InlinePrediction   = "#565F89"
        ListPrediction     = "#7AA2F7"
        Default            = "#C0CAF5"
    }

    # Keys: arrows search history by prefix, Tab = menu, Ctrl+f accept suggestion
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
    Set-PSReadLineKeyHandler -Key Ctrl+f    -Function AcceptSuggestion
    Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function ForwardWord

    # Ctrl+V: a clipboard image is saved as a PNG and its path inserted; copied
    # files insert their paths; plain text pastes as usual. Windows Terminal's
    # own Ctrl+V binding is released in keybindings.json so the chord reaches
    # the shell — Ctrl+Shift+V and right-click keep the terminal's text paste.
    if ($IsWindows) {
        Set-PSReadLineKeyHandler -Key Ctrl+v -BriefDescription PasteImageOrText `
            -Description 'Paste a clipboard image as a saved PNG path, files as paths, text as text' -ScriptBlock {
            $handled = $false
            try {
                Add-Type -AssemblyName System.Windows.Forms, System.Drawing
                # Text wins (including the path the clipboard shim adds), so an
                # Office-style image+text copy pastes its text as expected.
                if (-not [System.Windows.Forms.Clipboard]::ContainsText()) {
                    if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
                        $img = [System.Windows.Forms.Clipboard]::GetImage()
                        try {
                            $dir = Join-Path ([IO.Path]::GetTempPath()) 'terminal-pastes'
                            $null = New-Item -ItemType Directory -Force -Path $dir
                            $file = Join-Path $dir ('paste-{0:yyyyMMdd-HHmmss-ff}.png' -f (Get-Date))
                            $img.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
                            [Microsoft.PowerShell.PSConsoleReadLine]::Insert('"' + $file + '"')
                            $handled = $true
                        } finally { $img.Dispose() }
                    }
                    elseif ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {
                        $paths = foreach ($p in [System.Windows.Forms.Clipboard]::GetFileDropList()) { '"' + $p + '"' }
                        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($paths -join ' ')
                        $handled = $true
                    }
                }
            } catch { $handled = $false }   # clipboard busy or MTA session -> text paste
            if (-not $handled) { [Microsoft.PowerShell.PSConsoleReadLine]::Paste() }
        }
    }
}

# --- $PSStyle : nicer built-in file listing / error colors (pwsh 7.2+) -------
if ($PSStyle) {
    $PSStyle.FileInfo.Directory = "`e[1;38;2;122;162;247m"   # bold blue dirs
    $PSStyle.Formatting.Error        = "`e[38;2;247;118;142m"
    $PSStyle.Formatting.Warning      = "`e[38;2;224;175;104m"
    $PSStyle.Formatting.TableHeader  = "`e[38;2;187;154;247m"
}

# --- zoxide : smart `cd` that learns your most-used dirs ----------------------
#   cd <partial>  jumps to best match   |   cdi  interactive picker
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell --cmd cd | Out-String) })
}

# --- Quality-of-life aliases & helpers --------------------------------------
# Modern `ls` (eza) with icons + git status; falls back to Get-ChildItem
if (Get-Command eza -ErrorAction SilentlyContinue) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls { eza --icons --group-directories-first @args }
    function ll { eza -l  --icons --group-directories-first --git @args }
    function la { eza -la --icons --group-directories-first --git @args }
    function lt { eza --tree --level=2 --icons @args }
} else {
    function ll { Get-ChildItem -Force @args }
    function la { Get-ChildItem -Force -Hidden @args }
}
# Modern `cat` (bat) with syntax highlighting
if (Get-Command bat -ErrorAction SilentlyContinue) {
    Remove-Item Alias:cat -Force -ErrorAction SilentlyContinue
    function cat { bat --paging=never @args }
}
# icat <file...> : show images inline (chafa; sixels on Windows Terminal 1.22+,
# unicode blocks anywhere else). Drag a file in or Ctrl+V a screenshot, then icat it.
if (Get-Command chafa -ErrorAction SilentlyContinue) {
    function icat { chafa --align center @args }
}
function .. { Set-Location .. }
function ... { Set-Location ../.. }
function gs  { git status @args }
function gd  { git diff @args }
function gds { git diff --staged @args }
function gl  { git log --oneline --graph --decorate -20 @args }
function lg  { lazygit @args }
function which ($cmd) { (Get-Command $cmd -ErrorAction SilentlyContinue).Source }
function reload { . $PROFILE }
# sudo (gsudo) if no native sudo present
if ((Get-Command gsudo -ErrorAction SilentlyContinue) -and -not (Get-Command sudo -ErrorAction SilentlyContinue)) {
    Set-Alias sudo gsudo
}

# --- Multi-session helpers : open projects in new tabs ----------------------
$global:ProjectRoots = @(
    "$env:USERPROFILE",
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Documents\GitHub",
    "$env:USERPROFILE\code",
    "$env:USERPROFILE\source\repos"
)
function Get-Projects {
    foreach ($r in $global:ProjectRoots) {
        if (Test-Path $r) {
            Get-ChildItem $r -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path (Join-Path $_.FullName '.git') }
        }
    }
}
# nt <name> : open a matching project in a NEW Windows Terminal tab (auto-titled)
function nt {
    param([Parameter(Mandatory)][string]$Name)
    $hit = Get-Projects | Where-Object Name -like "*$Name*" | Select-Object -First 1
    if (-not $hit) { Write-Host "No project matching '$Name'" -ForegroundColor Red; return }
    wt -w 0 new-tab --title $hit.Name -d $hit.FullName pwsh
}
# pj <name> : jump to a matching project in the CURRENT tab
function pj {
    param([Parameter(Mandatory)][string]$Name)
    $hit = Get-Projects | Where-Object Name -like "*$Name*" | Select-Object -First 1
    if ($hit) { Set-Location $hit.FullName } else { Write-Host "No project matching '$Name'" -ForegroundColor Red }
}
# Tab-completion of project names for nt / pj
$projCompleter = {
    param($commandName, $parameterName, $wordToComplete)
    (Get-Projects).Name | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
Register-ArgumentCompleter -CommandName nt, pj -ParameterName Name -ScriptBlock $projCompleter

# --- fzf fuzzy finder : Ctrl+R fuzzy history, Ctrl+T file picker -------------
if ((Get-Module -ListAvailable PSFzf) -and (Get-Command fzf -ErrorAction SilentlyContinue) `
    -and $Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}

# --- Clipboard image shim : right-click paste for images --------------------
# A background watcher (clipboard-image-shim.ps1, installed next to this
# profile) saves a copied image to a PNG and adds its quoted path as clipboard
# TEXT — never replacing text you copied — so Windows Terminal's right-click
# and Ctrl+Shift+V paste the path in ANY tab (cmd and WSL included). One
# hidden instance per login session. Disable: set GLOWUP_NO_CLIP_SHIM=1.
if ($IsWindows -and -not $env:GLOWUP_NO_CLIP_SHIM) {
    $shimScript = Join-Path $PSScriptRoot 'clipboard-image-shim.ps1'
    if (Test-Path $shimScript) {
        $shimMutex = $null
        $shimRunning = [System.Threading.Mutex]::TryOpenExisting(
            'Local\windows-terminal-glowup-clip-shim', [ref]$shimMutex)
        if ($shimMutex) { $shimMutex.Dispose() }
        if (-not $shimRunning) {
            Start-Process pwsh -WindowStyle Hidden -ArgumentList `
                '-NoProfile', '-NoLogo', '-ExecutionPolicy', 'Bypass', '-File', $shimScript
        }
    }
}

# --- fastfetch system banner on startup (comment out for a silent start) -----
if ((Get-Command fastfetch -ErrorAction SilentlyContinue) -and $Host.Name -eq 'ConsoleHost') {
    fastfetch
} else {
    Write-Host ""
}

