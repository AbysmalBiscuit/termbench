# alacritree paired A/B harness

Compares two alacritree builds by running the instruments in this repo against
each of them, alternating, and reporting per-pair ratios rather than two
absolute numbers taken at different times.

## Why paired

A single run of each build, taken minutes apart, measures the machine as much
as the binary. On a laptop under any other load the round-to-round spread
reaches tens of percent, which is far larger than the effects worth chasing in a
renderer. Pairing puts both arms in the same minute so load largely divides out,
and alternating which arm goes first keeps drift from settling on one of them.

Read the per-pair ratios, not just the median. When every measurement in a pair
moves the same direction at once, that pair met a busy machine: no code change
moves plain text, scrolling, per-cell colour and underlines together.

## Running

```sh
./driver.ps1 -OldBinary path/to/old.exe -NewBinary path/to/new.exe -Pairs 6
perl analyze.pl
```

Each arm's binary needs `conpty.dll` and `OpenConsole.exe` **beside it**.
alacritree loads them from PATH or its own directory, and without them it falls
back to the Windows API pseudoconsole, which does not merely run slower: it
deadlocks against a benchmark's write loop. The driver refuses to start rather
than let that happen. Copy an installed build's whole payload, not just the exe;
`Start-Process` also refuses a file whose name lacks an executable extension, so
a `.stale-1234-0` leftover has to be renamed on the way.

## What one round measures

| instrument | what it varies |
| --- | --- |
| termbench `normal` | whole-terminal throughput; always writes 80x24 |
| sgrtest, 2000 screens | attribute density: plain, percell, percellbg, underline |
| scrolltest, 512 MB | scrolling against the same bytes repainted in place |

`percell` and `underline` push a byte-identical payload, so the difference
between them is what decorating a cell costs rather than what the extra bytes
cost.

## Isolation

`appdata/` is handed to each launch as `%APPDATA%`, so a run never touches the
live alacritree's config, state or IPC socket. That config mirrors a real one
and differs only where a difference would bias an arm:

- `gpu_timing` off, since a build without the key cannot issue the timer
  queries a build with it would be charged for.
- `pr_status` and `upstream_status` off: `gh` polling is background work during
  a measurement.
- `ipc_socket` off, so a bench window never answers the CLI or MCP bridge.
- both sidebars hidden in `state.toml`, which roughly doubles the grid and
  keeps the cell count from depending on sidebar state.

## Window geometry

Grid size is the cell count the renderer paints, so it has to be constant across
rounds. Under a tiling WM it is not: the window is sized by how many windows
share the workspace, and a second monitor at different DPI changes it again. The
driver pins the GlazeWM workspace and floats the window at a fixed size, and
only after confirming the focused window belongs to the run, so a mistimed call
cannot resize whatever the user had focused.

Every round records its grid beside its results, and `analyze.pl` names any
round that painted a different one instead of averaging it in.

## Output

`results/` holds one `<tag>-<arm>.tsv` per round, plus that round's grid, a
`done` marker, and the alacritree crash artifact for the process (which records
the exit reason whether or not anything went wrong, so a round that died quietly
is visible afterwards). Both directories are ignored; nothing here is committed.
