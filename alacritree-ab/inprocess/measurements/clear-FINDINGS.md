# The unattributed 88us was the clear, and the clear is 100us

Snapshot of one run. Numbers are the run's, not a standing claim.

- binary: `perf/clear-timing` @ HEAD, release
- GPU: `Intel | Intel(R) Arc(TM) 140T GPU (32GB) | 3.3.0 - Build 32.0.101.8517`
- grid 178x63 in a 1437x1228 client area, `-Ab decorations -Mode percellbg -Seconds 240`, 264 pairs
- raw: `clear-percellbg-report.txt`

## What was inferred before

`whole callback` is one `GL_TIME_ELAPSED` bracket around everything `draw`
issues. `total` is the four stage brackets added up, on the frames between.
`whole - total` ran about 88us and had never been measured -- the reasoning was
that the clear sits outside every stage, so the gap must be mostly clear.

Reasoning is not measurement. `GL_TIME_ELAPSED` cannot nest, but nothing stopped
the clear from getting a bracket of its own beside the other four.

## What the bracket says

| measurement    | value |
|----------------|------:|
| whole callback | 359us |
| clear          | 100us |
| backgrounds    | 106us |
| glyphs         | 164us |
| upload         |   0us |
| stage sum      | 371us |
| whole - sum    | -12us |

The clear is 100us, 28% of the callback and the second-largest item in it after
the glyph pass.

The residual went from +88us to -12us, which is the other half of the answer.
The gap was the clear all along, minus a bracket tax the clear's own bracket now
pays: five bottom-of-pipe drains cost about 12us more than one, so roughly 3us
per bracket. Every per-stage median in this series is inflated by about that
much -- under 2% of the glyph stage, which changes no conclusion any of the
earlier runs reached.

Cross-run check: the `whole callback` figure is 359us here and 360us in the
12pt font-size run, two separate processes on the same workload. The instrument
is repeatable even where its absolute microseconds are not.

## The open question

100us to clear roughly 1.8M pixels is slow for a hardware clear, which usually
costs close to nothing. The likely reason is the scissor: egui clips the
callback to the grid's rect before handing it over, and a scissored clear drops
off the fast-clear path on many parts. That would mean the pass is paying full
fill rate to write a constant colour.

Two things could be tried, in this order, and neither is tried here:

1. Price an unscissored clear against the scissored one. If they differ, the
   scissor is the cause and the question becomes whether the grid callback can
   safely cover its whole rect.
2. Replace `glClear` with one full-rect quad in the default background colour.
   If the clear is already paying full fill rate, a trivial-shader quad costs
   about the same and might cost less.

Dropping the clear outright is already ruled out: without it the background pass
has to draw every cell, which the background experiment priced higher than the
clear plus a collapsed pass.
