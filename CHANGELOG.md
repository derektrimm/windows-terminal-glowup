# Changelog

## Unreleased

### Added
- `modules/WtSettings` — the settings.json merge as a standalone module:
  JSONC parsing, profile-defaults overlay, color-scheme upsert, and
  keybinding deduplication by normalized chord.
- Test suite under `tests/` (Pester); runs on any OS with PowerShell 7.
- CI: PSScriptAnalyzer + Pester on every push and pull request.
- `install.ps1 -WhatIf` — dry run; prints every change without making any.
- `install.ps1 -Verify` — health check; reports each component and exits
  non-zero if a core piece is missing.
- `uninstall.ps1` — restores the `*.bak-glowup` backups and removes the
  prompt theme. `-WhatIf` supported.

### Changed
- Windows Terminal Preview and unpackaged (Scoop/Chocolatey) installs are
  now configured too, each with its own backup.
- Keybinding conflicts are evicted from the modern `actions` array as well
  as the legacy `keybindings` array. An `actions` entry with an `id` keeps
  its action and loses only the chord; an inline no-id binding is replaced.
- Chord comparison ignores case and modifier order (`Shift+Ctrl+F` equals
  `ctrl+shift+f`), including chord arrays.
- The pre-1.0 layout where `profiles` is a bare array is upgraded in place
  instead of breaking the merge.

## 2026-08-15

### Fixed
- winget failures now stop the installer with the failing package and exit
  code instead of passing silently ("already installed" still counts as
  success, so re-runs stay quiet).

### Changed
- README preview image now shows the prompt, `ll` icons + git column, and a
  `delta` side-by-side diff, rendered from this repo's theme and configs.

## 2026-06-20

- First release: installer, PowerShell 7 profile, Oh My Posh two-line theme,
  Tokyo Night scheme, Windows Terminal defaults + keybindings, optional
  delta git config.
