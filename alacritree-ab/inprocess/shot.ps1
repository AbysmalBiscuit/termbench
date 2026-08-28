# Not part of the measurement: captures the primary screen after a window has
# had time to fill, so a shader change that draws nothing is visible before its
# numbers are believed.
param([string]$Binary, [string]$Mode = 'percellbg', [int]$Seconds = 25, [string]$Out)
$here = $PSScriptRoot
$env:APPDATA = Join-Path $here 'appdata'
$env:LOCALAPPDATA = Join-Path $here 'local'
$env:ALACRITREE_AB_MODE = $Mode
$p = Start-Process -FilePath $Binary -PassThru
Start-Sleep -Seconds $Seconds
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
Write-Host "saved $Out"
