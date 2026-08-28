# Runs inside one benchmark window as the session's shell, driving three
# instruments against the same terminal in one launch:
#
#   termbench   whole-terminal throughput, the headline numbers
#   sgrtest     varies attribute density, so `underline` drives the decoration
#               path while `percell` holds the byte count fixed beside it
#   scrolltest  isolates scrolling from raw byte volume
#
# stdout stays attached to the terminal, which is the thing being measured;
# every instrument reports through its own result file instead. Those are folded
# into one table at ALACRITREE_AB_OUT so the analysis reads a single format.

$bench = Split-Path -Parent $PSScriptRoot
$results = Join-Path $PSScriptRoot 'results'
$log = Join-Path $results 'round.log'

function Note($msg) {
  Add-Content -LiteralPath $log -Value ("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $msg)
}

$out = $env:ALACRITREE_AB_OUT
if (-not $out) { Note 'no out path; idling'; while ($true) { Start-Sleep -Seconds 5 } }

# The window respawns a session when its shell exits, so without this the
# benchmark would loop and overwrite the result the driver is about to read.
if (Test-Path -LiteralPath "$out.done") {
  Note 'result already written; idling until the driver kills the window'
  while ($true) { Start-Sleep -Seconds 5 }
}

$tmp = "$out.parts"
Remove-Item -LiteralPath $tmp -Recurse -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# Let the window finish its first paints, and the driver finish pinning its
# geometry, before anything is measured. The grid has to be read after that
# settles or it describes a window that is about to be resized.
Start-Sleep -Seconds 3

# scrolltest and sgrtest paint a grid of a size they are told, so they need the
# terminal's real one; termbench always writes 80x24 regardless.
$cols = 80
$rows = 24
try {
  $cols = [Console]::WindowWidth
  $rows = [Console]::WindowHeight
} catch { }
if ($cols -lt 20) { $cols = 80 }
if ($rows -lt 10) { $rows = 24 }
Note "grid ${cols}x${rows}, pid $PID"

# Recorded beside the results so a round that painted a different grid than the
# rest is caught in the analysis rather than averaged in silently.
Set-Content -LiteralPath "$out.grid" -Value "${cols}x${rows}"

$rows_out = New-Object System.Collections.Generic.List[string]

# One `key=value ...` line is what sgrtest and scrolltest both write.
function Read-KeyValues($path) {
  $kv = @{}
  foreach ($tok in ((Get-Content -LiteralPath $path) -split '\s+')) {
    $p = $tok -split '=', 2
    if ($p.Count -eq 2) { $kv[$p[0]] = $p[1] }
  }
  return $kv
}

# --- termbench: name, seconds, bytes, gbs per test ------------------------
$tb = "$tmp/termbench.tsv"
Note 'termbench normal'
& "$bench/termbench_ab.exe" normal -out $tb
if (Test-Path -LiteralPath $tb) {
  foreach ($line in Get-Content -LiteralPath $tb) {
    $f = $line -split "`t"
    if ($f.Count -ge 4) { $rows_out.Add(("tb.{0}`t{1}`t{2}`t{3}" -f $f[0], $f[1], $f[2], $f[3])) }
  }
} else { Note 'termbench wrote no result' }

# --- sgrtest: attribute density at a fixed screen count -------------------
foreach ($mode in @('plain', 'percell', 'percellbg', 'underline')) {
  $f = "$tmp/sgr-$mode.txt"
  Note "sgrtest $mode"
  & "$bench/sgrtest.exe" $mode 2000 $cols $rows $f 8 binary
  if (Test-Path -LiteralPath $f) {
    $kv = Read-KeyValues $f
    $rows_out.Add(("sg.{0}`t{1}`t{2}`t{3}" -f $mode, $kv['seconds'], $kv['bytes'], $kv['gbs']))
  } else { Note "sgrtest $mode wrote no result" }
}

# --- scrolltest: scrolling vs the same bytes repainted in place -----------
foreach ($mode in @('scroll', 'noscroll')) {
  $f = "$tmp/scroll-$mode.txt"
  Note "scrolltest $mode"
  & "$bench/scrolltest_ab.exe" $mode 512 $cols $rows $f 1 binary
  if (Test-Path -LiteralPath $f) {
    $kv = Read-KeyValues $f
    $rows_out.Add(("sc.{0}`t{1}`t{2}`t{3}" -f $mode, $kv['seconds'], $kv['bytes'], $kv['gbs']))
  } else { Note "scrolltest $mode wrote no result" }
}

Set-Content -LiteralPath $out -Value $rows_out
Note ("wrote {0} rows" -f $rows_out.Count)

# The driver watches for this marker; it says the process reached the end
# rather than the result file merely having been opened.
Set-Content -LiteralPath "$out.done" -Value 'done'
Note 'done marker written'
