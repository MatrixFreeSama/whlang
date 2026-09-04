# Wheelchair 1.0.15 Vector-Region Maturation Proof

## Scope

1.0.15 adds a generic vector boundary/interior region partition above the fused true-parallel episode of 1.0.13 and the ISA-capability algebra of 1.0.14.

The optimization answers a structural question: when source predicates exist only because a finite domain has exceptional boundary points, must every vector block carry those predicates? 1.0.15 proves when an entire active vector block lies in the non-boundary interior and emits a separate interior realization for that region.

This is not workload dispatch. Compiler/runtime sources contain no heat, stencil, MoonBit, Rust, projector, Krylov, Toeplitz, or benchmark-name condition selecting the transformation.

## Physical realization

The generated fused evaluator contains two mutually exclusive width-8 bodies:

1. **Boundary vector body**
   - used for the first block and any block whose active range reaches the domain end;
   - retains the complete source predicate/select semantics;
   - the final 1..7 lanes remain AVX-512 masked lanes, never scalar elements.

2. **Proven interior vector body**
   - entered only after the block range is proven to lie strictly inside the source domain;
   - enables the existing `INTERIOR_PROVEN` expression facts;
   - erases predicates that are mathematically false throughout that active vector block;
   - exposes affine index relations to the existing induction/CSE machinery.

Both bodies converge before the same masked reduction, root-axis progression, induction progression, and generated backedge. The runtime still performs one generated-evaluator call per chunk and contains zero `call eval_slot` sites.

The scalar `rsi` chunk position used by the generated discriminator is region metadata only. It does not evaluate tensor elements. Mathematical element work remains vector-authoritative.

## Correctness validation

`test_115.sh` covers 57 deterministic sizes including sub-vector shapes, vector boundaries, non-multiples of eight, executor/chunk boundaries around 65536/131072/262144, and deterministic random extents. It checks:

- one-executor vs four-executor numerical equivalence;
- native AVX-512DQ vs forced AVX-512F-foundation equivalence;
- direct mathematical reference values for small cases;
- exact predicate erasure from the proven-interior generated region;
- retained predicate machinery in the boundary-vector region;
- affine-relation reuse in the interior region;
- zero scalar boundary fallback;
- zero workload-name dispatch.

Observed release-gate output:

```text
BOUNDARY_REGION_DIFFERENTIAL_CASES=57
BOUNDARY_REGION_EXECUTOR_EQUIVALENCE=PASS
BOUNDARY_REGION_AVX512F_EQUIVALENCE=PASS
BOUNDARY_REGION_REFERENCE=PASS
PROVEN_INTERIOR_PREDICATE_ERASURE=PASS
BOUNDARY_VECTOR_SEMANTICS_RETAINED=PASS
INTERIOR_AFFINE_RELATION_REUSE=PASS
BOUNDARY_REGION_SCALAR_FALLBACK=0
BOUNDARY_REGION_NO_WORKLOAD_DISPATCH=PASS
WHEX_VECTOR_REGION_PARTITION_1_0_15=PASS
```

## Inherited parallelism and architecture gates

The final 1.0.15 worktree was re-run through the inherited component gates. They preserve:

```text
TENSOR_HIDDEN_SCALAR_FALLBACK=0
PARALLEL_SCALAR_FALLBACK=0
CENTRAL_SPAWN_LOOP=0
CENTRAL_WAIT_LOOP=0
CENTRAL_REDUCTION_LOOP=0
GLOBAL_TASK_QUEUE=0
EVALUATOR_LOOP_FUSION=PASS
CROSS_VECTOR_AXIS_INDUCTION=PASS
CROSS_EPISODE_DYNAMIC_CONSTANT_RESIDENCY=PASS
COMMUNICATION_NO_GLOBAL_SYNC=PASS
ELIMINATION_PARALLEL_WIDTH_PRESERVED=PASS
ISA_GENERALIZATION_SCALAR_FALLBACK=0
```

`test_scheduler.sh` and `test_elimination.sh` were updated only to audit the new mutually exclusive static regions correctly. The previous audit summed both code bodies as if both executed for the same block; the revised audit checks each path independently against the established resource/work bounds.

The monolithic `test_complete.sh` includes `test_115.sh`, but the complete serial harness exceeds the execution-session wall-clock available in this environment. Its component gates were executed individually on the same final source tree. No failed assertion was bypassed.

## Scope boundary

1.0.15 does not claim arbitrary Rank-N source syntax, a complete AVX2 physical tensor backend, or general-language memory safety. The new proof is a vector-domain relation and applies only when the compiler can prove the region facts required by the transformation. Otherwise the exact boundary-capable vector body remains authoritative; there is no scalar fallback.
