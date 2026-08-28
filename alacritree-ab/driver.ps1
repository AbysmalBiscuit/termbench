# Paired A/B of two alacritree builds.
#
# Each round launches both binaries once, so the two arms see the same minute of
# machine load and the comparison is a per-round ratio rather than two numbers
# taken hours apart. Round order alternates (old-first, new-first, old-first, ...)
# so drift over the run cancels instead of loading onto one arm.
#
# Both windows read an isolated config, so a run never touches the live
# alacritree's state, config or IPC socket. See appdata/alacritty/alacritree.toml
# for what that config deliberately differs on.
#
#   ./driver.ps1 -OldBinary path/to/a.exe -NewBinary path/to/b.exe -Pairs 6
#
# Each arm's binary needs conpty.dll and OpenConsole.exe beside it. Without them
# alacritree falls back to the Windows API pseudoconsole, which does not merely
# run slower -- it deadlocks against a benchmark's write loop.

param(
  [string]$OldBinary,
  [string]$NewBinary,
  [int]$Pairs = 6,
  [int]$Warmup = 1,
  [int]$TimeoutSeconds = 300,
  [string]$Workspace = '1'
)

$ErrorActionPreference = 'Stop'

$base = $PSScriptRoot
$results = Join-Path $base 'results'
if (-not $OldBinary) { $OldBinary = Join-Path $base 'bin/alacritree-old.exe' }
if (-not $NewBinary) { $NewBinary = Join-Path $base 'bin/alacritree-new.exe' }

# Process names, not paths: the layout check below compares against what the WM
# reports, and Start-Process refuses a file whose name lacks an executable
# extension (so a `.stale-1234-0` install leftover has to be copied first).
$bins = @{ old = $OldBinary; new = $NewBinary }
foreach ($k in $bins.Keys) {
  if (-not (Test-Path -LiteralPath $bins[$k])) { throw "missing binary for arm '$k': $($bins[$k])" }
  $dir = Split-Path -Parent $bins[$k]
  foreach ($dep in @('conpty.dll', 'OpenConsole.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $dir $dep))) {
      throw "arm '$k' has no $dep beside it in $dir; the run would deadlock"
    }
  }
}
New-Item -ItemType Directory -Force -Path $results | Out-Null

$env:APPDATA = Join-Path $base 'appdata'

# GlazeWM tiles new windows, so left alone the bench grid depends on how many
# windows happen to share the workspace and on which monitor's DPI it landed on
# (a machine with mixed scaling makes those grids differ). Both change the cell
# count the renderer paints, which is the quantity under measurement. Pin the
# workspace, then float the window at a fixed size so every round paints alike.
$glaze = Join-Path $env:USERPROFILE '.local/bin/glazewm.exe'
$haveGlaze = Test-Path -LiteralPath $glaze
if (-not $haveGlaze) { Write-Host "glazewm not found at $glaze; window geometry left to the WM" }

function Move-ToBenchWorkspace {
  if (-not $haveGlaze) { return }
  & $glaze command focus --workspace $Workspace 2>$null | Out-Null
}

function Set-BenchWindowFloating {
  param([string]$ProcName)
  if (-not $haveGlaze) { return }
  # Only touch the window once it is confirmed to be ours: a mistimed call would
  # otherwise float and resize whatever the user had focused.
  try {
    $focused = (& $glaze query focused 2>$null | ConvertFrom-Json).data.focused
  } catch { return }
  if ($focused.processName -ne $ProcName) {
    Write-Host "  focused window is '$($focused.processName)', not $ProcName; leaving layout alone"
    return
  }
  & $glaze command set-floating --centered true --width 1280 --height 800 2>$null | Out-Null
}

function Invoke-Round {
  param([string]$Arm, [string]$Tag)

  $out = "$results/$Tag-$Arm.tsv"
  foreach ($stale in @($out, "$out.done", "$out.grid")) {
    Remove-Item -LiteralPath $stale -ErrorAction SilentlyContinue
  }

  $env:ALACRITREE_AB_OUT = $out
  $procName = [System.IO.Path]::GetFileNameWithoutExtension($bins[$Arm])
  $started = Get-Date
  Move-ToBenchWorkspace
  $p = Start-Process -FilePath $bins[$Arm] -PassThru
  Start-Sleep -Milliseconds 1200
  Set-BenchWindowFloating -ProcName $procName

  $deadline = $started.AddSeconds($TimeoutSeconds)
  while (-not (Test-Path -LiteralPath "$out.done")) {
    if ((Get-Date) -gt $deadline) { break }
    if ($p.HasExited) { Start-Sleep -Milliseconds 500; break }
    Start-Sleep -Milliseconds 250
  }
  $elapsed = ((Get-Date) - $started).TotalSeconds

  Start-Sleep -Milliseconds 500
  if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $p.WaitForExit(5000) | Out-Null
  }

  # alacritree writes one artifact per process, named by pid, recording the exit
  # reason whether or not anything went wrong. Keeping it with the results is
  # what makes a round that died quietly visible afterwards.
  $artifacts = Join-Path $env:LOCALAPPDATA 'alacritree'
  Get-ChildItem -LiteralPath $artifacts -Filter "crash-*-$($p.Id).log" -ErrorAction SilentlyContinue |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination "$results/$Tag-$Arm.crash.log" -Force }

  $ok = Test-Path -LiteralPath "$out.done"
  $grid = if (Test-Path -LiteralPath "$out.grid") { Get-Content -LiteralPath "$out.grid" } else { '?' }
  '{0,-14} {1,-4} {2,7:N1}s  {3,-9} grid {4}' -f `
    $Tag, $Arm, $elapsed, $(if ($ok) { 'ok' } else { 'NO RESULT' }), $grid | Write-Host
  return $ok
}

Write-Host "old: $OldBinary"
Write-Host "new: $NewBinary"
Write-Host "warmup: $Warmup pair(s), measured: $Pairs pair(s)"
Write-Host ''

for ($w = 1; $w -le $Warmup; $w++) {
  Invoke-Round -Arm 'old' -Tag "warmup$w" | Out-Null
  Invoke-Round -Arm 'new' -Tag "warmup$w" | Out-Null
}

for ($r = 1; $r -le $Pairs; $r++) {
  $tag = 'pair{0:d2}' -f $r
  # Alternate which arm goes first so drift within the run cancels.
  if ($r % 2 -eq 1) { $order = @('old', 'new') } else { $order = @('new', 'old') }
  foreach ($arm in $order) { Invoke-Round -Arm $arm -Tag $tag | Out-Null }
}

Write-Host ''
Write-Host "done. analyse with: perl $base/analyze.pl"
