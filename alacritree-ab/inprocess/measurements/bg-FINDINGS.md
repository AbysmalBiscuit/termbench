# Background collapse, first measured run

Snapshot. Regenerate with `perl ../analyze.pl bg-plain-report.txt` and
`perl ../analyze.pl bg-percellbg-report.txt`; both reports here are the raw
input, so the tables below are reproducible from what is committed.

Machine: Windows 11, grid 178x63, vsync off, release build.

## Plain grid, 116 pairs

Nothing is decorated and almost every cell keeps the default background, so
almost every quad collapses.

| measurement | gated | always | ratio | p |
| --- | --- | --- | --- | --- |
| total GPU per frame | 396us | 775us | 0.524 | 0.000 |
| glyphs + decorations (null control) | 350us | 355us | 1.015 | 0.011 |
| backgrounds | 42us | 418us | 0.103 | 0.000 |

Median saved per frame: 368us, against the 376us the backgrounds stage gave
back. Total GPU per frame nearly halves.

The null control is not flat here the way it is in the decoration experiment,
and 1.015 at p 0.011 is more than drift. Removing two megapixels of fill
changes what the rest of the frame contends for, so the stages left alone are
not perfectly independent of the one under test. It runs against the change,
making the gated arm's glyphs look slower, so the effect is understated rather
than inflated.

## Per-cell background grid, 137 pairs

Every cell carries a background of its own, so nothing may collapse.

| measurement | gated | always | ratio | p |
| --- | --- | --- | --- | --- |
| total GPU per frame | 649us | 648us | 1.004 | 0.488 |
| glyphs + decorations (null control) | 299us | 300us | 1.004 | 0.434 |
| backgrounds | 345us | 345us | 1.000 | 0.793 |

Both arms measure identical, and `backgrounds` lands on 1.000 at p 0.793. The
collapse correctly does nothing when every cell has a background to draw.

## What the pass costs

Roughly 42us on a grid where nothing needs a quad against roughly 420us where
every cell does. The clear paints the grid rect once; drawing an opaque quad
over each cell to repaint that same colour was the whole of the difference.

## What this does not measure

Only the background quad, and only against itself. Nothing here compares the
GPU grid renderer to the egui mesh path, or to any other renderer.
