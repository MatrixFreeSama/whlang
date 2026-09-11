# Wheelchair 1.2.3 Mature Proof

## Release thesis

Wheelchair 1.2.3 adds a generic Global Coupled Operator semantic layer and a
proof-gated Sparse Causal Expansion planner inspired by the decomposition idea
of Laplace expansion without cofactor/minor enumeration.

The release is not Newton-specific and does not add a named-workload backend.
The new planner consumes only weighted coupling topology and conservative
amplification budgets.

## New mature capability

`surface/sparse_causal_expansion.py` provides:

- deterministic weighted coupling-graph normalization;
- bounded separator discovery;
- exact small-graph separator search plus bounded BFS-frontier search;
- disconnected-interior proof after separator removal;
- binary separator composition;
- Causal Separator Signature boundary records;
- zero duplicate region expansion;
- structural recipe DAG deduplication without numeric-state aliasing;
- conservative work/storage/communication amplification gates;
- explicit rejection when a required bounded separator is not proved;
- structural hashes invariant to node renaming when topology/recipes are
  isomorphic.

## Language integration

`tools/apply_123.py` deterministically extends the frozen 1.2.2 WHEX semantic
planner. WH and WHEX therefore share the same operator proof layer through the
existing semantic planner.

The integration adds no runtime operator type tags, separator-plan objects, or
workload dispatch. Region names and separator metadata are absent from canonical
native bytes.

## 1.2.3 authority gates

The strict release gate is `test_sparse_causal_expansion_123.sh`. Its required
results include:

```text
GLOBAL_OPERATOR_NO_WORKLOAD_DISPATCH=PASS
SPARSE_CAUSAL_EXPANSION_CHAIN31=PASS
SPARSE_CAUSAL_EXPANSION_DUPLICATE_REGION_EXPANSIONS=0
SPARSE_CAUSAL_EXPANSION_BINARY_DAG=PASS
SPARSE_CAUSAL_EXPANSION_BOUNDED_AMPLIFICATION=PASS
GLOBAL_OPERATOR_NAME_ERASURE=PASS
SPARSE_CAUSAL_EXPANSION_UNPROVEN_DENSE_REJECT=PASS
SPARSE_CAUSAL_EXPANSION_WORK_AMPLIFICATION_REJECT=PASS
SPARSE_CAUSAL_EXPANSION_NO_REPEATED_MINOR_SUBPROBLEM=PASS
WHEX_GLOBAL_OPERATOR_SCE_PLAN=PASS
WHEX_GLOBAL_OPERATOR_REGION_NAME_ERASURE=PASS
WH_WHEX_SHARED_GLOBAL_OPERATOR_ALGEBRA=PASS
GLOBAL_OPERATOR_NATIVE_REFERENCE_1_2_4_EXECUTORS=PASS
GLOBAL_OPERATOR_RENAMED_NATIVE_BYTE_EQUIVALENCE=PASS
GLOBAL_OPERATOR_RUNTIME_METADATA_ERASURE=PASS
GLOBAL_OPERATOR_SCALAR_FALLBACK=0
GLOBAL_OPERATOR_CENTRAL_SPAWN_LOOP=0
GLOBAL_OPERATOR_CENTRAL_WAIT_LOOP=0
GLOBAL_OPERATOR_CENTRAL_REDUCTION_LOOP=0
GLOBAL_OPERATOR_NON_NEIGHBOR_COMMUNICATION=0
WHEELCHAIR_SPARSE_CAUSAL_EXPANSION_1_2_3=PASS
```

## Historical peak protection

`test_complete_123.sh` derives and reruns the complete 1.2.2 release authority,
changing only the obsolete whole-file `whex_semantics.py` SHA assertion. The
replacement gate preserves the old canonical/native behavior and then proves the
new semantic layer is erased from runtime.

The final release must therefore report both:

```text
WHEELCHAIR_1_2_2_COMPLETE=PASS
WHEELCHAIR_1_2_3_COMPLETE=PASS
```

and retain the old 1.2.1 Newton/Jv and Interior Periodic technical-peak gates as
well as the 1.2.2 Rank-N gates.

## Claim boundary

This release claims a mature generic compile-time separator/signature algebra,
its WH/WHEX semantic integration, and zero-runtime-cost metadata erasure on the
current native domain.

It does not claim a finished arbitrary-runtime CSR/COO importer or a fully native
generic Schur-complement solver. Those require a later physical-realization proof
and may not be silently inferred from this release.
