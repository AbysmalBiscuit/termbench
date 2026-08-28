# Decoration gate, first measured run

Snapshot. Regenerate with `perl ../analyze.pl plain-report.txt` and
`perl ../analyze.pl underline-report.txt`; both reports in this directory are
the raw input, so the tables below are reproducible from what is committed.

Machine: Windows 11, grid 178x63, vsync off, release build.

## Undecorated grid (`plain`), 139 pairs

| measurement | gated | always | ratio | p |
| --- | --- | --- | --- | --- |
| total GPU per frame | 677us | 684us | 0.952 | 0.000 |
| backgrounds + glyphs (null control) | 669us | 648us | 1.003 | 0.261 |
| decorations | - | 33us | - | - |

Median saved per frame: 33us.

Do not read the saving off the two column medians. Those are medians over
different windows; the paired difference is the statistic, and it agrees with
the ratio (0.952 of ~684us is ~33us) and with the decorations stage it removes.

Integrity: 140 of 140 gated windows skipped on every frame, and none reported a
decoration time it could not have earned.

## Underlined grid (`underline`), 133 pairs

| measurement | gated | always | ratio | p |
| --- | --- | --- | --- | --- |
| total GPU per frame | 986us | 989us | 1.004 | 0.043 |
| backgrounds + glyphs (null control) | 657us | 678us | 1.003 | 0.076 |
| decorations | 288us | 311us | 1.000 | 0.271 |

The gate does not fire: 133 windows drew on every frame, 1 mixed (the first,
before the workload had filled the screen). Both arms do identical work and
measure identical. `total` reaches p 0.043, but the null control moves the same
way, so that is machine drift rather than the gate.

## What the pass costs

Roughly 33us on a grid with nothing decorated against roughly 300us on one
underlined throughout. The pass was never free; a plain screen was paying the
cheap end of it to collapse every quad in the vertex shader and draw nothing.

## What this does not measure

Only the decoration pass, and only against itself. Nothing here compares the GPU
grid renderer to the egui mesh path, or to any other renderer.
