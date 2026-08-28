# Drives one phase of the decoration-gate A/B inside a live window.
#
# ALACRITREE_DECOAB_MODE picks the sgrtest workload: `plain` leaves the grid
# undecorated, so the gated arm skips the pass and the always arm draws it;
# `underline` decorates every cell, where both arms draw and the pair is a
# null control on the instrument itself.
$here = $PSScriptRoot
$bench = Split-Path -Parent (Split-Path -Parent $here)
$mode = $env:ALACRITREE_DECOAB_MODE
if (-not $mode) { $mode = 'plain' }
New-Item -ItemType Directory -Force -Path "$here/out" | Out-Null

# Let the window finish its first paints before the grid is read; a size taken
# mid-startup describes a window about to be resized.
Start-Sleep -Seconds 3
$cols = 80
$rows = 24
try { $cols = [Console]::WindowWidth; $rows = [Console]::WindowHeight } catch { }
Set-Content -LiteralPath "$here/out/$mode.grid" -Value "${cols}x${rows}"

# Repeat until the driver kills the window: the report fires every 240 frames
# and a useful comparison wants several windows per arm, which one sgrtest run
# does not reliably reach.
$pass = 0
while ($true) {
  $pass++
  & "$bench/sgrtest.exe" $mode 4000 $cols $rows "$here/out/$mode-$pass.txt" 8 binary
}
