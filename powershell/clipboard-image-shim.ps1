<#
.SYNOPSIS
    Makes right-click paste work for images in Windows Terminal.

.DESCRIPTION
    Windows Terminal's right-click (and Ctrl+Shift+V) paste only ever inserts
    clipboard TEXT, so a copied screenshot pastes nothing. This watcher fixes
    that at the clipboard layer: when the clipboard holds an image and no text,
    it saves the image to %TEMP%\terminal-pastes\paste-*.png and ADDS the
    quoted path as clipboard text, keeping the image formats intact. Files
    copied in Explorer get their quoted paths added the same way. Text you
    copied yourself is never touched, and nothing leaves the machine.

    The profile starts one instance of this per login session (see the mutex),
    hidden, with your first PowerShell tab. Set GLOWUP_NO_CLIP_SHIM=1 to keep
    it from starting. Saved PNGs older than 7 days are cleaned up on start.

    Detection polls GetClipboardSequenceNumber (one native call, 400 ms apart)
    instead of registering a clipboard listener window — no message pump, and
    the idle cost is unmeasurable. Clipboard access needs STA, which is
    pwsh's default on Windows.
#>
[CmdletBinding()]
param()

if (-not $IsWindows) { exit 0 }

# Single instance per login session; the profile checks this same mutex.
$created = $false
$mutex = [System.Threading.Mutex]::new($true, 'Local\windows-terminal-glowup-clip-shim', [ref]$created)
if (-not $created) { exit 0 }

try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    Add-Type -Namespace GlowupNative -Name Clip -MemberDefinition `
        '[DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();'

    $pasteDir = Join-Path ([IO.Path]::GetTempPath()) 'terminal-pastes'
    if (Test-Path $pasteDir) {
        Get-ChildItem $pasteDir -Filter 'paste-*.png' |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    $last = [GlowupNative.Clip]::GetClipboardSequenceNumber()
    while ($true) {
        Start-Sleep -Milliseconds 400
        $seq = [GlowupNative.Clip]::GetClipboardSequenceNumber()
        if ($seq -eq $last) { continue }
        $last = $seq

        for ($attempt = 0; $attempt -lt 3; $attempt++) {
            try {
                # Text present (the user's own, or ours from a previous pass):
                # leave the clipboard alone.
                if ([System.Windows.Forms.Clipboard]::ContainsText()) { break }

                if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
                    $img = [System.Windows.Forms.Clipboard]::GetImage()
                    if ($null -eq $img) { break }
                    try {
                        $null = New-Item -ItemType Directory -Force -Path $pasteDir
                        $file = Join-Path $pasteDir ('paste-{0:yyyyMMdd-HHmmss-ff}.png' -f (Get-Date))
                        $img.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
                        $data = [System.Windows.Forms.DataObject]::new()
                        $data.SetImage($img)
                        $data.SetText('"' + $file + '"')
                        [System.Windows.Forms.Clipboard]::SetDataObject($data, $true)
                    } finally { $img.Dispose() }
                    # Our own write bumped the sequence; don't react to it.
                    $last = [GlowupNative.Clip]::GetClipboardSequenceNumber()
                }
                elseif ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {
                    $files = [System.Windows.Forms.Clipboard]::GetFileDropList()
                    $quoted = foreach ($f in $files) { '"' + $f + '"' }
                    $data = [System.Windows.Forms.DataObject]::new()
                    $data.SetFileDropList($files)
                    $data.SetText($quoted -join ' ')
                    [System.Windows.Forms.Clipboard]::SetDataObject($data, $true)
                    $last = [GlowupNative.Clip]::GetClipboardSequenceNumber()
                }
                break
            } catch {
                # Clipboard briefly locked by another app; retry.
                Start-Sleep -Milliseconds 80
            }
        }
    }
} finally {
    $mutex.Dispose()
}
