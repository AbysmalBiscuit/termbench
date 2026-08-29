//! Saturate the machine so a terminal can be measured under contention.
//!
//! A terminal that feels instant on an idle box can take seconds to echo a
//! keystroke while a build runs, and none of the benchmarks here see that:
//! they measure throughput on a machine with nothing else to do.  This puts a
//! known, reproducible load next to them.
//!
//! The load is separate processes, not threads, because that is the shape of
//! the thing being reproduced.  A build is other processes competing for cores
//! through the scheduler, and a process is what carries a priority class, a
//! job assignment, and a nice value.  Threads inside the benchmark would share
//! all three and measure something else.
//!
//! Usage:
//!
//! ```text
//! burners                 # one per logical core, until interrupted
//! burners 8               # eight, until interrupted
//! burners 8 --for 30      # eight, then exit
//! ```

use std::io::Read;
use std::process::{Child, Command, Stdio};
use std::time::Duration;

/// Spin without touching memory, so the load competes for cores and leaves the
/// cache alone.  A benchmark whose numbers move because the load evicted its
/// working set is measuring the load, not the terminal.
fn burn() -> ! {
    // The parent holds the write end of this pipe.  Killing the parent hard
    // skips every destructor it owns, including the one that reaps these, so a
    // burner that does not notice on its own outlives the run and quietly eats
    // a core until someone spots it in the task list.
    std::thread::spawn(|| {
        let mut byte = [0u8; 1];
        let _ = std::io::stdin().read(&mut byte);
        std::process::exit(0);
    });

    let mut state: u64 = 1;
    loop {
        for _ in 0..4096 {
            state = state.wrapping_mul(6364136223846793005).wrapping_add(1);
        }
        std::hint::black_box(state);
    }
}

/// Reaps on drop, which covers everything except a hard kill of the parent;
/// the pipe each child watches covers that.
struct Burners(Vec<Child>);

impl Drop for Burners {
    fn drop(&mut self) {
        for child in &mut self.0 {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

impl Burners {
    fn spawn(count: usize) -> Self {
        let exe = std::env::current_exe().expect("current exe");
        let mut children = Vec::new();
        for _ in 0..count {
            match Command::new(&exe).arg("--burn").stdin(Stdio::piped()).spawn() {
                Ok(child) => children.push(child),
                Err(err) => eprintln!("burner failed to start: {err}"),
            }
        }
        Self(children)
    }
}

fn cores() -> usize {
    std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1)
}

fn usage() -> ! {
    eprintln!("usage: burners [COUNT] [--for SECONDS]");
    eprintln!();
    eprintln!("  COUNT          how many busy processes (default: one per logical core)");
    eprintln!("  --for SECONDS  exit after this long (default: run until interrupted)");
    std::process::exit(2);
}

fn main() {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    if argv.iter().any(|a| a == "--burn") {
        burn();
    }

    let mut count: Option<usize> = None;
    let mut hold: Option<u64> = None;
    let mut it = argv.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--for" | "-t" => match it.next().and_then(|v| v.parse().ok()) {
                Some(seconds) => hold = Some(seconds),
                None => usage(),
            },
            "--help" | "-h" => usage(),
            other => match other.parse() {
                Ok(n) => count = Some(n),
                Err(_) => usage(),
            },
        }
    }

    let count = count.unwrap_or_else(cores);
    if count == 0 {
        eprintln!("nothing to do");
        return;
    }

    let _burners = Burners::spawn(count);
    match hold {
        Some(seconds) => {
            eprintln!("{count} burners for {seconds}s");
            std::thread::sleep(Duration::from_secs(seconds));
        },
        // Sleeping in a loop rather than parking, so the reaper in `Drop` still
        // runs on the console signal a Ctrl+C delivers to the whole group.
        None => {
            eprintln!("{count} burners, Ctrl+C to stop");
            loop {
                std::thread::sleep(Duration::from_secs(1));
            }
        },
    }
}
