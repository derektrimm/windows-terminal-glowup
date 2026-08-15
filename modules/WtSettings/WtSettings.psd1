@{
    RootModule        = 'WtSettings.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '5f9a2c1e-8d4b-4c6a-9e3f-2b7d1a0c8e5d'
    Author            = 'Derek Trimm'
    Description       = 'Merge engine for Windows Terminal settings.json: JSONC parsing, profile defaults, color scheme upsert, and chord-normalized keybinding deduplication across both the legacy keybindings and modern actions arrays.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('windows-terminal', 'settings', 'jsonc', 'merge')
            LicenseUri = 'https://github.com/derektrimm/windows-terminal-glowup/blob/main/LICENSE'
            ProjectUri = 'https://github.com/derektrimm/windows-terminal-glowup'
        }
    }
}
