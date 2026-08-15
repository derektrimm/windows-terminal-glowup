# windows-terminal-glowup

[![CI](https://github.com/derektrimm/windows-terminal-glowup/actions/workflows/ci.yml/badge.svg)](https://github.com/derektrimm/windows-terminal-glowup/actions/workflows/ci.yml)

Turn a stock Windows Terminal + PowerShell into something you actually enjoy looking at — a themed two-line prompt, file icons, predictive autocomplete, a matching color scheme with transparency, and a set of modern CLI tools. One script, ~2 minutes.

> **Theme:** Tokyo Night · **Prompt:** Oh My Posh (two-line) · **Font:** CaskaydiaCove Nerd Font

![The two-line prompt, ll with file icons and git status, and a delta side-by-side diff](assets/preview.png)

<sup>Rendered straight from this repo's theme and configs: the two-line prompt (path · git status · run time), `ll` with icons + git column, and a `delta` side-by-side diff.</sup>

---

## Quick start

You need **Windows 10/11** with **Windows Terminal** and **winget** (both ship on Windows 11). Then:

```powershell
git clone https://github.com/derektrimm/windows-terminal-glowup.git
cd windows-terminal-glowup
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Want syntax-highlighted `git diff` too? Add `-ConfigureGitDelta`:

```powershell
pwsh -ExecutionPolicy Bypass -File .\install.ps1 -ConfigureGitDelta
```

When it finishes: **fully close Windows Terminal and open a new tab.** (The look only applies to newly opened tabs.) If you see ▯ boxes instead of icons, set the font to **CaskaydiaCove NF** in Settings → Defaults → Appearance.

The installer is **safe to re-run** and backs up anything it replaces (`*.bak-glowup`).

Three more switches:

```powershell
pwsh -File .\install.ps1 -WhatIf     # dry run — print every change, make none
pwsh -File .\install.ps1 -Verify     # health check — what's installed, what's missing
pwsh -File .\uninstall.ps1           # put the backups back (also takes -WhatIf)
```

---

## What you get

### Look & feel
- **Oh My Posh** two-line prompt (path · git branch/status · Node/Python version · run time), green `❯` that turns red on errors
- **CaskaydiaCove Nerd Font** so all the glyphs render
- **Terminal-Icons** — file-type icons in `ls`/`dir`
- **Predictive autocomplete** — a dropdown of suggestions from history + a predictor plugin (PSReadLine)
- **Tokyo Night** color scheme, subtle acrylic transparency, comfy padding, block cursor
- **Visible scrollbar with command marks** — a tick per command so you can see/jump through your scrollback
- **Images in the terminal** — paste a copied screenshot with **right-click, `Ctrl+V`, or `Ctrl+Shift+V`** and its path lands at the prompt (saved as a PNG); drag a file onto the window to get its path; `icat` renders any of them inline (sixels on Windows Terminal 1.22+, unicode blocks elsewhere). [How it works](#pasting-images)

### Modern CLI tools (installed via winget)
| You type | Tool | What it does |
|---|---|---|
| `ls` / `ll` / `la` / `lt` | [eza](https://github.com/eza-community/eza) | listings with icons + git status |
| `cat` | [bat](https://github.com/sharkdp/bat) | syntax-highlighted file viewer |
| `fd` | [fd](https://github.com/sharkdp/fd) | fast, friendly `find` |
| `rg` | [ripgrep](https://github.com/BurntSushi/ripgrep) | blazing-fast search |
| `git diff` | [delta](https://github.com/dandavison/delta) | side-by-side highlighted diffs *(opt-in)* |
| `lg` | [lazygit](https://github.com/jesseduffield/lazygit) | full git TUI |
| `btop` | [btop](https://github.com/aristocratos/btop4win) | gorgeous resource monitor |
| `cd` | [zoxide](https://github.com/ajeetdsouza/zoxide) | smart `cd` that learns your dirs |
| `Ctrl+R` | [fzf](https://github.com/junegunn/fzf) + PSFzf | fuzzy history / file search |
| `tldr` | [tealdeer](https://github.com/tealdeer-rs/tealdeer) | example-first command help |
| `sudo` | [gsudo](https://github.com/gerardog/gsudo) | elevate a single command |
| `icat` | [chafa](https://github.com/hpjansson/chafa) | images rendered in the terminal |

### Shell helpers (in the profile)
`nt <name>` open a project in a **new tab** · `pj <name>` jump to a project · `gs` `gd` `gds` `gl` `lg` git shortcuts · `reload` re-source the profile · `..` / `...` up directories.

---

## Keybindings (Windows Terminal)

| Keys | Action |
|---|---|
| `Alt+1` … `Alt+9` | Jump to tab 1–9 |
| `Ctrl+Shift+F` | Find / search scrollback |
| `Ctrl+Alt+↑` / `↓` | Jump to previous / next command mark |
| `Ctrl+Alt+M` | Drop a scrollbar mark |
| `Ctrl+Alt+B` | Broadcast typing to all panes |
| `Alt+Shift+V` / `Alt+Shift+S` | Split pane vertical / horizontal |
| `Alt+Shift+U` | Duplicate pane |
| `Alt+←↑↓→` / `Alt+Shift+←↑↓→` | Move focus / resize panes |
| `Shift+F11` | Focus mode (hide tabs/title) |
| <code>Win+&#96;</code> | Quake-style drop-down terminal |
| `Alt+K` | Clear screen |
| `Ctrl+V` / right-click / `Ctrl+Shift+V` | Paste — a copied **image** lands as the path of a saved PNG; text pastes as usual |

`Ctrl+V` is released from Windows Terminal to the shell so PowerShell can handle images directly; `Ctrl+Shift+V`, `Shift+Insert`, and right-click keep the terminal's text paste in every tab — which pastes image paths too, thanks to the clipboard shim below.

## Pasting images

Windows Terminal's own paste (right-click, `Ctrl+Shift+V`) only ever inserts clipboard *text*, and it offers no hook to change that — so a copied screenshot normally pastes nothing. Two pieces fix it:

- **In PowerShell tabs, `Ctrl+V` handles images itself** (a PSReadLine handler): a clipboard image is saved to `%TEMP%\terminal-pastes\paste-*.png` and its quoted path inserted; files copied in Explorer insert their quoted paths; text pastes normally. Works with no background process.
- **Everywhere else — including right-click, and cmd/WSL tabs — a clipboard shim makes the terminal's text paste work for images.** `clipboard-image-shim.ps1` (installed next to your profile, one hidden instance per login, started with your first PowerShell tab) watches the clipboard sequence number; when the clipboard holds an image and *no text*, it saves the PNG and **adds** the path as clipboard text alongside the image. Apps that prefer images (Word, Paint, browsers) still paste the image; the terminal pastes the path.

The shim never replaces text you copied, reads nothing but the clipboard, sends nothing anywhere, and is ~90 lines you can read. Saved PNGs are cleaned up after 7 days. Disable it with `GLOWUP_NO_CLIP_SHIM=1` (PowerShell `Ctrl+V` image paste keeps working without it); `uninstall.ps1` stops and removes it.

---

## What's in here

```
install.ps1                         one-command setup (idempotent, backs up; -WhatIf, -Verify)
uninstall.ps1                       restores the backups, removes the theme
powershell/
  Microsoft.PowerShell_profile.ps1  the profile (prompt, aliases, helpers)
oh-my-posh/
  two-line.omp.json                 the Oh My Posh theme
windows-terminal/
  color-scheme.tokyo-night.json     the color scheme
  profile-defaults.json             font / opacity / scrollbar defaults
  keybindings.json                  the keybindings above
git/
  delta.gitconfig                   optional delta diff config
modules/WtSettings/                 the settings.json merge (see below)
tests/                              Pester suite for the merge
```

Prefer to install by hand or cherry-pick? Each file is standalone — copy the theme to `%LOCALAPPDATA%\oh-my-posh\themes\`, the profile to your `$PROFILE`, and merge the `windows-terminal/*.json` pieces into your `settings.json`.

## How the settings merge works

Windows Terminal owns `settings.json`, so the installer edits it as a guest. The
merge lives in `modules/WtSettings` as pure functions over the parsed file:

- **JSONC in, your keys preserved.** Comments and trailing commas parse; keys
  the installer knows nothing about pass through untouched. The pre-1.0 layout
  where `profiles` is a bare array is upgraded in place.
- **Schemes are upserted by name.** Your own color schemes stay; only an
  existing "Tokyo Night" entry is replaced.
- **A key chord is claimed exactly once.** Conflicting bindings are removed
  from both the legacy `keybindings` array and the modern `actions` array,
  comparing normalized chords (`Shift+Ctrl+F` equals `ctrl+shift+f`). An
  `actions` entry with an `id` keeps its action and loses only the chord.
- **Every real settings file is handled** — stable, Preview, and unpackaged
  (Scoop/Chocolatey) installs — each backed up to `settings.json.bak-glowup`
  before writing.

Because the merge never touches the filesystem itself, the whole thing is unit
tested (`tests/`, Pester) on any OS with PowerShell 7:

```powershell
Invoke-Pester -Path ./tests
```

CI runs the suite plus PSScriptAnalyzer on every push and pull request.

---

## Customizing

- **Less/more transparency:** change `opacity` (0–100) in `windows-terminal/profile-defaults.json`, or hold `Ctrl+Shift` and scroll in the terminal.
- **No startup banner:** comment out the `fastfetch` line near the bottom of the profile.
- **Different prompt segments/colors:** edit `oh-my-posh/two-line.omp.json` (see the [Oh My Posh docs](https://ohmyposh.dev/docs)).
- **Another theme:** browse [windowsterminalthemes.dev](https://windowsterminalthemes.dev) and swap the scheme.

## Undo

```powershell
pwsh -File .\uninstall.ps1
```

restores your previous `$PROFILE` and each Windows Terminal `settings.json` from the `*.bak-glowup` backups the installer made, and removes the prompt theme. Installed tools, modules, and the font are left alone (the header of `uninstall.ps1` lists the removal one-liners). The backups sit right next to the originals, so renaming them back by hand works too.

---

## Credits

Built on the work of [Oh My Posh](https://ohmyposh.dev), [Nerd Fonts](https://www.nerdfonts.com), [Terminal-Icons](https://github.com/devblackops/Terminal-Icons), [PSReadLine](https://github.com/PowerShell/PSReadLine), the [Tokyo Night](https://github.com/enkia/tokyo-night-vscode-theme) palette, and the excellent CLI tools linked above. MIT licensed — use it, fork it, share it.
