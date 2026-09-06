# Wheelchair 1.0.12 Structural-Algebra Maturation Proof

## Release boundary

This proof records the 1.0.12 WHEX/native structural compiler state. It inherits the 1.0.9 runtime/serial-spine erasure gates and the 1.0.11 operator-span/constant-pressure gates.

## Final correctness defect repaired

The final blocking case was a dynamic indexed coordinate of the form:

```text
(17*i + 3) % n
```

The generalized affine-modulo recognizer was intended to prove integer expressions in the form:

```text
c*axis + q*n + d
```

but its multiplication branch accidentally called the floating-point literal matcher used by f64 coefficient lowering. A typed u64 literal such as `17` therefore failed the structural proof before native modulo realization.

1.0.12 changes that branch to recognize `mul(u64_literal, expr)` and `mul(expr, u64_literal)` directly with `expr_literal_u64`, then recursively combines the resulting `(c,q,d)` tuple using checked integer arithmetic.

The fix is structural and type-driven. No workload identity is inspected.

## Dynamic modulo native contract

For an accepted expression, the compiler proves:

- non-negative runtime numerator over the declared input range;
- integer magnitude below the exact-conversion / reciprocal-rounding bound;
- external modulo extent `n` is the proven denominator;
- SIMD realization remains vectorized through quotient estimate, exact-multiple correction, and unsigned remainder selection.

The runtime has no scalar tail or scalar boundary oracle. Final partial blocks are masked in AVX-512.

## 1.0.12 regression evidence

Passed in this worktree:

```text
WHEELCHAIR_BUILD=PASS
WHEELCHAIR_TESTS=PASS
WHEX_SURFACE_ERASURE=PASS
WHEX_CANONICAL_IR_IDENTICAL=PASS
WHEX_MACHINE_CODE_IDENTICAL=PASS
RESOURCE_SCHEDULER_CONNECTED=PASS
TENSOR_HIDDEN_SCALAR_FALLBACK=0
COMPUTATION_ELIMINATION=PASS
COMMUNICATION_ELIMINATION=PASS
RUNTIME_ERASURE=PASS
SERIAL_SPINE_ERASURE=PASS
CENTRAL_SPAWN_LOOP=0
CENTRAL_WAIT_LOOP=0
CENTRAL_REDUCTION_LOOP=0
GLOBAL_TASK_QUEUE=0
OPERATOR_PERIODIC_DIFFERENTIAL_CASES=89
OPERATOR_SUBSPACE_1_0_11_FIX=PASS
OPERATOR_POWER_Q1_Q4=PASS
PERIODIC_OPERATOR_RELATION_Q8=PASS
STRICT_AFFINE_VMULPD_BCST=PASS
DYNAMIC_AFFINE_MODULO_DIFFERENTIAL_CASES=58
DYNAMIC_AFFINE_MODULO_NUMERIC=PASS
DYNAMIC_AFFINE_MODULO_EXECUTOR_EQUIVALENCE=PASS
AFFINE_MODULO_QN_SIGNED_OFFSET_CASES=48
AFFINE_MODULO_QN_SIGNED_OFFSET=PASS
STRUCTURAL_ALGEBRA_NO_WORKLOAD_DISPATCH=PASS
GENERALIZED_STRUCTURAL_ALGEBRA_1_0_12=PASS
```

The dynamic modulo quotient/correction arithmetic was additionally stress-checked over 300,000 deterministic random `(n,c,q,d,i)` tuples satisfying the proof domain; every computed remainder matched exact integer `% n` in that stress audit. This stress audit is supporting evidence, while `test_112.sh` is the shipped reproducible release gate.

## Parallelism boundary

1.0.12 does not reintroduce:

- scalar tensor fallback;
- general-lane retry after tensor-native failure;
- central executor spawn/wait/reduction loops;
- global work queue;
- fixed global partial/result arrays.

The release remains AOT and direct-native for the topology lane.

## Scope boundary

The internal structural algebra is more general than the current source grammar, but the shipped WHEX surface remains a one-explicit-axis slice. This release therefore does not claim arbitrary Rank-N source support or complete coverage of nullspace, rank decomposition, Kronecker/TT/Tucker, Krylov, Schur, Woodbury, or multigrid transformations.
