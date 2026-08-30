# termbench and friends

A fork of [cmuratori/termbench](https://github.com/cmuratori/termbench) carrying
two more instruments and the harnesses that run all of them against a terminal
under development.

Upstream answers one question: how fast does a terminal accept bytes? That
number confounds several things a renderer does separately, so the instruments
here hold one of them fixed at a time.

## The instruments

The sources are in `instruments/`. Every build writes its binaries to the repo
root, because that is where the harnesses load them from by name.

| source | question it answers |
| --- | --- |
| `termbench.cpp` | how fast does a terminal sink bytes? Upstream's benchmark, plus a result file. |
| `sgrtest.cpp` | does it stall on the bytes, or on the attribute changes inside them? Paints the same grid the same number of times in every mode and varies only SGR density. |
| `scrolltest.cpp` | does it stall because it is scrolling, or because it is moving bytes? Pushes an identical byte count through payloads that differ in one respect at a time. |

Each source opens with the reasoning behind its modes and what its pairs
isolate. Read that before reading its numbers.

All three write results to a file rather than stdout, because stdout is
attached to the terminal being measured. `sgrtest` and `scrolltest` take the
path positionally; `termbench` takes `-out`. Run either of the new two with no
arguments for its usage.

`fast_pipe.h` is upstream's named-pipe bypass for the Windows conio subsystem.

## Building

```sh
devrun task build    # everything, from any shell
```

`devrun task` lists the rest. The tasks wrap the scripts below, which still work
on their own from a developer prompt:

```sh
./build.bat    # Windows, MSVC and clang
./build.sh     # anything else, clang
```

Building only `termbench.cpp` leaves a harness round unable to start. The burner
is a separate crate and only `devrun task build` picks it up along with the
rest; `cd burners && cargo build --release` is the direct form.

## Running termbench

```sh
termbench_release_clang small    # ~1 MB payloads, for cmd.exe or Windows Terminal
termbench_release_clang          # the regular sizes
termbench_release_clang large    # more of a stress test
```

Upstream's guidance: on a Windows machine with memory bandwidth in the 10-20
GB/s range, a reasonable terminal lands in the 0.5-2.0 GB/s range. Well above
suggests a well-optimized terminal, well below a poorly written one. Throughput
depends heavily on hardware and on the operating system's pipe behaviour, so
treat those as rough. Upstream has not tested termbench on Linux and gives no
expected numbers there.

## The harnesses

The instruments say what a terminal did. Comparing two builds needs more than
running them twice, because on a laptop the round-to-round spread swamps most
of what is worth chasing.

| directory | what it compares |
| --- | --- |
| `alacritree-ab/` | two alacritree builds, alternating arms so drift divides out. For effects worth several percent of a frame. |
| `alacritree-ab/inprocess/` | one build against itself, flipping a renderer option between report windows. For a few microseconds of GPU time, which the paired harness cannot resolve. |
| `burners/` | a describable CPU load, so a terminal can be measured while competing with a build instead of on an idle machine. |

Each has its own README covering why it is built that way, how to run it, and
how to read what comes out. `alacritree-ab/inprocess/measurements/` holds
captured reports and the findings they produced; each findings file names the
command that regenerates it from the raw report committed beside it.
