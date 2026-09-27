# Wheelchair 1.0.9 Runtime-Erasure Performance Evidence

This file records evidence, not a universal language ranking.

## Host/control

The current benchmark host exposes CPUs 0-4 with cgroup quota `400000/100000` (four sustained CPUs). Parent measurement process is pinned to CPU 4; one-executor contestants are pinned to CPU 0; four-executor contestants are allowed CPUs 0-3. Timing uses a small `fork/exec + wait4 + CLOCK_MONOTONIC_RAW` C harness, with no Python polling in the timed path.

Workload: the same periodic heat/stencil topology used in the 1.0.8 Rust memory duel, `N=16,777,216`. All contestants return `checksum_bits=0x4167fc0000000000`.

## 1.0.9 vs 1.0.8 A/B

51 interleaved measured rounds after warmup:

```text
1 executor:
  1.0.9 median 133.547074 ms
  1.0.8 median 132.671016 ms

4 executors:
  1.0.9 median 75.207969 ms
  1.0.8 median 75.539128 ms
```

The time difference is within the noisy near-parity boundary on this host. 1.0.9 does not claim a robust speedup from this A/B run.

## Peak resident memory

A tight `/proc/<pid>/status` sampler is used only for RSS, not timing. Seven runs at `N=100,000,000` observed:

```text
                 1 executor   4 executors
Wheelchair 1.0.9     28 KiB       40 KiB
Wheelchair 1.0.8    104 KiB      116 KiB
```

This is consistent with the structural release claim: fixed evaluator arenas, global partial/summary buffers, and fixed child-stack BSS no longer exist in 1.0.9.

## Rust control, current host

The same Rust 1.98.0 sources were rebuilt with aggressive native flags (`-C opt-level=3 -C target-cpu=native -C lto=fat -C codegen-units=1 -C panic=abort -C strip=symbols`). In a 15-round interleaved run:

```text
1 executor / process:
  WHEX 1.0.9 direct       135.016451 ms
  Rust natural safe       185.632934 ms, ~263 MiB maxrss
  Rust expert fused safe   43.012398 ms, ~820 KiB median maxrss
  Rust no_std unsafe       39.775441 ms, wait4 RSS below useful floor

4 executors/threads:
  WHEX 1.0.9 direct        71.014137 ms
  Rust expert safe 4       27.732272 ms, ~952 KiB maxrss
```

Interpretation: 1.0.9 greatly reduces its own runtime memory floor, but expert fused Rust still wins this workload's execution-time contest. Natural safe Rust remains substantially more memory-hungry. These results prevent a Sandbag Benchmark claim and keep the optimization target visible.
