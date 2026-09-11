# Wheelchair 1.2.1 release proof

## Final status

The final source tree completed the monolithic release harness with:

```text
RC=0
WHEELCHAIR_1_2_1_COMPLETE=PASS
```

The full observed output is retained in `RELEASE_GATES.txt`.

## 1.2.1 native restoration

The release adds generic Interior Periodic Composition Erasure. Proven interior affine periodic coordinates may erase redundant dynamic modulo only after range proof. Boundary regions retain exact periodic semantics. No Newton/Jacobian/workload-name dispatch exists.

The mature Newton/Jv regression retains the established bitwise checksums at 10M and 100M for 1/2/4 executors, and direct canonical compilation produces the same ELF as the Python WHEX surface.

## Technical Peak Preservation Contract

`GENERAL_TRUE_PARALLEL_CHARTER_1_1_0.md` now makes technical-peak preservation a release invariant. Generality may not flatten a previously demonstrated native-performance peak into a slower common denominator. A lost narrow optimization must be promoted into generic structural algebra and recovered for every program satisfying the same proof.

The Newton/Jv restoration is the reference case: the missing periodic affine relation was generalized rather than restored as a benchmark-specific fast path.

## Lane identity hardening

Compiler-lane identity cannot be changed by a single fuzzy spelling coincidence. Exact structural markers are decisive; otherwise at least two independent repairable structural markers are required to select the structural lane. Typo repair continues inside the already-selected lane.

This simultaneously preserves legacy WH auto-repair and WH/WHEX structural typo equivalence.

## True-parallel invariants retained

The final harness reconfirmed, among other gates:

```text
TENSOR_HIDDEN_SCALAR_FALLBACK=0
PARALLEL_SCALAR_FALLBACK=0
RUNTIME_ERASURE=PASS
SERIAL_SPINE_ERASURE=PASS
CENTRAL_SPAWN_LOOP=0
CENTRAL_WAIT_LOOP=0
CENTRAL_REDUCTION_LOOP=0
GLOBAL_TASK_QUEUE=0
COMMUNICATION_NO_GLOBAL_SYNC=PASS
WH_SERIAL_INTRODUCTION_REPORT_ZERO=PASS
WH_DYNAMIC_WHILE_NO_SERIAL_FALLBACK=PASS
INTERIOR_PERIODIC_SCALAR_FALLBACK=0
```

## Surface equivalence retained

WH and WHEX remain equivalent structural surfaces over the same native realizer:

```text
WH_WHEX_CANONICAL_EQUIVALENCE=PASS
WH_WHEX_NATIVE_BYTE_EQUIVALENCE=PASS
WH_WHEX_SURFACE_EQUIVALENCE_1_2_1=PASS
```

## Package hygiene

The release package is generated only after tests, then all build products and Python caches are removed. The final archive contains source/evidence only and is re-extracted and checked against its internal `SHA256SUMS` manifest.
