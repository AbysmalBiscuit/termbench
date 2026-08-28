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
#
# Three different paths can draw a cell -- the glyph atlas, the built-in box
# font, and the colour-glyph cache -- and a screen of ASCII exercises only the
# first, so a diff over it cannot see a regression in the other two.
# `osc11` is `static` with the terminal asked to change its background out from
# under the renderer, which is the only way to see whether the paint path reads
# the live palette or the configured one.
if ($mode -eq 'osc11') {
  $esc = [char]27
  $bel = [char]7
  Write-Host "$esc]11;#FF0000$bel" -NoNewline
}

if ($mode -eq 'static' -or $mode -eq 'osc11') {
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  $wide = [Math]::Min($cols, 250)
  $ascii = -join (32..126 | ForEach-Object { [char]$_ })
  # The block the built-in font draws itself rather than reading from a face.
  $box = -join (0x2500..0x257f | ForEach-Object { [char]$_ })
  # Colour emoji come from the glyph cache. U+2753 is the one whose regression
  # started this; the rest spread over single- and multi-colour glyphs.
  $emoji = @(0x1f600, 0x1f680, 0x2753, 0x2705, 0x274c, 0x1f308, 0x26a1, 0x2b50) |
    ForEach-Object { [char]::ConvertFromUtf32($_) }
  # Each emoji covers two cells, and a `Substring` would cut a surrogate pair in
  # half, so the line is grown a whole glyph at a time.
  $emojiLine = ''
  for ($cell = 0; $cell + 2 -le $wide; $cell += 2) {
    $emojiLine += $emoji[($cell / 2) % $emoji.Count]
  }

  # One line short of the window, so the screen holds still instead of scrolling
  # its first row off.
  $lines = @()
  1..3 | ForEach-Object { $lines += ($box * 4).Substring(0, $wide) }
  1..3 | ForEach-Object { $lines += $emojiLine }
  ($rows - 1 - $lines.Count)..1 | ForEach-Object {
    $lines += ($ascii * 3).Substring(0, $wide)
  }
  $lines | ForEach-Object { Write-Host $_ }
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
