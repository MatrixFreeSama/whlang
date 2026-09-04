# Wheelchair 1.0.11 Maturation Proof

This file records the current source-tree regression boundary for the matured 1.0.11 WHEX/native structural compiler.

## Correctness defect repaired

The recursive operator-span collector produced the correct canonical span for Q2:

- `p[i] * 1.0`
- `p[i+1] * 1.0`
- `p[i+2] * 0.25`

The defect was in native realization under immutable-constant register pressure. Once ZMM26..31 were occupied, a newly composed affine offset could fail resident-constant allocation and fall back to ordinary recursive integer lowering. That ordinary path used the physical root axis and could erase the outer symbolic affine offset.

1.0.11 removes that semantic fallback. Non-resident affine constants remain in the existing read-only constant pool and are consumed directly through EVEX qword-broadcast memory operands.

## Required native behavior

- `vpaddq zmm,...,QWORD BCST [rip+const]` handles non-resident affine offsets.
- `vpmullq zmm,...,QWORD BCST [rip+const]` handles non-resident affine coefficients.
- no scalar fallback is introduced by constant-register exhaustion;
- no global task queue, central spawn loop, central wait loop, or central reduction loop is introduced;
- strict mode remains structurally separate and preserves strict evaluation semantics.

## Regression gates passed in this worktree

- `WHEELCHAIR_BUILD=PASS`
- `WHEELCHAIR_TESTS=PASS`
- `WHEX_SURFACE_ERASURE=PASS`
- `WHEX_CANONICAL_IR_IDENTICAL=PASS`
- `WHEX_MACHINE_CODE_IDENTICAL=PASS`
- `RESOURCE_SCHEDULER_CONNECTED=PASS`
- `COMPUTATION_ELIMINATION=PASS`
- `COMMUNICATION_ELIMINATION=PASS`
- `RUNTIME_ERASURE=PASS`
- `SERIAL_SPINE_ERASURE=PASS`
- `CENTRAL_SPAWN_LOOP=0`
- `CENTRAL_WAIT_LOOP=0`
- `CENTRAL_REDUCTION_LOOP=0`
- `GLOBAL_TASK_QUEUE=0`
- `OPERATOR_PERIODIC_DIFFERENTIAL_CASES=89`
- `OPERATOR_PERIODIC_CORRECTNESS_FIX=PASS`
- `OPERATOR_POWER_Q1_Q4=PASS`
- `OPERATOR_POWER_EXECUTOR_EQUIVALENCE=PASS`
- `AFFINE_CONSTANT_PRESSURE_NUMERIC=PASS`
- `AFFINE_CONSTANT_PRESSURE_EXECUTOR_EQUIVALENCE=PASS`
- `AFFINE_CONSTANT_PRESSURE_VECTOR_SPILL=PASS`
- `OPERATOR_SPAN_MATURE_1_0_11=PASS`

The monolithic `test_complete.sh` can exceed the execution-session wall-clock limit because it serially invokes several heavy release gates. Those gates were therefore also executed individually in the same worktree.
