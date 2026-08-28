# Glyph coverage read, first measured run

Negative result. Regenerate with `perl ../analyze.pl glyph-plain-report.txt`;
that report is the raw input.

Machine: Windows 11, grid 178x63, vsync off, release build.

## What was flipped

The glyph shader recovered coverage by converting the atlas colour channels
back to gamma, three `pow()` per fragment, the way egui's general shader does.
The other arm read coverage straight out of alpha, which the decoration pass
already does. epaint writes every font texel as
`from_rgba_premultiplied(a, a, a, a)` and colour glyphs never reach this pass,
so the colour channels hold nothing alpha does not.

## Plain grid, 148 pairs

| measurement | alpha only | three pow | ratio | p |
| --- | --- | --- | --- | --- |
| total GPU per frame | 432us | 408us | 1.010 | 0.084 |
| backgrounds + decorations (null control) | 47us | 47us | 1.000 | 0.118 |
| glyphs | 382us | 360us | 1.010 | 0.242 |

Median saved per frame: -4us. Removing three transcendentals per fragment buys
nothing, and the null control sits at exactly 1.000, so the instrument was not
the problem.

## What that says about the pass

The glyph pass is bound by writing blended fragments, not by what it computes
for each one. Two things corroborate it. A nearly blank startup screen costs
15us in this stage against roughly 300us for a full one at the same 11,214
instances, so cost tracks covered pixels rather than instance count. And the
background pass, whose shader is a single assignment, cost about as much as the
glyph pass at a similar fragment count until its quads were collapsed.

That also explains why the background collapse won so much: it removed
fragments. Anything that only makes a fragment cheaper has little to win here.

## Why it was not shipped

The conversion it skips is an sRGB round trip, and skipping it moved 1.5% of
pixels by one 255th, measured with `pixdiff.ps1` against a captured static
screen. Costing output while buying no time is the wrong trade.

## Where to look instead

Draw fewer fragments, not cheaper ones. Nothing obvious is left in this pass:
glyph quads already come from the galley's atlas rect rather than the whole
cell, and blank cells already collapse to a point.
