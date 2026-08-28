# What the absolute microseconds are worth

Snapshot. Regenerate with `perl ../analyze.pl clock-trend-report.txt` and
`perl ../trend.pl gated clock-trend-report.txt`; the raw report is committed
beside this file, so both tables come back from what is here.

Machine: Windows 11, grid 178x63, vsync off, release build. The context is the
integrated GPU, which the report line now names:

```
grid gl: Intel | Intel(R) Arc(TM) 140T GPU (32GB) | 3.3.0 - Build 32.0.101.8517
```

The machine also has an NVIDIA RTX PRO 2000, and no measurement in this
directory has ever touched it. Neither alacritree nor vendored alacritty
exports `NvOptimusEnablement`, so an OpenGL binary Optimus does not recognize
gets the integrated GPU, whatever the monitors are plugged into.

## The clock moves more than anything under test

One run, 129 windows of the shipped path, identical work throughout:

| stage | min | p10 | median | p90 | max | max/min |
| --- | --- | --- | --- | --- | --- | --- |
| total (stages summed) | 66us | 220us | 342us | 487us | 526us | 8.0 |
| whole callback | 136us | 317us | 508us | 739us | 831us | 6.1 |
| glyphs | 31us | 202us | 305us | 418us | 462us | 14.9 |

Every stage moves together by the same factor, which is what a clock does and
not what a workload does. There is no warm-up to wait out: seven consecutive
windows sat near 220us and five windows later the run was back above 500us.

So a single absolute figure from this rig says almost nothing. Any claim of the
form "the glyph pass costs N microseconds" needs the distribution, and p10 is
the closest thing to a ramped-clock reading.

## The pairing survives it

Same run, read as pairs:

| measurement | gated | always | ratio | p |
| --- | --- | --- | --- | --- |
| total GPU per frame | 342us | 655us | 0.530 | 0.000 |
| whole callback | 507us | 839us | 0.614 | 0.000 |
| glyphs + decorations (null control) | 303us | 307us | 1.003 | 0.474 |
| backgrounds | 36us | 347us | 0.104 | 0.000 |

The null control lands on 1.003 at p 0.474 across an 8x swing in the absolute
numbers. Alternating the arms window by window is what makes that possible, and
it is the only reason the earlier ratios in this directory still stand.

## A third of the callback was never counted

`whole callback` is one bracket around everything the callback issues. `total`
is the stages added up. The gap is a median of 165us against a stage sum of
342us, and it is mostly the `glClear`, which sits outside every stage bracket.

The gap cannot be bracket overhead. A whole-callback frame issues one query and
a per-stage frame issues four, so per-bracket cost would push `total` above
`frame` rather than below it.

That closes a lever rather than opening one. Dropping the clear would force the
background pass to draw every cell, which the `always` arm above prices at
347us; clear plus collapsed backgrounds is 201us. The arrangement already wins.
