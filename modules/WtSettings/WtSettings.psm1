# ============================================================================
#  WtSettings — the merge engine behind windows-terminal-glowup.
#
#  Windows Terminal owns its settings.json; we are a guest in that file. Every
#  function here is a pure transform on the parsed settings object so the whole
#  merge is unit-testable on any OS (the suite runs on Linux in CI). File IO,
#  backups, and ShouldProcess live in install.ps1 / uninstall.ps1 — not here.
#
#  What the merge guarantees:
#    - JSONC input (comments, trailing commas) parses; unknown keys survive.
#    - The legacy layout where "profiles" is a bare array is upgraded in place.
#    - A key chord is claimed exactly once: conflicting bindings are removed
#      from BOTH the legacy "keybindings" array and the modern "actions" array,
#      comparing normalized chords ("shift+ctrl+f" == "ctrl+shift+f").
#    - An "actions" entry with an id keeps its action (only the chord is
#      taken); an inline binding with no id is superseded and dropped.
# ============================================================================

function ConvertFrom-WtJson {
    <#
    .SYNOPSIS
        Parse Windows Terminal JSONC (comments + trailing commas) into an
        ordered hashtable tree.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Text
    )
    process {
        # pwsh's ConvertFrom-Json accepts comments and trailing commas; the
        # dedicated name pins that contract (and the tests prove it).
        $Text | ConvertFrom-Json -AsHashtable -Depth 64
    }
}

function ConvertTo-WtJson {
    <#
    .SYNOPSIS
        Serialize a settings tree back to JSON for settings.json.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings
    )
    $Settings | ConvertTo-Json -Depth 64
}

function Get-WtSettingsPath {
    <#
    .SYNOPSIS
        Every Windows Terminal settings.json present on this machine:
        stable, Preview, and the unpackaged (Scoop/Chocolatey) location.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    ) | Where-Object { $env:LOCALAPPDATA -and (Test-Path $_) }
}

function Get-WtNormalizedChord {
    <#
    .SYNOPSIS
        Canonical form of a key chord (or array of chords) for comparison.
    .DESCRIPTION
        "Shift+Ctrl+F" and "ctrl+shift+f" are the same binding to Windows
        Terminal; modifiers are sorted and lowercased so they compare equal.
        An array of chords normalizes each and joins them sorted, so entry
        order never matters.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $Keys
    )
    $modifiers = 'alt', 'ctrl', 'shift', 'win'
    $chords = @($Keys) | ForEach-Object {
        $tokens = "$_".ToLowerInvariant().Split('+') |
            ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $mods = @($tokens | Where-Object { $_ -in $modifiers } | Sort-Object)
        $rest = @($tokens | Where-Object { $_ -notin $modifiers })
        (@($mods) + @($rest)) -join '+'
    }
    (@($chords) | Sort-Object) -join '|'
}

function Merge-WtProfileDefaults {
    <#
    .SYNOPSIS
        Overlay profile defaults (font, scheme, opacity, ...) onto
        profiles.defaults, upgrading the legacy bare-array "profiles" layout.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,
        [Parameter(Mandatory)]
        [hashtable]$Defaults
    )
    $profiles = $Settings['profiles']
    if ($null -eq $profiles) {
        $profiles = [ordered]@{}
        $Settings['profiles'] = $profiles
    }
    elseif ($profiles -is [System.Collections.IList]) {
        # pre-1.0 layout: "profiles" was the list itself
        $profiles = [ordered]@{ list = @($profiles) }
        $Settings['profiles'] = $profiles
    }
    if ($null -eq $profiles['defaults']) { $profiles['defaults'] = [ordered]@{} }
    foreach ($k in $Defaults.Keys) { $profiles['defaults'][$k] = $Defaults[$k] }
    $Settings
}

function Set-WtColorScheme {
    <#
    .SYNOPSIS
        Upsert a color scheme by name, leaving every other scheme untouched.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory transform; file IO and ShouldProcess live in the installer.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,
        [Parameter(Mandatory)]
        [hashtable]$Scheme
    )
    if ($null -eq $Settings['schemes']) { $Settings['schemes'] = @() }
    $Settings['schemes'] = @(
        @($Settings['schemes']) | Where-Object { $_['name'] -ne $Scheme['name'] }
    ) + $Scheme
    $Settings
}

function Merge-WtKeybindings {
    <#
    .SYNOPSIS
        Claim our key chords in both binding stores Windows Terminal reads.
    .DESCRIPTION
        Removes any existing binding for a chord we ship — from the legacy
        "keybindings" array AND from "actions" entries that carry keys — then
        appends our bindings to "keybindings" (which every WT version honors).
        An "actions" entry with an id keeps its action definition (only the
        chord is removed); an inline no-id binding is superseded and dropped.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,
        [Parameter(Mandatory)]
        [array]$Keybindings
    )
    $claimed = @{}
    foreach ($kb in $Keybindings) {
        $claimed[(Get-WtNormalizedChord $kb['keys'])] = $true
    }

    if ($null -eq $Settings['keybindings']) { $Settings['keybindings'] = @() }
    $Settings['keybindings'] = @(
        @($Settings['keybindings']) | Where-Object {
            -not $_.Contains('keys') -or
            -not $claimed.ContainsKey((Get-WtNormalizedChord $_['keys']))
        }
    ) + @($Keybindings)

    if ($Settings.Contains('actions')) {
        $kept = foreach ($action in @($Settings['actions'])) {
            if ($action.Contains('keys') -and
                $claimed.ContainsKey((Get-WtNormalizedChord $action['keys']))) {
                if ($action.Contains('id')) {
                    $action.Remove('keys')
                    $action
                }
                # no id: binding-only entry, superseded — drop it
            }
            else { $action }
        }
        $Settings['actions'] = @($kept)
    }
    $Settings
}

function Set-WtDefaultProfile {
    <#
    .SYNOPSIS
        Point defaultProfile at the PowerShell 7 profile, if one exists.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory transform; file IO and ShouldProcess live in the installer.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings
    )
    $profiles = $Settings['profiles']
    $list = if ($profiles -is [System.Collections.IDictionary]) { $profiles['list'] } else { $profiles }
    $ps7 = @($list) | Where-Object {
        $_ -and $_['source'] -eq 'Windows.Terminal.PowershellCore'
    } | Select-Object -First 1
    if ($ps7 -and $ps7['guid']) { $Settings['defaultProfile'] = $ps7['guid'] }
    $Settings
}

function Merge-WtSettings {
    <#
    .SYNOPSIS
        The full glowup merge: profile defaults + color scheme + keybindings
        + PS7 default profile + scrollback size, preserving everything else.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,
        [Parameter(Mandatory)]
        [hashtable]$Defaults,
        [Parameter(Mandatory)]
        [hashtable]$Scheme,
        [Parameter(Mandatory)]
        [array]$Keybindings,
        [int]$HistorySize = 20000
    )
    $Settings = Merge-WtProfileDefaults -Settings $Settings -Defaults $Defaults
    $Settings = Set-WtColorScheme -Settings $Settings -Scheme $Scheme
    $Settings = Merge-WtKeybindings -Settings $Settings -Keybindings $Keybindings
    $Settings = Set-WtDefaultProfile -Settings $Settings
    $Settings['historySize'] = $HistorySize
    $Settings
}

Export-ModuleMember -Function @(
    'ConvertFrom-WtJson'
    'ConvertTo-WtJson'
    'Get-WtSettingsPath'
    'Get-WtNormalizedChord'
    'Merge-WtProfileDefaults'
    'Set-WtColorScheme'
    'Merge-WtKeybindings'
    'Set-WtDefaultProfile'
    'Merge-WtSettings'
)
