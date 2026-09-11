# Wheelchair 1.2.1 maturation proof

## Release thesis

1.2.1 intentionally improves the physical WHEX/structural-WH realization without changing the 1.2.0 human surfaces or canonical semantics.

The new rule is **Interior Periodic Composition Erasure**:

1. recognize dynamic `periodic(expr,n)` as canonical modulo;
2. prove `expr = c*axis + q*n + d` in integer affine algebra;
3. erase the exact `q*n` ring term;
4. compose `c*axis+d` with the current logical root coordinate;
5. prove the composed coordinate lies in `[0,n)` for every active lane of the already-proven interior vector region;
6. erase physical dynamic modulo only after that proof;
7. retain the full boundary modulo implementation otherwise.

No workload, solver, benchmark, coefficient or modulus name participates in the decision.

## Correctness and conservative control

`test_121.sh` reports:

```text
INTERIOR_PERIODIC_DIFFERENTIAL_CASES=57
INTERIOR_PERIODIC_EXECUTOR_EQUIVALENCE=PASS
INTERIOR_PERIODIC_AVX512F_EQUIVALENCE=PASS
INTERIOR_PERIODIC_REFERENCE=PASS
INTERIOR_PERIODIC_MODULO_ERASURE=PASS
BOUNDARY_PERIODIC_SEMANTICS_RETAINED=PASS
INTERIOR_PERIODIC_UNPROVEN_CONTROL_RETAINED=PASS
INTERIOR_PERIODIC_NO_WORKLOAD_DISPATCH=PASS
INTERIOR_PERIODIC_SCALAR_FALLBACK=0
WHEX_INTERIOR_PERIODIC_COMPOSITION_1_2_1=PASS
```

The positive witness uses safe `periodic(i-1,n)` and `periodic(i+1,n)` neighborhoods. The negative control uses `periodic(i-2,n)`, which is not valid for every lane of the current interior contract and therefore retains dynamic modulo.

## Mature Newton/Jv regression

`test_newton_jv_121.sh` freezes the established checksums at 10M and 100M for 1/2/4 executors and proves direct-canonical/native identity:

```text
NEWTON_JV_FRONTEND_ERASURE=PASS
NEWTON_JV_10M_100M_EXECUTOR_EQUIVALENCE=PASS
NEWTON_JV_NO_WORKLOAD_DISPATCH=PASS
WHEX_NEWTON_JV_REGRESSION_1_2_1=PASS
```

The Python human surface therefore does not enter timed execution and does not change the native image.

## Machine-code effect

For the mature Newton/Jv one-executor generated image, compared with 1.2.0:

```text
VCVTTPD2QQ: 4 -> 2
VPMULLQ:    10 -> 6
generated RX payload: 1305 -> 1209 bytes
```

The proven interior loses the two dynamic `%n` neighbor quotient/correction paths. Boundary code retains exact periodic semantics.

## Same-host performance evidence

See `PERFORMANCE_1_2_1_NEWTON_RESTORATION.md`.

On the current Xeon Platinum 8370C host, 21-run shuffled/interleaved medians show 1.2.1 faster than both reconstructed matched expert C and the explicit AVX-512 C control at all six 10M/100M × 1/2/4 points. The 100M 1.2.0 -> 1.2.1 speedup is approximately 1.90x to 2.24x.

Performance evidence is a release-supporting measurement, not a universal language claim.

## Surface/canonical preservation and intentional native-baseline movement

1.2.1 changes native code intentionally, so the 1.2.0 requirement that native ELFs equal the older 1.0.15 byte baseline no longer applies. The charter explicitly permits a native baseline update after correctness, topology and performance proof.

The 1.2.0 WH/WHEX surface sources and curated canonical hashes remain frozen. Updated equivalence gates require:

```text
WHEX_1_2_0_SURFACE_SOURCE_FREEZE=PASS
WHEX_1_2_0_CANONICAL_FREEZE=PASS
WH_WHEX_CANONICAL_EQUIVALENCE=PASS
WH_WHEX_NATIVE_BYTE_EQUIVALENCE=PASS
WH_SERIAL_INTRODUCTION_REPORT_ZERO=PASS
WH_WHEX_SURFACE_EQUIVALENCE_1_2_1=PASS
```

Thus WH and WHEX remain equal surfaces over the same improved physical realizer.

## Inherited architecture gates

The final implementation was rerun through the established component gates, including:

```text
WHEELCHAIR_TESTS=PASS
WHEX_SURFACE_ERASURE=PASS
WHEX_CANONICAL_IR_IDENTICAL=PASS
WHEX_MACHINE_CODE_IDENTICAL=PASS
TENSOR_HIDDEN_SCALAR_FALLBACK=0
RESOURCE_SCHEDULER_CONNECTED=PASS
COMPUTATION_ELIMINATION=PASS
ELIMINATION_PARALLEL_WIDTH_PRESERVED=PASS
COMMUNICATION_ELIMINATION=PASS
COMMUNICATION_NO_GLOBAL_SYNC=PASS
RUNTIME_ERASURE=PASS
SERIAL_SPINE_ERASURE=PASS
CENTRAL_SPAWN_LOOP=0
CENTRAL_WAIT_LOOP=0
CENTRAL_REDUCTION_LOOP=0
GLOBAL_TASK_QUEUE=0
OPERATOR_PERIODIC_DIFFERENTIAL_CASES=89
OPERATOR_SUBSPACE_1_0_11_FIX=PASS
OPERATOR_SPAN_MATURE_1_0_11=PASS
GENERALIZED_STRUCTURAL_ALGEBRA_1_0_12=PASS
WHEX_TRUE_PARALLEL_1_0_13=PASS
WHEX_ISA_CAPABILITY_GENERALIZATION_1_0_14=PASS
WHEX_VECTOR_REGION_PARTITION_1_0_15=PASS
```

Legacy general WH was also rechecked through mixed numeric, topology recovery, FEM native equivalence, feature showcase, and conservative dynamic-complex rejection component gates.

## No hidden Von-Neumann fallback

The release preserves:

```text
call eval_slot = 0
scalar tensor fallback = 0
central spawn loop = 0
central wait loop = 0
central reduction loop = 0
global task queue = 0
```

Resource or proof failure never authorizes scalar tensor execution or a general-lane retry.

## Technical Peak Preservation Contract

`GENERAL_TRUE_PARALLEL_CHARTER_1_1_0.md` now explicitly forbids generalization from flattening an established technical performance peak. The 1.2.1 Newton/Jv restoration is the reference proof: the lost periodic affine relation was promoted into generic structural algebra rather than reintroduced as a workload-specific fast path. Future releases must retain a peak-regression corpus and either preserve or improve each mature native envelope.

## Lane identity is not fuzzy-repaired

Final release validation exposed and fixed a surface-routing ambiguity: a damaged legacy identifier fragment could previously be one edit away from a structural keyword and therefore influence compiler-lane selection. 1.2.1 now treats lane identity as a semantic boundary. Exact structural vocabulary is decisive; when no exact marker exists, at least two independent line-leading structural-keyword repair witnesses are required before selecting the structural lane. Ordinary one-character repair remains available *after* the lane is selected.

This preserves both legacy WH typo repair and WH/WHEX structural typo equivalence while preventing spelling repair from silently changing the execution model. The final monolithic release harness completed with `RC=0` and `WHEELCHAIR_1_2_1_COMPLETE=PASS`.
