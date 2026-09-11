# Wheelchair 1.2.1

## Theme: recover sovereign-grade periodic-neighborhood structure generically

- Added generic Interior Periodic Composition Erasure in the handwritten tensor frontend.
- `periodic(expr,n)` may erase dynamic modulo only after ring normalization and an explicit interior interval proof.
- Proven interior `periodic(i+n-1,n)` and `periodic(i+1,n)` now become affine `i-1` / `i+1` coordinates; unsafe radius-2 controls retain full modulo.
- The downstream pure-map affine algebra reuses existing cross-vector induction, so neighborhood maps can derive from the same residue family without benchmark-specific code.
- Boundary vector regions retain exact source periodic semantics; scalar boundary/tail fallback remains zero.
- WHEX/WH human surfaces and canonical semantics remain frozen from 1.2.0. Native byte baselines intentionally move because this release improves physical realization. Equivalent WH/WHEX sources still require byte-identical native output to each other.
- Added `test_121.sh`, `test_newton_jv_121.sh`, updated semantic/equivalence gates, and same-host Newton/Jv performance evidence.
- The Python surface is explicitly exonerated by canonical-direct native byte identity at 1/2/4 executors.

# Wheelchair 1.2.0

- Added the independent WH structural-recovery surface `surface/wh_structural.py`; WHEX source/semantic/native files remain byte-frozen to 1.1.0.
- WH can now express the entire currently mature WHEX structural surface with the `.wh` extension and reach byte-identical canonical graphs.
- Added familiar WH `for` element-map syntax that erases to WHEX `field`.
- Added familiar WH `for { total += ... }` reduction syntax that erases to WHEX `sum`; it creates no mutable scalar runtime state.
- Added familiar WH `if { } else { }` expression syntax that erases to canonical `select` and creates no runtime branch-dispatch object.
- WH structural programs share WHEX Axis/Region/Effect/Ownership/Dependency/Control plans and the same Rank-N prove-and-erase/no-fake-flatten policy.
- Dynamic structural `while` is recognized but explicitly rejected until a genuine recurrence/fixed-point topology exists; it never creates a hidden serial backedge or general-lane retry.
- Added `test_wh_equivalence_120.sh`, frozen WHEX 1.1.0 implementation/canonical/native hashes, and WH/WHEX canonical/native byte-equivalence gates.
- Legacy WH general/GTR behavior remains available and regression-tested.

# Wheelchair 1.1.0 Release Notes

## Theme: general high-level semantics without surrendering true parallelism

1.1.0 is a semantic-architecture release over the 1.0.15 native backend.

- added compile-time first-class axis declarations;
- added pure structural functions with generic specialization and zero runtime call objects;
- added compile-time records whose field access erases before canonical IR;
- added explicit Region / Effect / Parallel contracts;
- added binding and region dependency topology with zero synthetic order edges;
- added compile-time unique-output ownership and read/write-set reporting;
- added control-topology reporting for predicate/dataflow `select` semantics;
- added an explicit Serial-Introduction Report whose current pure-lane counters must all remain zero;
- added abstraction/runtime erasure accounting;
- added generic Rank-N reduction-axis elimination when an axis is proven irrelevant;
- non-erasable used Rank-N structure is preserved and explicitly rejected by the current rank-1 realizer rather than flattened into a hidden sequential nest;
- non-pure WHEX effects are recognized but explicitly rejected until a genuine native effect topology exists;
- old WHEX canonical and machine-code identity remains a release gate;
- new high-level abstraction examples must emit byte-identical machine code to manually inlined equivalents;
- the 1.0.15 periodic-heat native ELF is frozen byte-for-byte for this semantic-only release.

The semantic lane does not add a runtime scheduler, runtime record layout, runtime
closure object, borrow table, global lock, scalar tail, scalar boundary path, or
tensor-to-general fallback.

---

# Wheelchair 1.0.15 Release Notes

## Theme: vector boundary/interior region partition

1.0.15 keeps the 1.0.14 ISA-capability algebra and removes a remaining source of hot-loop pollution: global boundary predicates no longer force every vector block to carry boundary selection machinery.

- the fused generated episode partitions each chunk into mutually exclusive boundary-vector and proven-interior vector regions;
- first/final/tail blocks keep the exact source predicate/select semantics;
- interior blocks use domain proof to erase predicates known false for every active lane;
- interior affine relations become visible again to the existing cross-vector induction and structural-CSE machinery;
- both regions remain width-8 vector code and converge into the same masked reduction path;
- no scalar boundary oracle, scalar tail, tensor-to-general retry, central queue, or workload/solver-name dispatch is introduced;
- scheduler and computation-elimination audits now inspect the two mutually exclusive static bodies per execution path instead of incorrectly adding their static instruction counts as simultaneous work;
- `test_115.sh` differentially covers awkward vector sizes, executor chunk boundaries, one/four executors, native-DQ/foundation realizations, direct small-case references, retained boundary semantics, interior predicate erasure, affine-relation reuse, and zero scalar fallback.

A same-host performance audit on the existing periodic heat topology found that this generic region partition is the missing optimization needed to cross a deliberately aggressive hand-written AVX-512 C/FFI ceiling proxy. That proxy is not an actual MoonBit native measurement and is documented separately in `PERFORMANCE_1_0_15_MOONBIT_REVENGE.md`.

---

# Wheelchair 1.0.14 Release Notes

## Theme: ISA capabilities instead of extension-name semantics

1.0.14 keeps the 1.0.13 fused true-parallel WHEX episode and generalizes ISA-specific strengths into semantic capability recipes.

- CPU discovery now derives a capability algebra from AVX, AVX2, FMA, AVX-512F/BW/DQ/VL, BMI2, POPCNT and LZCNT rather than using a single DQ+VL tensor gate;
- the current 512-bit tensor base requires only capabilities actually needed by that physical realizer; AVX-512VL is not required;
- i64 vector multiply has native-DQ and exact AVX-512F synthesized realizations;
- signed i64 -> f64 conversion has native-DQ and exact AVX-512F decomposition/reconstruction realizations;
- property-proven nonnegative f64 -> u64 truncation used by exact modulo lowering has an AVX-512F synthesized realization;
- predicate -> i64 all-ones/zero materialization has native-DQ and predicated-broadcast AVX-512F realizations;
- fixed the final foundation predicate bug: the synthesized `VPBROADCASTQ zmmDST{k1}{z},rax` EVEX P0 now encodes both destination high-register bits correctly;
- `--isa-limit native|avx512f|avx512dq|avx2` provides an audit ceiling without changing semantic routing;
- forced AVX-512F output is release-gated against DQ-only `VPMULLQ`, `VCVTQQ2PD`, `VCVTTPD2QQ`, and `VPMOVM2Q`;
- native-DQ and AVX-512F-foundation executables are differential-tested on heat/select boundaries, sparse nonlinear indexed operators, FEM aggregation, odd tails, and 1/4-executor execution;
- AVX2 is represented in the capability model but is not misrepresented as a complete 256-bit tensor backend. Without the required 512-bit base capabilities, compilation rejects explicitly; no scalar emulation is introduced.

The release does not add workload-name, solver-name, or benchmark-name dispatch. A WHEX operation requests semantic capabilities; the physical x86 realizer chooses a native instruction or an exact parallel recipe.

---

# Wheelchair 1.0.13 Release Notes

## Theme: true-parallel WHEX realization

1.0.13 keeps the 1.0.12 structural-algebra semantics and replaces the remaining per-vector evaluator shell with a fused generated episode.

- generated AVX-512 code owns the complete chunk loop; runtime performs one generated-evaluator call per chunk instead of one call per eight points;
- root axis ZMM6 advances across blocks by an exact `+8` recurrence;
- up to two profitable affine coefficients may reserve persistent carriers from the shared ZMM16..25 ownership pool; a coefficient `c` is initialized once as `c*root` and advances by `c*8`;
- carrier allocation is generic and coefficient-driven. Exhaustion falls back only to ordinary AVX-512 multiplication, never to scalar execution;
- immutable ZMM26..31 constants remain once-per-worker resident; dynamic exact-modulo invariants are computed once per fused chunk episode;
- the final partial block remains AVX-512 mask-zeroed;
- the old runtime per-vector unroll metadata is normalized to one truthful fused body;
- induction ownership is included in structural proof transactions, so failed speculative lowering cannot leave a stale persistent register;
- tensor runtime contains zero `call eval_slot` sites and exactly one `call eval_vec4` site in `eval_chunk`; the generated evaluator itself contains no call instruction;
- no benchmark/workload/solver name participates in the new induction/fusion decisions.

### Regression evidence

The 1.0.13 true-parallel gate checks:

- 1/4-executor equality at 1024, 1025, 2049 and 16,777,216 points;
- the historical heat checksum `0x4167fc0000000000`;
- one evaluator entry per chunk and no scalar evaluator call;
- a generated backward edge inside the AVX-512 episode;
- generic `17*i+d` induction materialized as initialization from ZMM6 plus a cross-block `+136` update;
- no generated inner `call`;
- no workload-name dispatch.

### Performance note

On the current Xeon Platinum 8272CL execution image, a 31+31 interleaved whole-process A/B of the existing periodic heat workload at N=16,777,216 measured a median 37.280716 ms for 1.0.12 and 31.723609 ms for 1.0.13, a 1.175173x median speedup. This is an internal same-machine version comparison, not a renewed Rust victory claim.

---

# Wheelchair 1.0.12 Release Notes

## Theme: generalized structural algebra without hidden serialization

1.0.12 keeps the frozen 1.0.9 native runtime architecture and the 1.0.11 recursive operator-span maturation, then generalizes the WHEX proof/lowering boundary.

- canonical operator directions now retain affine and modulo-domain identity rather than relying on workload-specific periodic handling;
- exact compatible periodic composition uses modular integer algebra, allowing repeated relations to collapse through ordinary key equality;
- structural operator-span emission is transactional. Failed native realization restores code pointer, register ownership, cache/constant state, fixups, axis context, and scheduling counters before another structural path is attempted;
- tensor native compilation no longer builds an unused scalar evaluator before AVX-512 lowering;
- tensor-native failure no longer retries the sovereign general lane; the general/topology lane is selected semantically before lowering;
- runtime boundary and tail work remain vectorized, with a masked final AVX-512 block and zero `call eval_slot` sites;
- dynamic modulo lowering proves the integer form `c*axis + q*n + d` and realizes it in vector code;
- fixed a generic type bug in that proof: u64 affine multiplication now matches u64 literals instead of calling the f64 coefficient helper;
- dynamic modulo regression covers the existing sparse nonlinear topology at 58 extents plus 48 independent `q*n`/signed-offset metamorphic cases;
- 1-executor and 4-executor results remain within the declared numerical contracts;
- compiler/runtime sources are release-gated against workload-name dispatch.

### Claim boundary

1.0.12 is a structural-algebra maturation release, not a claim that every tensor rank or every linear-algebra decomposition is already exposed in WHEX. The current human topology surface remains the documented one-axis slice. Future Rank-N, factorization, subspace, and relation capabilities should extend the same structural machinery rather than introduce named solver fast paths.

---

# Wheelchair 1.0.11 Release Notes

## Theme: mature recursive operator spans without changing the native architecture

1.0.11 inherits the complete 1.0.9 runtime and topology architecture. Its changes are confined to structural WHEX/native lowering and regression coverage.

- added recursive homogeneous-linear operator-span recovery and symbolic affine coordinate composition;
- preserved conservative periodic/modulo semantics instead of erasing unproven modulo structure;
- fixed recursive collector return-state preservation across context restoration;
- fixed a constant-pressure correctness bug where a proven composed affine coordinate could fall back to root-unaware ordinary lowering after resident immutable ZMM constants were exhausted;
- added RIP-relative qword-broadcast `vpaddq` and `vpmullq` constant operands so affine structure remains vectorized under constant pressure;
- aligned compile-time constant-pool metadata with the existing 512-entry fixup topology;
- added Q1→Q4 recursive-power and affine-constant-pressure regression gates, including odd tail extent 1025 and 1/4-executor equivalence.

The 1.0.9 runtime-erasure and serial-spine-erasure release notes follow unchanged for inherited architecture.

---

# Wheelchair 1.0.9 Release Notes

## Theme: erase the runtime shell and the central fork/join spine

1.0.9 is a native-topology maturation release. It preserves 1.0.8 language semantics and GTR while changing the physical shape of generated topology executables.

### Runtime erasure

- removed fixed scalar/vector/vector-init evaluator arenas;
- generated arithmetic now occupies an exact-size RX segment;
- patched evaluator entry stubs use direct `rel32` AOT jumps;
- final topology ELFs are sectionless and contain only loadable program state;
- removed global chunk partials, global worker summaries, fixed child-stack BSS, and shared affinity-mask BSS;
- frozen template BSS reduced to 20 bytes;
- child stacks are allocated only for reachable causal subtrees and released immediately after the dependency closes.

### Serial-spine erasure

- removed root `spawn-all` loop;
- removed root `wait-all` loop;
- removed root/global reduction sweep;
- added distributed causal binary executor tree;
- every internal node joins only its direct dependency child;
- fan-in-two reduction occurs at the same causal node;
- no global task/work queue is introduced.

### Reduction-state maturation

- replaced `O(chunks)` global partial storage with a stack-local binary-carry frontier;
- tightened the proven frontier to 12 f64 levels = 96 bytes for `MAX_CHUNKS=2048`;
- canonical four-executor FEM now exposes only three cross-executor causal return edges;
- canonical total reduction adds remain 511 and critical reduction span remains 9.

### Compiler-chain proof

The authoritative topology backend remains handwritten x86-64 assembly and direct static ELF emission. Release gates assert no C/LLVM/Rust/JIT/foreign high-level backend and no dynamic runtime/interpreter in generated topology images. The optional Python WHEX human-surface tool is byte-erased before the native authority boundary and is not used as performance authority.

### Correctness/test repairs

- corrected the shipped WHEX heat `N=4` test oracle from `4.4453125` to the mathematically correct `1.111328125`;
- scheduler machine-code tests now disassemble the exact generated RX segment instead of depending on ELF section tables;
- retained the 1.0.8 general correctness/GTR suite, including deterministic f64 differential coverage;
- added a dedicated 1.0.9 runtime/serial-spine release gate.
- made the complete release harness resource-isolate the heavy native proof gates, avoiding CI quota contention without changing generated-program execution semantics.

### Claim boundary

1.0.9 proves the shipped gates and the tested topology slice. It does not claim architecture completion, globally minimal work/span, or universal performance superiority over expert C/Rust implementations.

## 1.2.1 Technical Peak Preservation Contract

The general true-parallel charter now makes peak preservation a release invariant. Generalization may not erase a mature machine-code advantage and fall back toward a slower common denominator. A lost narrow optimization must be promoted into a generic Axis/Operator/Region/Effect/Capability proof rule, never restored through workload-name dispatch.

The Newton/Jv restoration is the reference case: Interior Periodic Composition Erasure recovered a periodic affine relation generically, retained exact boundary semantics, reduced redundant modulo work, and restored the established performance peak without adding a Newton/Jacobian special case.

## Lane identity hardening

Compiler-lane selection is now protected from accidental fuzzy-keyword promotion. Exact structural markers select the structural lane immediately; otherwise two independent repairable structural markers are required. Fuzzy repair therefore cannot turn a single damaged legacy identifier fragment into a different execution model.
