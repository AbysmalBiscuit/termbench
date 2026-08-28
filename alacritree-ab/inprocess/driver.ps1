# Launches one bench window with an isolated APPDATA (config, state, IPC) and
# LOCALAPPDATA (the log the report lands in), lets it run, then kills it and
# prints the gpu grid report lines.
param(
  [Parameter(Mandatory = $true)][string]$Binary,
  [ValidateSet('decorations', 'backgrounds')][string]$Ab = 'decorations',
  [ValidateSet('plain', 'percell', 'percellbg', 'underline')][string]$Mode = 'plain',
  [int]$Seconds = 300
)

$here = $PSScriptRoot
$exe = (Resolve-Path -LiteralPath $Binary).Path
foreach ($dep in @('conpty.dll', 'OpenConsole.exe')) {
  if (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $exe) $dep))) {
    throw "no $dep beside $exe; the run would deadlock"
  }
}

$env:APPDATA = Join-Path $here 'appdata'
$env:LOCALAPPDATA = Join-Path $here 'local'
$env:ALACRITREE_AB_MODE = $Mode

# One config serves both experiments, and the arm it flips is the only thing
# that differs between them, so the driver sets it rather than the caller
# editing a file it would then have to remember to put back.
$config = Join-Path $here 'appdata/alacritty/alacritree.toml'
$patched = (Get-Content -LiteralPath $config -Raw) -replace 'gpu_ab = "[a-z]+"', ('gpu_ab = "' + $Ab + '"')
Set-Content -LiteralPath $config -Value $patched -NoNewline

Remove-Item -Recurse -Force (Join-Path $here 'local/alacritree') -ErrorAction SilentlyContinue
$p = Start-Process -FilePath $exe -PassThru
Write-Host "$Ab/$Mode : pid $($p.Id), running ${Seconds}s"
Start-Sleep -Seconds $Seconds
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
$p.WaitForExit(5000) | Out-Null
Start-Sleep -Milliseconds 500

$grid = Get-Content -LiteralPath "$here/out/$Mode.grid" -ErrorAction SilentlyContinue
Write-Host "grid $grid"
Get-ChildItem -Path (Join-Path $here 'local/alacritree') -Filter '*.log' -ErrorAction SilentlyContinue |
  ForEach-Object { Select-String -Path $_.FullName -Pattern 'gpu grid' | ForEach-Object { $_.Line } }
