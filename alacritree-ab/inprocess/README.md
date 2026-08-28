# In-process decoration-gate A/B

Times alacritree's decoration pass against itself by alternating the gate
between report windows of a single running window, and reports per-pair ratios.

## Why in-process rather than paired binaries

The sibling harness one directory up launches two builds in turn. That works
for effects worth several percent of a whole frame, and it cannot resolve a few
microseconds of GPU time: the round-to-round spread on a laptop swamps them.

So this one moves the comparison inside one process. `[debug] gpu_deco_ab`
makes the timer flip the gate every 240 frames and name the arm on the report
line, which puts the two arms in front of the same driver, the same grid and
the same minute. Adjacent report lines are a pair.

The instrument is the same `[debug] gpu_timing` line the renderer already logs,
so nothing measurement-only sits in the paint path when the key is off.

## Running

```sh
./driver.ps1 -Binary path/to/alacritree.exe -Mode plain      -Seconds 300
./driver.ps1 -Binary path/to/alacritree.exe -Mode underline  -Seconds 300
perl analyze.pl measurements/plain-report.txt
```

The binary needs `conpty.dll` and `OpenConsole.exe` beside it, for the reason
the sibling README gives: without them alacritree falls back to the Windows API
pseudoconsole, which deadlocks against a benchmark's write loop rather than
merely running slower. The driver refuses to start instead.

## The two modes

| mode | what the grid holds | what the pair measures |
| --- | --- | --- |
| `plain` | no cell decorated | what the gate saves, since only one arm draws |
| `underline` | every cell underlined | the gate correctly not firing: both arms draw identical work |

`underline` is the control that matters most. If the gated arm ever came out
ahead there, the gate would be dropping a decoration someone asked for.

## Reading the report

`analyze.pl` pairs each `[deco gated]` window with the `[deco always]` window
beside it and prints three rows:

- **total GPU per frame** is the claim.
- **backgrounds + glyphs** is a null control. Both arms run identical work
  there, so its ratio is the machine's noise floor. A `total` that does not
  clear it is drift, not effect.
- **decorations** is the pass itself, present on the always arm and absent from
  a gated arm that skipped.

Two integrity lines follow. `gated windows: N skipped every frame` says whether
the gate actually fired, which a stage median cannot: a median describes only
the frames that drew. `gated windows that skipped yet reported a decoration
time` must be zero, or a result leaked across an arm flip.

A timer result arrives three frames after the draw that earned it, so the
reads just after a flip belong to the arm that ended. The timer discards those
frames; the report never sees them.

## Isolation

`appdata/` becomes `%APPDATA%` (config, state, IPC) and `local/` becomes
`%LOCALAPPDATA%` (where the log lands), so a run never touches the live
alacritree. `ipc_socket` is off so a bench window cannot answer the CLI or MCP
bridge the live window owns; `vsync` is off because a frame cap would hide the
microseconds being measured.

`out/` and `local/` are ignored. `measurements/` holds the captured report lines and
the findings they produced.
