# Pester 5 suite for the WtSettings merge engine. Pure JSON-in/JSON-out, so it
# runs anywhere pwsh runs — including Linux CI. Run locally with:
#   Invoke-Pester -Path ./tests
BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'modules' 'WtSettings') -Force
    $script:fixtures = Join-Path $PSScriptRoot 'fixtures'
    $script:repoRoot = Join-Path $PSScriptRoot '..'

    # The real payloads the installer ships
    $script:shipDefaults = Get-Content (Join-Path $repoRoot 'windows-terminal' 'profile-defaults.json') -Raw | ConvertFrom-WtJson
    $script:shipScheme   = Get-Content (Join-Path $repoRoot 'themes' 'tokyo-night' 'color-scheme.json') -Raw | ConvertFrom-WtJson
    $script:shipKeys     = @(Get-Content (Join-Path $repoRoot 'windows-terminal' 'keybindings.json') -Raw | ConvertFrom-Json -AsHashtable)

    function Get-ModernFixture {
        Get-Content (Join-Path $script:fixtures 'modern-settings.jsonc') -Raw | ConvertFrom-WtJson
    }
    function Get-LegacyFixture {
        Get-Content (Join-Path $script:fixtures 'legacy-settings.json') -Raw | ConvertFrom-WtJson
    }
}

Describe 'ConvertFrom-WtJson' {
    It 'parses JSONC with comments and trailing commas' {
        $s = Get-ModernFixture
        $s | Should -Not -BeNullOrEmpty
        $s['copyOnSelect'] | Should -BeFalse
        $s['profiles']['defaults']['font']['face'] | Should -Be 'Consolas'
    }

    It 'round-trips through ConvertTo-WtJson without losing structure' {
        $s = Get-ModernFixture
        $again = ConvertTo-WtJson -Settings $s | ConvertFrom-WtJson
        $again['profiles']['list'].Count | Should -Be 2
        $again['schemes'].Count | Should -Be 2
        $again['defaultProfile'] | Should -Be $s['defaultProfile']
    }
}

Describe 'Get-WtNormalizedChord' {
    It 'treats modifier order and case as irrelevant' {
        Get-WtNormalizedChord 'Shift+Ctrl+F' | Should -Be (Get-WtNormalizedChord 'ctrl+shift+f')
    }

    It 'distinguishes genuinely different chords' {
        Get-WtNormalizedChord 'ctrl+shift+f' | Should -Not -Be (Get-WtNormalizedChord 'ctrl+f')
        Get-WtNormalizedChord 'alt+1' | Should -Not -Be (Get-WtNormalizedChord 'alt+2')
    }

    It 'normalizes chord arrays regardless of element order' {
        Get-WtNormalizedChord @('ctrl+c', 'ctrl+insert') |
            Should -Be (Get-WtNormalizedChord @('CTRL+INSERT', 'Ctrl+C'))
    }

    It 'keeps the non-modifier key position stable' {
        Get-WtNormalizedChord 'win+`' | Should -Be 'win+`'
        Get-WtNormalizedChord 'ctrl+alt+up' | Should -Be 'alt+ctrl+up'
    }
}

Describe 'Merge-WtProfileDefaults' {
    It 'creates profiles.defaults from nothing' {
        $s = [ordered]@{}
        $s = Merge-WtProfileDefaults -Settings $s -Defaults ([ordered]@{ opacity = 88 })
        $s['profiles']['defaults']['opacity'] | Should -Be 88
    }

    It 'overlays onto existing defaults, keeping keys we do not ship' {
        $s = Get-ModernFixture
        $s = Merge-WtProfileDefaults -Settings $s -Defaults $script:shipDefaults
        $s['profiles']['defaults']['font']['face'] | Should -Be 'CaskaydiaCove NF'
        $s['profiles']['defaults']['colorScheme'] | Should -Be 'Tokyo Night'
        # the user's unrelated top-level key survives
        $s['copyOnSelect'] | Should -BeFalse
    }

    It 'upgrades the legacy bare-array profiles layout in place' {
        $s = Get-LegacyFixture
        $s['profiles'] -is [System.Collections.IList] | Should -BeTrue
        $s = Merge-WtProfileDefaults -Settings $s -Defaults $script:shipDefaults
        $s['profiles'] -is [System.Collections.IDictionary] | Should -BeTrue
        $s['profiles']['list'].Count | Should -Be 1
        $s['profiles']['list'][0]['name'] | Should -Be 'Windows PowerShell'
        $s['profiles']['defaults']['colorScheme'] | Should -Be 'Tokyo Night'
    }
}

Describe 'Set-WtColorScheme' {
    It 'replaces a same-name scheme instead of duplicating it' {
        $s = Get-ModernFixture
        $s = Set-WtColorScheme -Settings $s -Scheme $script:shipScheme
        $tokyo = @($s['schemes'] | Where-Object { $_['name'] -eq 'Tokyo Night' })
        $tokyo.Count | Should -Be 1
        $tokyo[0]['background'] | Should -Be '#1A1B26'
    }

    It 'preserves the user''s other schemes' {
        $s = Get-ModernFixture
        $s = Set-WtColorScheme -Settings $s -Scheme $script:shipScheme
        @($s['schemes'] | Where-Object { $_['name'] -eq 'My Custom Scheme' }).Count | Should -Be 1
    }

    It 'creates the schemes array when missing' {
        $s = [ordered]@{}
        $s = Set-WtColorScheme -Settings $s -Scheme $script:shipScheme
        @($s['schemes']).Count | Should -Be 1
    }
}

Describe 'Merge-WtKeybindings' {
    BeforeEach {
        $script:s = Get-ModernFixture
        $script:s = Merge-WtKeybindings -Settings $script:s -Keybindings $script:shipKeys
    }

    It 'appends every shipped binding' {
        foreach ($kb in $script:shipKeys) {
            $hits = @($script:s['keybindings'] | Where-Object {
                (Get-WtNormalizedChord $_['keys']) -eq (Get-WtNormalizedChord $kb['keys'])
            })
            $hits.Count | Should -Be 1 -Because "chord '$($kb['keys'])' must be bound exactly once"
        }
    }

    It 'evicts a conflicting legacy binding even when the case differs (ALT+2)' {
        $alt2 = @($script:s['keybindings'] | Where-Object {
            (Get-WtNormalizedChord $_['keys']) -eq 'alt+2'
        })
        $alt2.Count | Should -Be 1
        $alt2[0]['command']['action'] | Should -Be 'switchToTab'
    }

    It 'keeps unrelated legacy bindings (alt+f4)' {
        @($script:s['keybindings'] | Where-Object { $_['command'] -eq 'closeWindow' }).Count | Should -Be 1
    }

    It 'strips only the chord from a conflicting actions entry that has an id' {
        $hi = @($script:s['actions'] | Where-Object { $_['id'] -eq 'User.sendHi' })
        $hi.Count | Should -Be 1 -Because 'the id-addressable action must survive'
        $hi[0].Contains('keys') | Should -BeFalse -Because 'we claimed alt+1'
    }

    It 'drops a conflicting inline actions binding with no id (shift+ctrl+f vs ctrl+shift+f)' {
        @($script:s['actions'] | Where-Object { $_['command'] -eq 'openTabColorPicker' }).Count | Should -Be 0
    }

    It 'leaves non-conflicting actions untouched' {
        $paste = @($script:s['actions'] | Where-Object { $_['id'] -eq 'User.paste' })
        $paste.Count | Should -Be 1
        $paste[0]['keys'] | Should -Be 'ctrl+insert'
    }

    It 'releases ctrl+v: the user''s text-paste binding is evicted for the unbound entry' {
        $ctrlV = @($script:s['keybindings'] | Where-Object {
            (Get-WtNormalizedChord $_['keys']) -eq 'ctrl+v'
        })
        $ctrlV.Count | Should -Be 1
        $ctrlV[0]['command'] | Should -Be 'unbound'
    }

    It 'evicts a legacy binding whose keys are an array (legacy fixture find)' {
        $legacy = Get-LegacyFixture
        $legacy = Merge-WtKeybindings -Settings $legacy -Keybindings $script:shipKeys
        $find = @($legacy['keybindings'] | Where-Object {
            (Get-WtNormalizedChord $_['keys']) -eq 'ctrl+shift+f'
        })
        $find.Count | Should -Be 1
        $find[0]['command'] | Should -Be 'find'
        $find[0]['keys'] | Should -Be 'ctrl+shift+f'
    }

    It 'is idempotent — merging twice binds each chord once' {
        $twice = Merge-WtKeybindings -Settings $script:s -Keybindings $script:shipKeys
        foreach ($kb in $script:shipKeys) {
            $hits = @($twice['keybindings'] | Where-Object {
                (Get-WtNormalizedChord $_['keys']) -eq (Get-WtNormalizedChord $kb['keys'])
            })
            $hits.Count | Should -Be 1
        }
    }
}

Describe 'Set-WtDefaultProfile' {
    It 'selects the PowerShell 7 profile when present' {
        $s = Get-ModernFixture
        $s = Set-WtDefaultProfile -Settings $s
        $s['defaultProfile'] | Should -Be '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    }

    It 'leaves defaultProfile alone when PS7 is absent' {
        $s = Get-LegacyFixture
        $before = $s['defaultProfile']
        $s = Set-WtDefaultProfile -Settings $s
        $s['defaultProfile'] | Should -Be $before
    }
}

Describe 'Merge-WtSettings (end to end)' {
    BeforeAll {
        $script:merged = Merge-WtSettings -Settings (Get-ModernFixture) `
            -Defaults $script:shipDefaults -Scheme $script:shipScheme -Keybindings $script:shipKeys
    }

    It 'applies every layer' {
        $merged['profiles']['defaults']['colorScheme'] | Should -Be 'Tokyo Night'
        @($merged['schemes'] | Where-Object { $_['name'] -eq 'Tokyo Night' }).Count | Should -Be 1
        $merged['defaultProfile'] | Should -Be '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
        $merged['historySize'] | Should -Be 20000
    }

    It 'preserves keys it knows nothing about' {
        $merged['$help'] | Should -Be 'https://aka.ms/terminal-documentation'
        $merged['copyOnSelect'] | Should -BeFalse
        $merged['profiles']['list'][0]['commandline'] | Should -Match 'WindowsPowerShell'
    }

    It 'serializes back to parseable JSON' {
        $json = ConvertTo-WtJson -Settings $merged
        { $json | ConvertFrom-Json -Depth 64 } | Should -Not -Throw
    }

    It 'is idempotent end to end' {
        $again = Merge-WtSettings -Settings $merged `
            -Defaults $script:shipDefaults -Scheme $script:shipScheme -Keybindings $script:shipKeys
        @($again['schemes'] | Where-Object { $_['name'] -eq 'Tokyo Night' }).Count | Should -Be 1
        foreach ($kb in $script:shipKeys) {
            @($again['keybindings'] | Where-Object {
                (Get-WtNormalizedChord $_['keys']) -eq (Get-WtNormalizedChord $kb['keys'])
            }).Count | Should -Be 1
        }
    }
}

Describe 'Shipped payloads are valid' {
    It 'keybindings.json chords are unique after normalization' {
        $chords = $script:shipKeys | ForEach-Object { Get-WtNormalizedChord $_['keys'] }
        ($chords | Sort-Object -Unique).Count | Should -Be $chords.Count
    }

    It 'profile defaults reference the default theme''s scheme' {
        $script:shipDefaults['colorScheme'] | Should -Be $script:shipScheme['name']
    }
}

Describe 'Theme catalog' {
    BeforeAll {
        $script:themeDirs = @(Get-ChildItem (Join-Path $script:repoRoot 'themes') -Directory)
    }

    It 'ships the documented themes' {
        $names = $script:themeDirs.Name | Sort-Object
        $names | Should -Contain 'tokyo-night'
        $names | Should -Contain 'catppuccin-mocha'
        $names | Should -Contain 'gruvbox-dark'
        $names | Should -Contain 'nord'
    }

    It 'every theme carries all three files' {
        foreach ($dir in $script:themeDirs) {
            foreach ($f in 'color-scheme.json', 'two-line.omp.json', 'psreadline-colors.json') {
                Join-Path $dir.FullName $f | Should -Exist -Because "$($dir.Name) must ship $f"
            }
        }
    }

    It 'every scheme defines the full palette, cursor, and selection colors' {
        foreach ($dir in $script:themeDirs) {
            $scheme = Get-Content (Join-Path $dir.FullName 'color-scheme.json') -Raw | ConvertFrom-WtJson
            foreach ($k in 'background', 'foreground', 'cursorColor', 'selectionBackground',
                           'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
                           'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue',
                           'brightPurple', 'brightCyan', 'brightWhite') {
                $scheme[$k] | Should -Match '^#[0-9A-Fa-f]{6}$' -Because "$($dir.Name) scheme must define $k"
            }
        }
    }

    It 'scheme names are unique across themes' {
        $names = foreach ($dir in $script:themeDirs) {
            (Get-Content (Join-Path $dir.FullName 'color-scheme.json') -Raw | ConvertFrom-WtJson)['name']
        }
        ($names | Sort-Object -Unique).Count | Should -Be $names.Count
    }

    It 'every prompt theme parses and keeps the two-line layout' {
        foreach ($dir in $script:themeDirs) {
            $omp = Get-Content (Join-Path $dir.FullName 'two-line.omp.json') -Raw | ConvertFrom-Json -AsHashtable
            @($omp['blocks']).Count | Should -Be 2 -Because "$($dir.Name) prompt must stay two-line"
            $omp['transient_prompt'] | Should -Not -BeNullOrEmpty
        }
    }

    It 'every psreadline palette defines every color the profile reads' {
        foreach ($dir in $script:themeDirs) {
            $colors = Get-Content (Join-Path $dir.FullName 'psreadline-colors.json') -Raw | ConvertFrom-Json -AsHashtable
            foreach ($k in 'Command', 'Parameter', 'Operator', 'Variable', 'String', 'Number',
                           'Type', 'Comment', 'Keyword', 'Error', 'InlinePrediction',
                           'ListPrediction', 'Default') {
                $colors['psreadline'][$k] | Should -Match '^#[0-9A-Fa-f]{6}$' -Because "$($dir.Name) must define psreadline.$k"
            }
            foreach ($k in 'directory', 'error', 'warning', 'tableHeader') {
                $colors['style'][$k] | Should -Match '^#[0-9A-Fa-f]{6}$' -Because "$($dir.Name) must define style.$k"
            }
        }
    }
}
