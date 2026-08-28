# The glyph pass is ink-bound, not instance-bound

Snapshot of three runs. Numbers are those runs', not a standing claim.

- binary: `perf/glyph-fill` @ a61b1bcb, release
- GPU: `Intel | Intel(R) Arc(TM) 140T GPU (32GB) | 3.3.0 - Build 32.0.101.8517`
- `-Ab decorations -Mode percellbg -Seconds 240 -FontSize {8,12,20}`
- raw: `size{08,12,20}-percellbg-report.txt`
- all figures are the `gated` arm, which is the shipped path

## The design

The window holds its pixels while `[font] size` moves, so cell count falls as
1/size^2 and each glyph's ink grows as size^2. Total ink area is therefore
roughly constant while the instance count moves 6.5x. Two outcomes separate:

- glyph time flat across sizes -> the pass is bound by the ink it rasterises
- glyph time tracking cell count -> the pass is bound by per-instance work

`backgrounds` asks the same question with no texture fetch in it, and
`whole - total` is the clear, which covers identical pixels at every size and
so doubles as a cross-run control.

## What the runs said

| size | grid    |  cells | glyphs | backgrounds | total | whole | clear |
|-----:|---------|-------:|-------:|------------:|------:|------:|------:|
|    8 | 267x96  | 25,632 |  261us |       196us | 462us | 578us | 115us |
|   12 | 178x63  | 11,214 |  164us |       106us | 272us | 360us |  88us |
|   20 | 107x37  |  3,959 |  138us |       116us | 254us | 350us |  96us |

Cross-run comparison is the thing the clock finding warned about, so read the
drift first. `trend.pl` head/tail: 8pt 0.85 (it got *slower* through the run,
the only one of the three under thermal load), 12pt 1.06, 20pt 1.00. The 12pt
and 20pt runs held their clocks and their clears agree to 9%. Those two carry
the conclusion; 8pt only corroborates it.

Between the two clean runs, a 2.83x cut in instances bought 16% off the glyph
pass and nothing at all off backgrounds, which moved the wrong way by 9% --
inside the clear's own 9% spread.

## The answer

Ink-bound. Fitting the three points gives about 6ns per instance over a fixed
~108us; fitting only the two clean runs gives 3.6ns over a fixed ~124us. Either
way the instance-driven share of the glyph pass at the 12pt default is a
quarter to two-fifths, and the rest is rasterising ink.

The quads are already tight. `slot_from_galley` takes the galley's own `pos`
and `uv`, so a glyph's rectangle is egui's atlas box around the ink, not the
cell. There is no slack geometry left to trim -- which is also why the
zero-coverage discard found nothing: with a tight quad there is little blank
area to discard, and discard skips the write, never the fetch.

## Disposition

Instance-count work on the glyph pass has a low ceiling: cutting instances by
2.8x moved it 16%. Collapsing glyph runs the way the background pass collapses
its own would buy correspondingly little. If the glyph pass is worth attacking
again, the target is per-texel cost, not geometry and not instance count.
