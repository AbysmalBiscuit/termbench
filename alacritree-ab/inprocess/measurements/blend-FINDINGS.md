# Blending the opaque background pass costs nothing

Snapshot of one run. Numbers are the run's, not a standing claim.

- binary: `perf/glyph-fill` @ a61b1bcb, release
- GPU: `Intel | Intel(R) Arc(TM) 140T GPU (32GB) | 3.3.0 - Build 32.0.101.8517`
- grid 178x63, `-Ab blend -Mode percellbg -Seconds 240`, 279 pairs
- raw: `blend-percellbg-report.txt`

## The question

egui_glow leaves premultiplied blending enabled before handing the callback the
context, and every terminal background colour is opaque. Blending an opaque
source computes the source. The pass could run with `GL_BLEND` off.

## The answer

It saves nothing.

| measurement            | blend on | blend off | ratio |     p |
|------------------------|---------:|----------:|------:|------:|
| backgrounds            |    105us |     105us | 1.000 | 0.632 |
| total GPU per frame    |    270us |     270us | 1.000 | 0.571 |
| whole callback         |    359us |     359us | 1.000 | 0.445 |
| glyphs (null control)  |    164us |     163us | 1.000 | 0.698 |

The null control moves as much as the subject, so the instrument is reading its
own floor in both columns. Over 279 pairs the bound on any real saving is under
about 1% of a 105us stage, so under ~1us per frame.

The plausible reason: the fixed-function blender is not a per-fragment cost the
way a texture fetch is. On this part it appears to be free when it runs, which
is the same shape as the zero-coverage discard result.

## The clock behaved this time

`trend.pl` puts head/tail at 1.02 (total), 1.02 (whole), 1.04 (glyphs). The
clock test saw 6-15x on the same fields. `percellbg` repaints every cell every
frame and never lets the GPU drop to an idle clock, so this run's absolute
microseconds are worth quoting. A `plain` run's are not.

## Disposition

Do not ship the `GL_BLEND` toggle. The A/B arm stays in `gpu_timing.rs` as the
record of the measurement; the shipped path keeps blending on, which is also
what alacritty does.
