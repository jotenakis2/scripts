#!/usr/bin/env python3
"""Bench an interactive shell's real startup latency.

Why a PTY: an interactive shell only behaves normally when stdout is a
terminal, and `zsh -i -c exit` skips everything a defer mechanism schedules, so
it under-reports by an order of magnitude. Here the shell is spawned in a real
pseudo-terminal and timed on its actual output stream.

Two numbers per run:
  first = first byte of output   -> the prompt is visible, you can type
  last  = last byte before quiet -> every deferred task (plugins, completion
                                    dump, prompt theme, version manager) is done

Usage:
  ./zsh-startup-bench.py                          # zsh -i, 5 runs
  ./zsh-startup-bench.py --runs 20 --drop-first 3 # ignore the cold runs
  ./zsh-startup-bench.py --per-prompt 4           # + latency of 4 later prompts
  ./zsh-startup-bench.py --cmd "bash -i"          # any interactive shell
  ./zsh-startup-bench.py --env ZDOTDIR=/tmp/cfg   # profile an alternative config

Reading the result: the machine gives a bimodal spread (scheduler, CPU frequency),
so compare configurations on `min`, not on the median. `--drop-first` removes the
first N runs, which pay cold page cache.
"""
import argparse
import os
import pty
import select
import statistics
import sys
import time


def spawn(argv, extra_env=None):
    pid, fd = pty.fork()
    if pid == 0:  # child
        env = os.environ.copy()
        if extra_env:
            env.update(extra_env)
        env.setdefault("TERM", "xterm-256color")
        try:
            os.execvpe(argv[0], argv, env)
        finally:
            os._exit(127)
    return pid, fd


def drain(fd, seconds):
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.02)
        if r:
            try:
                if not os.read(fd, 65536):
                    return False
            except OSError:
                return False
    return True


def burst(fd, start, quiet=0.25, limit=10.0):
    """Return (first_ms, last_ms) of the output burst that follows `start`."""
    first = last = None
    while True:
        r, _, _ = select.select([fd], [], [], 0.02)
        now = time.time()
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            if first is None:
                first = now
            last = now
        else:
            if last is not None and now - last > quiet:
                break
            if now - start > limit:
                break
    return (
        round((first - start) * 1000) if first else None,
        round((last - start) * 1000) if last else None,
    )


def measure_one(argv, extra_env, presses):
    t0 = time.time()
    pid, fd = spawn(argv, extra_env)
    first, last = burst(fd, t0)
    prompts = []
    if presses:
        time.sleep(0.8)
        drain(fd, 0.4)
        for _ in range(presses):
            start = time.time()
            os.write(fd, b"\n")
            # the newline echo arrives first, so the LAST chunk of the burst is
            # when the new prompt finished rendering
            _, done = burst(fd, start, quiet=0.10, limit=3.0)
            if done is not None:
                prompts.append(done)
            drain(fd, 0.15)
    try:
        os.kill(pid, 9)
        os.waitpid(pid, 0)
    except OSError:
        pass
    return first, last, prompts


def main():
    parser = argparse.ArgumentParser(
        description="Measure real interactive shell startup latency in a PTY.")
    parser.add_argument("--runs", type=int, default=5,
                        help="number of shells to spawn (default 5)")
    parser.add_argument("--cmd", default="zsh -i",
                        help='command to run (default "zsh -i")')
    parser.add_argument("--env", action="append", default=[], metavar="K=V",
                        help="extra environment for the shell (repeatable)")
    parser.add_argument("--per-prompt", type=int, default=0, metavar="N",
                        help="also time N later prompts (per-prompt cost)")
    parser.add_argument("--drop-first", type=int, default=0, metavar="N",
                        help="ignore the first N runs (cold cache warm-up)")
    parser.add_argument("--quiet", action="store_true",
                        help="only print the summary")
    args = parser.parse_args()

    argv = args.cmd.split()
    extra_env = {}
    for item in args.env:
        key, _, value = item.partition("=")
        extra_env[key] = value

    firsts, lasts, prompts = [], [], []
    for i in range(args.runs):
        first, last, per = measure_one(argv, extra_env, args.per_prompt)
        if first is None:
            print(f"run {i + 1}: shell produced no output (bad --cmd?)",
                  file=sys.stderr)
            continue
        if not args.quiet:
            print(f"run {i + 1}: first={first} ms  last={last} ms")
        if i < args.drop_first:
            continue
        firsts.append(first)
        lasts.append(last)
        prompts.extend(per)

    if not firsts:
        print("no usable run", file=sys.stderr)
        return 1

    print()
    print(f"first prompt  median {statistics.median(firsts):.0f} ms  "
          f"min {min(firsts)}  max {max(firsts)}  (n={len(firsts)})")
    print(f"fully ready   median {statistics.median(lasts):.0f} ms  "
          f"min {min(lasts)}  max {max(lasts)}")
    if prompts:
        print(f"per prompt    median {statistics.median(prompts):.0f} ms "
              f"min {min(prompts)}  max {max(prompts)}  (n={len(prompts)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
