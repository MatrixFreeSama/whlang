# Wheelchair 1.2.4 Mature Generic Native Proof

## Release thesis

Wheelchair 1.2.4 promotes two performance improvements discovered during Global Coupled Operator validation into generic native structural algebra. Neither optimization recognizes Newton, stiffness, FEM, CFD, Poisson, KKT, fluid, solid, or any other workload/physics name.

The accepted pipeline is:

```text
frozen mature native frontend
        -> generic Product-Subtract Contraction
        -> generic Vector Reduction Residency
        -> AVX-512 native realization
```

The frozen handwritten source remains unchanged. The 1.2.4 frontend is derived at build time from the protected source SHA and assembled into the static native compiler.

## 1. Generic Product-Subtract Contraction

For tolerant floating-point programs, the compiler may structurally contract

```text
a - (b * c)
```

into the equivalent admitted fused operation `VFNMADD231PD` when the expression and resource proof succeeds. Strict IEEE mode retains the original multiply/subtract rounding sequence. Resource failure retains the prior all-vector recipe; it never introduces a scalar fallback.

The Global Coupled Operator regression produces:

```text
GENERIC_NATIVE_VFNMADD231PD=4
GENERIC_NATIVE_VMULPD=6
GENERIC_NATIVE_VSUBPD=0
GENERIC_NATIVE_GENERATED_CALL_EDGES=0
```

The mature pre-1.2.4 shape used 10 vector multiplies and 4 vector subtracts for the same operator.

## 2. Generic Vector Reduction Residency

Qualified tolerant reductions retain all eight AVX-512 lane chains in a resident ZMM accumulator across full SIMD blocks. The previous mature recipe extracted and rejoined halves at every block. The resident recipe performs the horizontal collapse only at chunk completion.

Properties:

```text
GENERIC_NATIVE_ZMM_RESIDENT_REDUCTION=1
GENERIC_NATIVE_SCALAR_FALLBACK=0
GENERIC_NATIVE_GENERATED_CALL_EDGES=0
```

There is no runtime workload tag, solver tag, physics tag, carrier dispatcher, central reduction loop, or scalar tail introduced by this optimization.

## 3. Workload-name erasure

The release contains two source programs with identical operator mathematics and dependency structure but deliberately different names: a global stiffness example and a synthetic non-physical twin. Their native outputs are byte-identical at 1, 2, and 4 executors.

```text
GENERIC_NATIVE_NO_WORKLOAD_DISPATCH=PASS
GENERIC_NATIVE_OPERATOR_NAME_ERASURE=PASS
GENERIC_NATIVE_RENAMED_NATIVE_BYTE_EQUIVALENCE=PASS
```

Therefore the optimization is selected by algebraic structure and admitted floating-point semantics, not by the problem name.

## 4. Existing peak preservation

The mature handwritten native sources remain SHA-frozen:

```text
compiler/tensor_frontend_x86_64.S
  e7b05d8c6f401b0d8b7caa6db4016ee39ca3100d6f781ff438375528f3dbd0d6
compiler/topologyc_x86_64.S
  2e83af25b6a6188c9ce24497d636206ca5978e59a92b619e6b722909ad2d4f80
runtime/tensor_runtime_template_x86_64.S
  e9116041c673aec4dca58a43379ccb78d5ae3d6aa7e7ba76656da32b24cdfeb3
```

Newton/Jv does not match the new structural recipe. At 1, 2, and 4 executors its baseline and 1.2.4 native ELFs remain byte-identical:

```text
NEWTON_JV_NATIVE_BYTE_IDENTITY_ON_1_2_4=PASS
INTERIOR_PERIODIC_1_2_1_TECHNICAL_PEAK_PROTECTED=PASS
NEWTON_JV_1_2_1_TECHNICAL_PEAK_PROTECTED=PASS
```

Rank-N and Sparse Causal Expansion remain mature:

```text
WHEELCHAIR_RANK_N_1_2_2=PASS
RANK_N_GENERATED_RX_CALL_EDGES=0
RANK_N_SCALAR_FALLBACK=0
WHEELCHAIR_SPARSE_CAUSAL_EXPANSION_1_2_3=PASS
GLOBAL_OPERATOR_SCALAR_FALLBACK=0
GLOBAL_OPERATOR_CENTRAL_SPAWN_LOOP=0
GLOBAL_OPERATOR_CENTRAL_WAIT_LOOP=0
GLOBAL_OPERATOR_CENTRAL_REDUCTION_LOOP=0
GLOBAL_OPERATOR_NON_NEIGHBOR_COMMUNICATION=0
```

## 5. Native sovereignty

Python is used only as an exact, hash-protected build-time source derivation tool for the Rank-N and 1.2.4 assembly frontends. User-program compilation and generated execution do not use Python, GCC, Clang, LLVM, Rust, a JIT, or a foreign high-level runtime.

```text
GENERIC_NATIVE_BOOTSTRAP_GENERATORS_EXACT=PASS
GENERIC_NATIVE_BOOTSTRAP_BASE_HASH_PROTECTED=PASS
GENERIC_NATIVE_ASSEMBLY_ONLY_BUILD=PASS
GENERIC_NATIVE_NO_FOREIGN_HIGH_LEVEL_BACKEND=PASS
WHEELCHAIR_1_0_9_INVARIANTS_ON_1_2_4=PASS
```

## 6. Same-host performance authority

Performance admission is based only on same-host, same-ISA, same-workload comparisons between the frozen mature frontend and the 1.2.4 frontend. Cross-vendor absolute milliseconds are not an optimizer admission criterion.

Authority run: `33879496682`.

Three AVX-512-qualified hosts completed the full 1.2.4 authority with no qualified failure.

### AMD EPYC 9V74, CPU family 25, model 17, authority slot 3

21 shuffled/interleaved measured runs per case, 3 warmups, 10M/100M points, 1/2/4 executors:

```text
10M / 1:  8.269416 ms -> 6.803471 ms   1.2155x
10M / 2:  7.822310 ms -> 6.712690 ms   1.1653x
10M / 4:  4.515347 ms -> 3.919199 ms   1.1521x
100M / 1: 73.996973 ms -> 59.382319 ms  1.2461x
100M / 2: 70.086688 ms -> 58.701202 ms  1.1940x
100M / 4: 35.763935 ms -> 30.036664 ms  1.1907x
median speedup:  1.1923x
geomean speedup: 1.1935x
```

### AMD EPYC 9V45, CPU family 26, model 2, authority slot 6

```text
10M / 1:  3.968161 ms -> 3.660937 ms   1.0839x
10M / 2:  4.189749 ms -> 3.842281 ms   1.0904x
10M / 4:  2.560269 ms -> 2.379455 ms   1.0760x
100M / 1: 34.868176 ms -> 31.806197 ms  1.0963x
100M / 2: 34.660502 ms -> 31.254942 ms  1.1090x
100M / 4: 17.687577 ms -> 16.036536 ms  1.1030x
median speedup:  1.0934x
geomean speedup: 1.0930x
```

### AMD EPYC 9V74, CPU family 25, model 17, authority slot 10

```text
10M / 1:  8.259318 ms -> 6.771330 ms   1.2197x
10M / 2:  7.844237 ms -> 6.683709 ms   1.1736x
10M / 4:  4.493719 ms -> 3.908673 ms   1.1497x
100M / 1: 73.989130 ms -> 59.304409 ms  1.2476x
100M / 2: 69.998934 ms -> 58.697381 ms  1.1925x
100M / 4: 35.700476 ms -> 30.029920 ms  1.1888x
median speedup:  1.1907x
geomean speedup: 1.1949x
```

All reported numerical spreads between baseline, optimized Wheelchair, and the matched expert-C control were `0.000e+00` in this authority run.

The release performance gate requires both median and geometric-mean same-host baseline speedup to be at least 1.05x on every qualified authority host.

## 7. Rejected experimental recipes

The following experiments are deliberately not part of the 1.2.4 default native lane:

- branch-based striped reduction: no stable gain and adds runtime carrier selection;
- full-block tail-gate fusion: machine-code cleanup was correct, but measured gain was noise-level;
- 2x static fused-block unroll: generated two independent ZMM carriers without runtime dispatch, but measured gain was approximately noise-level and occasionally negative;
- replacing the mature 512-bit physical lane with a 256-bit lane: rejected by the evidence; forced-512 expert C was substantially faster than its compiler-default vector width on tested Intel hosts during the experiment.

Wheelchair therefore keeps only optimizations with demonstrated aggregate benefit and no established-peak regression.

## 8. Final authority

```text
WHEELCHAIR_1_2_3_COMPLETE_ON_1_2_4=PASS
WHEELCHAIR_GENERIC_NATIVE_1_2_4=PASS
WHEELCHAIR_1_2_4_COMPLETE=PASS
WHEELCHAIR_1_2_4_QUORUM=PASS
```

Wheelchair 1.2.4 is a generic native-codegen release. The global stiffness operator is a validation workload, not a privileged backend path.
