# Not part of the measurement: captures the bench window after it has had time
# to fill, so a shader change that draws differently is visible before its
# numbers are believed.
#
# Captures the window's own composited surface via PrintWindow, never the
# desktop. Reading the screen would pick up whatever overlaps the window and
# would need it raised and positioned, which means fighting whoever is using
# the machine for the monitor it happens to open on.
param([string]$Binary, [string]$Mode = 'static', [int]$Seconds = 20, [string]$Out)
$here = $PSScriptRoot
Remove-Item -Recurse -Force (Join-Path $here 'local') -ErrorAction SilentlyContinue
$run = New-Item -ItemType Directory -Force -Path (Join-Path $here 'local/appdata')
Copy-Item -Recurse -Force (Join-Path $here 'appdata/*') $run
$env:APPDATA = $run.FullName
$env:LOCALAPPDATA = Join-Path $here 'local'
$env:ALACRITREE_AB_MODE = $Mode

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public struct RECT { public int L, T, R, B; }
public class Win {
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  // PW_RENDERFULLCONTENT: ask DWM for the window's own surface rather than a
  // WM_PRINT repaint, which a GL window does not answer.
  public const uint FULL = 0x00000002;
}
'@ -ReferencedAssemblies System.Drawing, System.Drawing.Primitives

$p = Start-Process -FilePath $Binary -PassThru
Start-Sleep -Seconds $Seconds
$p.Refresh()
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { Stop-Process -Id $p.Id -Force; throw 'bench window has no handle' }

$r = New-Object RECT
[Win]::GetClientRect($h, [ref]$r) | Out-Null
$w = $r.R - $r.L
$ht = $r.B - $r.T
$bmp = New-Object System.Drawing.Bitmap $w, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [Win]::PrintWindow($h, $hdc, [Win]::FULL)
$g.ReleaseHdc($hdc)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
Write-Host "saved $Out (${w}x${ht}, PrintWindow=$ok)"
