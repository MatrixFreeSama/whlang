# Wheelchair 1.2.11

Wheelchair is a general-purpose AOT language with HPC and simulation as its primary focus.
Version 1.2.11 is a pure-native-assembly corrective release over 1.2.10.

## What 1.2.11 fixes

Wheelchair 1.2.10 completed the pure-assembly production path, but its final native launcher selected only `base` or `derived`. A high structural-pressure tensor graph could therefore be compiled with the base register profile even when the already-mature `wide` physicalizer was the correct AOT capability class.

The coupled fluid-solid benchmark exposed the defect: its canonical graph has 12 distinct structural loads, which belongs to the existing expanded persistent-register interval, yet 1.2.10 selected `base`.

1.2.11 moves resource-profile selection into the native launcher itself. Human WH/WHEX is first lowered in-process by the handwritten assembly surface lowerer to the canonical graph. The launcher then analyzes canonical structural loads and makes exactly one pre-code-generation choice:

```text
Rank-N Cartesian graph        -> derived
0..10 distinct loads          -> base persistent-register profile
11..14 distinct loads         -> wide expanded-register profile
15+ distinct loads            -> base proved vector-recompute profile
```

These thresholds preserve the mature resource-profile contract. Selection is based only on canonical structure. It does not inspect program names, source paths, benchmark identities, timing results, or runtime load.

There is no failure-driven fallback. The compiler does not try base, observe failure, and retry wide.

## Production implementation

```text
WH / WHEX UTF-8 source
        -> handwritten x86-64 surface lowering
        -> canonical data/causality graph
        -> native AOT resource-profile analysis
        -> exactly one base / wide / derived physicalizer
        -> AOT causal-region contraction
        -> static ELF64 machine code
```

The production package contains no Python source and has no Python runtime dependency. `build.sh` uses GNU binutils and POSIX shell utilities only.

## Core parallel rule

```text
Compute locally.
Finish locally.
Release blindly.
```

Completion remains:

```text
OWNED -> FREE
```

Dependency communication may name a true causal neighbor. Resource release may not name a later consumer. Work stealing, fixed runtime home ownership, per-worker work inboxes, global ready queues, root work schedulers, peer-load queries, post-completion work search, resource handoff, runtime profitability selectors, and idle `PAUSE` spinning remain forbidden.

## Build

Linux x86-64 requirements: GNU `as`, `ld`, `nm`, `objcopy`, `objdump`, `readelf`, plus standard POSIX shell utilities.

```sh
./build.sh
```

## Use

```sh
./bin/wheelchairc program.wh -o program --executors 4
./program

./bin/whexc program.whex -o program --executors 4
./program
```

The launcher performs static resource selection before compilation. `topologyc`, `topologyc-wide`, `topologyc-derived`, and the native256 physical capability binaries remain shipped for explicit physical experiments and regression proof.

## 1.2.11 regression gate

```sh
./test_release_native_1211.sh
```

The gate verifies base/wide/recompute thresholds, FSI pressure-12 wide selection at Q1/Q2/Q4, Rank-N derived priority, byte identity between automatic and explicit physicalizer selection, core general/iterate behavior, feature-showcase erasure, multilingual surface, conservative auto-repair, dynamic rejection, static ELF output, Python-free production build, and recipient-blind resource release.
