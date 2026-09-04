# Wheelchair 1.2.1

Wheelchair 1.2.1 is a native-realization maturation release over the 1.2.0 WH/WHEX unified structural core. Human WH/WHEX surface semantics and canonical graphs remain frozen; the native topology compiler intentionally improves how proven interior periodic affine coordinates are realized.

The new generic **Interior Periodic Composition Erasure** rule normalizes `periodic(expr,n)` as `c*axis + q*n + d`, removes the `q*n` ring term, and erases the physical modulo only when interval proof establishes that the remaining affine residue already lies in `[0,n)` for every active lane of a proven interior vector region. Boundary regions retain exact periodic semantics, and unproved cases remain untouched.

This release therefore updates the old native byte baseline intentionally. The non-regression contract becomes: surface/canonical bytes remain stable; WH/WHEX equivalent programs still produce byte-identical ELFs to each other; native bytes may move only behind correctness, topology, no-specialization, and same-host performance gates.

The source relationship is now:

```text
WH familiar/inference surface ─┐
                              ├─> Unified Structural Semantic Core -> topologyc -> native ELF
WHEX explicit expert surface ─┘
```

For the current mature shared semantic set, release gates require canonical byte identity, and native-capable equivalent pairs require complete ELF byte identity. WH `for` becomes an Axis map or reduction, WH `if` becomes predicate/dataflow `select`, and dynamic WH `while` explicitly rejects until a genuine recurrence/fixed-point topology exists. Sequential-looking syntax is never permission for a hidden sequential fallback.

See `WH_WHEX_EQUIVALENCE_1_2_0.md` and `surface/SURFACE_SPEC.md`.


## 1.2.1 interior periodic composition erasure

The 1.0.15 boundary/interior split proved that an interior vector block contains only physical root lanes `1..n-2`. 1.2.1 now propagates that fact through dynamic periodic indexing. For an index normalized to `c*axis + q*n + d`, modulo arithmetic first erases the exact `q*n` term. The compiler then proves the composed affine residue range against the current interior domain. Only when every lane is already in `[0,n)` is the runtime `% n` quotient/correction removed.

The rule is property-driven. It contains no Newton, Jacobian, stencil, coefficient, modulus, benchmark, or opponent-name dispatch. A `periodic(i+n-2,n)` control remains unoptimized under the current interior contract because the first interior lane can make `i-2` negative.

The release gate `test_121.sh` checks 57 extents, one/four executors, AVX-512DQ and forced AVX-512F foundation realization, direct small-size mathematical references, machine-code modulo erasure in the proven case, retained modulo in the unproved control, zero scalar fallback, and zero workload dispatch. `test_newton_jv_121.sh` additionally freezes the mature Newton/Jv checksums and proves that bypassing the Python WHEX surface and feeding the canonical graph directly to the handwritten topology compiler produces byte-identical ELFs.

See `PERFORMANCE_1_2_1_NEWTON_RESTORATION.md` and `MATURE_1_2_1_PROOF.md`.

## 1.2.0 WH/WHEX surface equivalence

The new `surface/wh_structural.py` is intentionally outside WHEX. Existing WHEX parser/semantic/compiler/runtime files are frozen to their 1.1.0 hashes. The WH compiler selects the structural lane before native compilation when structural declarations are present. Structural failure is terminal and is never retried through the legacy general lane. Legacy `.wh` continues through the existing general/GTR path.

The 1.2.0 equivalence gate proves that all currently accepted WHEX test/example programs are also accepted by the WH structural parser with byte-identical canonical graphs; intentional WHEX semantic rejection remains rejection. Familiar WH `for`, `+=`, `if`, pure function, record, region and Rank-N examples canonicalize to their explicit WHEX peers, and native-capable pairs generate byte-identical ELFs.

## 1.1.0 general true-parallel semantics

New WHEX source constructs include first-class `axis`, `pure [generic] fn`, compile-time
`record`, and `region ... effect pure parallel { ... }`. Functions specialize and
inline before canonical IR; records and region/effect metadata are compile-time-only.
The release gate requires high-level and manually inlined equivalents to generate
byte-identical canonical graphs and byte-identical ELFs.

The compiler now emits a `wheelchair.whex.semantic/1` plan containing binding and region
dependency graphs, independent pairs, critical dependency depth, ownership read/write
sets, control/predicate structure, erasure counters, parallelism contracts, and an
explicit Serial-Introduction Report. Current pure-lane serial-introduction counters
must all remain zero.

Rank-N syntax is preserved through semantic proof. 1.1.0 implements a first genuine
Rank-N native lowering for sum reductions whose extra axes are proven irrelevant: the
axes are algebraically removed and their multiplicity is folded into the expression
before the existing rank-1 native realizer runs. A genuinely used extra axis is not
flattened into a serial nest; it is preserved and explicitly rejected until a native
Rank-N physical realizer exists.

Effect categories are recognized (`pure`, `local_state`, `region_write`,
`shared_state`, `atomic`, `io`, `device`, `external`), but only `pure` has a completed
WHEX native realization in 1.1.0. Unsupported effects reject rather than introducing
hidden locks, queues, or sequential dispatch.

The complete design and invariants are frozen in
`GENERAL_TRUE_PARALLEL_CHARTER_1_1_0.md`, while the exact human syntax and current
claim boundary are in `surface/WHEX_SPEC.md`.

## Non-regression rule

1.1.0 intentionally does not change the 1.0.15 physical backend for existing kernels.
The release gate freezes the existing periodic-heat ELF SHA-256
`76404fbc1a3b54c7b829a01f44e4716ebcf6db3ec7b441504636e4c5a8c2e0ab` and checksum
`0x4167fc0000000000`. Thus this semantic expansion cannot consume existing performance
through extra runtime machinery.

## 1.0.15 vector boundary/interior region partition

The generated fused vector episode now separates global boundary conditions from a proven interior region without converting boundary elements into scalar work. For each vector block, the episode chooses between two mutually exclusive width-8 native bodies:

- **boundary vector region**: retains the complete source `select` / predicate semantics for the first block, final block, and masked final tail;
- **proven interior vector region**: uses the already-established interior proof to erase source predicates that are mathematically false for every active lane.

The partition is derived from axis/domain facts, not from workload names. The interior body can therefore reuse affine relations and cross-vector induction carriers that global boundary selects would otherwise obscure. Both bodies converge into the same masked reduction and causal executor fabric. Runtime still enters the generated evaluator once per chunk, and the tensor runtime still contains zero scalar evaluator calls.

The shipped `test_115.sh` release gate checks awkward vector widths, chunk boundaries, one/four executors, native AVX-512DQ and forced AVX-512F foundation realizations, direct mathematical references for small cases, machine-code predicate erasure in the proven interior body, retained predicate semantics in the boundary body, zero scalar fallback, and zero workload-name dispatch.

## 1.0.14 ISA capability generalization

The compiler derives semantic capability bits from CPUID classes instead of treating AVX2/AVX-512F/DQ/VL as monolithic language features. Current capabilities include vector width, predication, masked tail, broadcast, gather, FMA, i64 vector multiply, i64/f64 conversion, predicate-to-i64-mask materialization, cross-vector state, and reduction-tree support.

For the current 512-bit WHEX realizer:

- AVX-512VL is no longer a semantic requirement;
- AVX-512DQ `VPMULLQ` may be replaced exactly by an AVX-512F `VPMULUDQ`/shift/add recipe;
- signed i64 -> f64 conversion may be synthesized from exact 32-bit decomposition plus AVX-512F `VCVTDQ2PD`;
- a property-proven nonnegative f64 -> u64 truncate used by exact modulo lowering may be synthesized without `VCVTTPD2QQ`;
- predicate -> all-ones/zero i64 vectors may be synthesized with AVX-512F predicated `VPBROADCASTQ`;
- native-DQ and forced AVX-512F-foundation targets are differential-tested on control-heavy heat, sparse nonlinear, dynamic-modulo, and FEM structures;
- AVX2 contributes capabilities to the model, but the current release does not claim a completed 256-bit WHEX tensor realizer. An AVX2 ceiling is rejected explicitly rather than scalar-emulated.

The architectural rule is capability-driven: instruction-set names select physical recipes only. They do not change WHEX mathematics, structural proofs, workload dispatch, or parallel width.

## 1.0.13 true-parallel maturation

### Cross-vector axis induction

A proven affine integer coordinate is no longer necessarily rebuilt from the root axis on every eight-lane vector block. The compiler may reserve a persistent carrier from the same ownership pool used by topology CSE.

For a coordinate such as:

```text
17*i + d
```

one carrier is initialized once from the first vector root and then advances by:

```text
17 * 8 = 136
```

per vector block. Carrier allocation is structural and coefficient-driven. If no carrier is available, lowering remains ordinary AVX-512 arithmetic; it never becomes a scalar loop.

### Evaluator-loop fusion

The generated vector evaluator now owns the complete chunk episode. The runtime calls the generated evaluator exactly once per chunk, rather than once per eight-point block. The generated code contains its own back edge, masked final block, local carrier reduction, root-axis progression, and affine-induction progression.

### Cross-vector constant residency

Immutable ZMM26..31 constants remain initialized once per worker and survive across fused episodes. Dynamic exact-modulo invariants derived from `n` are established once per chunk episode, not once per vector block. Induction-carrier increments are kept as exact qword broadcast constants.

### Parallelism contract

A WHEX/tensor region that reaches the topology lane is vector-authoritative:

- no tensor scalar oracle is emitted into the final image;
- no `call eval_slot` exists in the tensor runtime path;
- no per-vector `call eval_vec4` loop exists;
- the final 1..7 lanes are handled by AVX-512 masking;
- a non-vector tensor realization is a contract violation / compile rejection, not a hidden scalar fallback;
- executor reduction remains the distributed causal fan-in tree inherited from 1.0.9.

## Generalized structural algebra inherited from 1.0.12

WHEX continues to use common structural machinery rather than named solver fast paths:

- affine/modular coordinates use the exact form `c*axis + q*n + d`;
- canonical operator directions retain source, affine transform, and modulo domain;
- compatible periodic operator composition uses exact modular integer algebra;
- recursive homogeneous-linear maps collapse into a canonical coefficient/direction span when proven;
- speculative structural lowering is transactional, including code cursor, CSE ownership, constants, fixups, axis context, scheduling state, and 1.0.13 induction-carrier ownership;
- dynamic affine modulo lowering remains vector-native for proven u64 forms;
- constant pressure changes physical realization only, never mathematical semantics.

No compiler/runtime dispatch condition contains benchmark, heat, stencil, FEM, projector, Toeplitz, Krylov, Rust, or solver names.

## Parallel architecture inherited from 1.0.9

- no central spawn-all loop;
- no central wait-all loop;
- no central/global reduction sweep;
- no global task queue;
- no global chunk-partial or worker-summary array;
- direct dependency children are joined locally;
- executor-local reduction uses the logarithmic binary-carry frontier;
- generated arithmetic occupies an exact-size RX segment with direct rel32 AOT entry patches.

## Current scope boundary

The WHEX human grammar is no longer limited to a one-axis shell: 1.1.0 exposes
first-class axis declarations, pure/generic structural functions, compile-time records,
and explicit pure parallel regions. Rank-N structure is preserved in semantic planning,
and one generic class of irrelevant reduction axes is actually eliminated to the
existing rank-1 native realizer.

The physical tensor realizer is still rank-1. A used extra Rank-N axis, mutable/shared
effects, I/O/device/external effects, runtime closures, and runtime aggregate storage do
not receive fake fallbacks. They reject until a topology-native realization exists.

The architectural rule is stronger than a list of algorithms or language features:
new semantics must extend common Axis/Region/Effect/Dependency/Control machinery and
must pass erasure, parallelism, serial-introduction, and machine-code non-regression
gates.

## Verification

Primary component gates:

```sh
./test.sh
./test_whex.sh
./test_scheduler.sh
./test_elimination.sh
./test_communication.sh
./test_109.sh
./test_operator_subspace_1011.sh
./test_operator_span_mature_1011.sh
./test_112.sh
./test_true_parallel_113.sh
./test_114.sh
./test_115.sh
./test_whex_semantic_parallel_110.sh
```

`test_true_parallel_113.sh` freezes the four 1.0.13 true-parallel requirements. `test_114.sh` freezes the 1.0.14 ISA capability algebra, AVX-512F foundation recipes, native/foundation differential equivalence, AVX-512VL independence, AVX2 explicit-reject boundary, and zero scalar emulation. `test_115.sh` freezes vector boundary/interior partitioning, per-region machine-code invariants, boundary correctness, executor/foundation equivalence, and zero scalar boundary fallback. `test_whex_semantic_parallel_110.sh` freezes 1.1.0 high-level abstraction erasure, multilingual equivalence, Rank-N axis elimination, no-fake-flatten rejection, Region/Effect/Ownership topology, zero serial introduction, and the 1.0.15 native machine-code baseline.
