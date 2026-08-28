# The scissored glClear is a slow path, and the grid does not need it at all

Snapshot of three runs plus three captures. Numbers are those runs', not a
standing claim.

- binary: `perf/clear-timing` @ HEAD, release
- GPU: `Intel | Intel(R) Arc(TM) 140T GPU (32GB) | 3.3.0 - Build 32.0.101.8517`
- grid 178x63 in a 1437x1228 client area, `-Mode percellbg -Seconds 240`
- raw: `{scissor,quad,noclear}-percellbg-report.txt`

The shipped clear measures 99-102us across all three runs, and the whole
callback 361-365us. Two separate processes agreeing to 1% is what makes the
arms below comparable to each other.

## Three ways to not pay 100us

| arm                        | clear | backgrounds | whole callback | control |
|----------------------------|------:|------------:|---------------:|--------:|
| shipped (scissored clear)  | 100us |       105us |          363us |    1.00 |
| scissor lifted             |   0us |       159us |          325us |    1.23 |
| full-rect quad, scissored  |   4us |       115us |          269us |    1.03 |
| no grid clear at all       |   0us |       117us |          268us |    1.05 |

`control` is `backgrounds + glyphs`, work neither arm changes. A control that
moves means the saving is partly relocation rather than removal.

**Lifting the scissor** does put the clear on the fast path -- it drops to
literally 0us -- but the control moves 1.23 and `backgrounds` gains 54us. A fast
clear leaves tiles in a cleared-metadata state and the first draw to touch each
one pays to resolve it. Net saving 38us, and it is unshippable anyway: an
unscissored clear wipes the whole framebuffer, sidebars included.

**A full-rect quad** in the same colour under the same scissor costs 4us against
the clear's 102us, with the control nearly still. Net saving 96us, 26% of the
callback. Filling 1.56M pixels in 4us reads as impossible for this part, so it
was checked rather than believed: forcing the quad's colour to magenta turned
1,557,954 pixels magenta. It rasterises. Intel's tile colour compression
evidently takes a constant-colour raster fill on the fast path that the
scissored clear is missing.

**Skipping the grid's clear entirely** saves 93us and is pixel-identical to the
shipped path: 0 differing pixels of 1,764,636. eframe clears the whole
framebuffer before the callback runs, and `App::clear_color` returns
`theme.terminal_bg`, which comes from `config.palette.bg` -- the same source as
the grid's own `default_bg`. The two are equal by construction, not by luck.

## What the quad's pixel diff did and did not prove

Nothing, on its own. The first quad capture matched the shipped path to 0
pixels, which looked like proof the quad painted correctly. It was not: eframe
had already put that colour in the framebuffer, so a quad that drew nothing
would have matched too. The `noclear` capture matching to 0 pixels is what
exposed that. The magenta run is the only capture that actually establishes the
quad draws.

## Disposition

Nothing shipped here. Both remaining candidates are worth about the same, and
they differ in what they assume:

- Skipping the clear is free and simplest, but it leans on eframe having cleared
  to the same colour. Two things need checking before it ships: whether OSC 11
  can move the grid's `default_bg` away from `theme.terminal_bg` mid-session,
  and what happens under `[window] opacity`, where `clear_color` carries the
  configured alpha and the central panel fills with `Color32::TRANSPARENT`.
- The quad keeps a real write of the grid rect in the right colour, so it holds
  regardless of what eframe did, at the cost of one more program and one more
  draw.

The A/B arms stay in `gpu_timing.rs` as the record. The shipped path still
clears.
