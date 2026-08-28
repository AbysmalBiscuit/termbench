# OSC 11 does not decide it; opacity does

Snapshot. Answers the two questions left open by `clear-probes-FINDINGS.md`:
can OSC 11 or `[window] opacity` tell the two clear candidates apart?

- binary: `perf/clear-timing` @ HEAD, release
- captures: `osc11-gpu.png`, `op-{clear,noclear,mesh}.png`

## OSC 11: not a discriminator, but it is a bug

The paint path does follow OSC 11. `terminal_view.rs` reads `term.colors()` into
`runtime_palette`, and `colors::resolve` prefers the runtime entry over the
configured one, so a cell whose background is `Named(Background)` picks up the
new colour. Sending `ESC ] 11 ; #FF0000 BEL` to the static screen turns
1,190,688 pixels red.

`default_bg` does not follow it. `terminal_view.rs` takes it from
`background(&config.palette)`, which never consults the runtime palette. Two
things follow, both visible in the capture:

- 59,682 pixels keep the configured `#141F2E` -- a border of 8 near-full columns
  and 5 near-full rows, plus scattered regions consistent with rows that were
  never re-damaged after the palette moved.
- The background collapse compares each cell against `default_bg`. Once OSC 11
  moves the rendered colour away from it, no cell matches, so the pass draws
  every cell and the collapse stops firing.

This does not separate the candidates. eframe's `App::clear_color` reads
`theme.terminal_bg`, which comes from `config.palette.bg` -- the same source
`default_bg` uses. Deleting the grid's clear leaves eframe's clear painting the
identical stale colour. Same pixels, same bug. It wants its own fix: teach
`default_bg` to read the runtime palette.

## Opacity: this is the discriminator

Upstream alacritty makes the clear the sole carrier of window opacity:

- `renderer::clear(color, alpha)` writes `(rgb * alpha, alpha)` -- premultiplied,
  carrying the configured opacity.
- `compute_bg_alpha` returns `0.` for `Named(Background)`, and the text shader
  discards a fragment at `bg.a == 0.0`, so default-background cells are never
  drawn and the clear shows through them.

alacritree's grid clear writes `(rgb, 1.0)`: `rgb_to_color32` is
`Color32::from_rgb`, so the alpha is 255, and `to_array()` carries it through as
1.0. `glClear` ignores blend state, so that alpha lands in the framebuffer
directly. On a translucent window the GPU grid path therefore makes the terminal
rect opaque, which is not what upstream does.

Removing the clear does not fix that on its own. It falls back to eframe's
`clear_color`, which returns `[r, g, b, opacity]` -- the right alpha, but not
premultiplied, where upstream premultiplies. That is a second divergence, in
`app.rs` rather than in the callback.

**This was not confirmed by capture, and the capture method is the reason.**
`PrintWindow` returned alpha 255 for every pixel of all three captures --
shipped, `noclear`, and the mesh path at `opacity = 0.8`. The mesh path was the
positive control and it failed, so the method discards alpha rather than the
window being opaque. The opacity claims above rest on reading both code paths,
not on a measurement, and should be treated that way.

## Recommendation

Ship the quad, not the skip.

The quad writes the grid rect in the same colour with the same alpha the clear
did, so it is a pure performance change: 96us saved, pixels provably identical.
It touches neither of the divergences above.

Skipping the clear is worth the same 93us but changes what reaches the
framebuffer's alpha channel, and it does so while two transparency bugs are
already sitting in that path. Fix `clear_color` to premultiply and give
`default_bg` the runtime palette first; then skipping the clear becomes the
obvious simplification rather than a third change tangled with the other two.
