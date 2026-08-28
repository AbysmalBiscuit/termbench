# Drives one phase of the decoration-gate A/B inside a live window.
#
# ALACRITREE_AB_MODE picks the sgrtest workload: `plain` leaves the grid
# undecorated, so the gated arm skips the pass and the always arm draws it;
# `underline` decorates every cell, where both arms draw and the pair is a
# null control on the instrument itself.
$here = $PSScriptRoot
$bench = Split-Path -Parent (Split-Path -Parent $here)
$mode = $env:ALACRITREE_AB_MODE
if (-not $mode) { $mode = 'plain' }
New-Item -ItemType Directory -Force -Path "$here/out" | Out-Null

# Let the window finish its first paints before the grid is read; a size taken
# mid-startup describes a window about to be resized.
Start-Sleep -Seconds 3
$cols = 80
$rows = 24
try { $cols = [Console]::WindowWidth; $rows = [Console]::WindowHeight } catch { }
Set-Content -LiteralPath "$here/out/$mode.grid" -Value "${cols}x${rows}"

# `static` is not a measurement: it paints one fixed screen and holds it, so
# two builds can be captured and their pixels compared.
if ($mode -eq 'static') {
  $text = -join (32..126 | ForEach-Object { [char]$_ })
  1..$rows | ForEach-Object { Write-Host ($text * 3).Substring(0, [Math]::Min($cols, 250)) }
  while ($true) { Start-Sleep -Seconds 5 }
}

# Repeat until the driver kills the window: the report fires every 240 frames
# and a useful comparison wants several windows per arm, which one sgrtest run
# does not reliably reach.
$pass = 0
while ($true) {
  $pass++
  & "$bench/sgrtest.exe" $mode 4000 $cols $rows "$here/out/$mode-$pass.txt" 8 binary
}
