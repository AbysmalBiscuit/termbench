# burners

CPU load generator for the benchmarks in this repo.

The other tools here measure a terminal on an idle machine. That is the case
where every terminal looks fine. The interesting numbers come from a terminal
competing with a build, and reproducing that needs a load you can describe:
same shape every run, gone when the run ends.

## Build

```sh
cd burners
cargo build --release
```

The binary lands in `burners/target/release/`.

## Run

```sh
burners                 # one busy process per logical core, until interrupted
burners 8               # eight of them
burners 8 --for 30      # eight, then exit on its own
```

`--for` is the form to use from a script: start it in the background, run the
measurement, and it cleans up after itself even if the script dies.

```sh
burners 16 --for 60 &
./termbench
```

## Why processes

Threads inside the benchmark would share its priority class, its job
assignment, and its nice value, so the scheduler would treat the load and the
thing under test as one. A build does not work that way. One process per
burner keeps the load where the scheduler can be asked to prefer one over the
other, which is the whole point of measuring under contention.

Each burner spins on a register, so it competes for cores without evicting the
benchmark's working set. A number that moves because the load trashed the cache
is a number about the load.

## Cleanup

Burners exit when the parent does, in both directions: normal exit and Ctrl+C
reap them from the parent, and a hard kill of the parent closes a pipe each
burner is watching, so they notice and exit on their own. Nothing survives the
run to eat a core unnoticed.
