# Wheelchair 1.0.13 True-Parallel Maturation Proof

## Scope

This proof records the four WHEX physical-realization upgrades added above the 1.0.12 generalized structural algebra:

1. cross-vector axis induction;
2. evaluator-loop fusion;
3. cross-vector / cross-episode constant residency;
4. a hard no-hidden-scalar parallelism contract.

## Cross-vector induction

The compiler function `vec_induct_get_reg` is keyed only by the proven composed affine coefficient. It allocates from the same ZMM16..25 persistent ownership domain used by topology CSE. Up to two coefficients are retained; lack of a free carrier merely retains ordinary AVX-512 multiplication.

The generated loop advances:

```text
root axis       += 8
coefficient c   += c*8
```

The release probe uses the pre-existing `17*i+3` field only as a metamorphic witness. Disassembly must show the same carrier initialized from ZMM6 by `vpmullq` and later advanced by an exact qword-broadcast constant 136.

## Evaluator-loop fusion

`runtime/tensor_runtime_template_x86_64.S::eval_chunk` performs exactly one `call eval_vec4`. The generated target contains:

- its own forward entry jump to the initialization island;
- its mathematical vector body;
- final-block masking;
- four-carrier reduction;
- root / induction progression;
- a generated backward edge;
- final fan-in and return.

No call instruction exists inside that generated episode.

## Constant residency

ZMM26..31 immutable constants remain initialized by `eval_vec_init` once per worker. ZMM14/ZMM15 dynamic exact-modulo invariants are computed once per chunk immediately before the single fused evaluator entry. Induction increments are interned in the same read-only constant pool and consumed as EVEX qword broadcasts.

## Parallelism contract

Tensor/WHEX lowering has no scalar retry path. Runtime source contains zero `call eval_slot` sites. A non-eight-wide tensor image exits as a contract violation rather than serializing an independent region. Final partial blocks use AVX-512 masks.

The distributed causal executor architecture remains unchanged:

```text
CENTRAL_SPAWN_LOOP=0
CENTRAL_WAIT_LOOP=0
CENTRAL_REDUCTION_LOOP=0
GLOBAL_TASK_QUEUE=0
```

## Transaction safety

Induction count, coefficients, physical-register ownership and the shared cache-register mask are included in the structural transaction state. A rolled-back operator-span attempt therefore cannot leave an induction carrier aliased with a later CSE value.

## Regression result

Observed component gates after the final compiler/runtime changes:

```text
WHEELCHAIR_TESTS=PASS
WHEX_SURFACE_ERASURE=PASS
WHEX_MACHINE_CODE_IDENTICAL=PASS
RESOURCE_SCHEDULER_CONNECTED=PASS
COMPUTATION_ELIMINATION=PASS
COMMUNICATION_ELIMINATION=PASS
WHEELCHAIR_1_0_9_GATES=PASS
OPERATOR_SUBSPACE_1_0_11_FIX=PASS
OPERATOR_SPAN_MATURE_1_0_11=PASS
GENERALIZED_STRUCTURAL_ALGEBRA_1_0_12=PASS
TRUE_PARALLEL_NUMERIC=PASS
TRUE_PARALLEL_EXECUTOR_EQUIVALENCE=PASS
EVALUATOR_LOOP_FUSION=PASS
CROSS_EPISODE_DYNAMIC_CONSTANT_RESIDENCY=PASS
PARALLEL_SCALAR_FALLBACK=0
CROSS_VECTOR_AXIS_INDUCTION=PASS
AFFINE_17_STEP_136=PASS
FUSED_GENERATED_BACKEDGE=PASS
GENERATED_INNER_CALLS=0
TRUE_PARALLEL_NO_WORKLOAD_DISPATCH=PASS
WHEX_TRUE_PARALLEL_1_0_13=PASS
```
