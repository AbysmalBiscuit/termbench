# In-process A/B for the GPU grid's skips

Times one of alacritree's paint-callback skips against itself by flipping it
between report windows of a single running window, and reports per-pair ratios.

## Why in-process rather than paired binaries

The sibling harness one directory up launches two builds in turn. That works
for effects worth several percent of a whole frame, and it cannot resolve a few
microseconds of GPU time: the round-to-round spread on a laptop swamps them.

So this one moves the comparison inside one process. `[debug] gpu_ab` makes the
timer flip the skip under test every 240 frames and name the arm on the report
line, which puts the two arms in front of the same driver, the same grid and
the same minute. Adjacent report lines are a pair.

The instrument is the same `[debug] gpu_timing` line the renderer already logs,
so nothing measurement-only sits in the paint path when the key is off.

## Running

```sh
./driver.ps1 -Binary path/to/alacritree.exe -Ab decorations -Mode plain
./driver.ps1 -Binary path/to/alacritree.exe -Ab decorations -Mode underline
perl analyze.pl measurements/plain-report.txt
```

`-Ab` picks which skip flips; the driver writes it into the bench config, so
the two experiments share one config and one appdata. `-Seconds` sets how long
a window runs, which decides how many pairs come out.

The binary needs `conpty.dll` and `OpenConsole.exe` beside it, for the reason
the sibling README gives: without them alacritree falls back to the Windows API
pseudoconsole, which deadlocks against a benchmark's write loop rather than
merely running slower. The driver refuses to start instead.

## Choosing a mode

`-Mode` is the sgrtest workload the window runs. Each experiment wants a mode
where its skip fires and one where it must not, and the second is the control
that matters: if the gated arm ever came out ahead there, the skip would be
dropping something someone asked to see.

| `-Ab` | skip fires | skip must not fire |
| --- | --- | --- |
| `decorations` | `plain` | `underline` |
| `backgrounds` | `plain` | `percellbg` |

## Reading the report

`analyze.pl` pairs each gated window with the always window beside it and
prints:

- **total GPU per frame**, the claim.
- **a null control** naming the stages this experiment leaves alone. Both arms
  run identical work there, so its ratio is the machine's noise floor. A
  `total` that does not clear it is drift, not effect. The analyzer picks the
  control from the arm labels, so it never sums the stage under test into its
  own baseline.
- **each stage**, so the saving can be checked against the stage it came from.

A timer result arrives three frames after the draw that earned it, so the reads
just after a flip belong to the arm that ended. The timer discards those
frames; the report never sees them.

The decoration experiment also prints whether the gate fired, which a stage
median cannot say: a median describes only the frames that drew. The background
collapse happens in the vertex shader, where nothing on the CPU side can count
it, so that run has no equivalent line.

## Isolation

`appdata/` becomes `%APPDATA%` (config, state, IPC) and `local/` becomes
`%LOCALAPPDATA%` (where the log lands), so a run never touches the live
alacritree. `ipc_socket` is off so a bench window cannot answer the CLI or MCP
bridge the live window owns; `vsync` is off because a frame cap would hide the
microseconds being measured.

`out/` and `local/` are ignored. `measurements/` holds the captured report
lines and the findings they produced, named for the experiment that made them.
