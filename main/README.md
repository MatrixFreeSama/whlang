# Wheelchair 1.3.126

![Build](https://img.shields.io/badge/build-36%2F36%20PASS-brightgreen) ![Release](https://img.shields.io/badge/release-1.3.126-blue)

Wheelchair is an HPC- and simulation-first general-purpose AOT language built around Rank-N semantics, matrix-free execution, ValueFacts, StateFacts, AddressFacts, RegionFacts, CoordinateFacts, GroupFact, Physical Reality, Traffic Reality, Silicon Domain Graphs, and Physical DAG execution.

The objective is not occupancy. It is convergence of real physical work toward the mathematical-physical lower bound:

```text
physical work / mathematical-physical lower bound -> 1
```

Idle silicon is valid whenever another materialization costs more than the remaining necessary work.



## 1.3.126: SupportFact becomes a canonical RegionSet

A zero-false reduction is no longer limited to one contiguous support. ADD/SUB support facts compose as a source-derived union; runtime discovers the exact IEEE intervals, sorts/merges them into one disjoint RegionSet, and the existing strict reduction tree erases every wholly dead subtree. There is no two-region mode, fixed Region capacity, Level-Set/narrow-band matcher, active-set backend, or new DSL.

On the retained real Level-Set/VOF two-interface benchmark (`n=8,000,000`, about 0.1% active support), pinned one-CPU median falls from **7.236 ms in 1.3.125 to 0.939 ms in 1.3.126 (7.70x)** with the same strict checksum. Natural serial C/Fortran measure 10.717/11.062 ms; hand-bounded two-band controls measure 1.381/1.716 ms. The 4M/8M/16M probe loses the former full-domain linear scaling and stays near support/startup cost.

## 1.3.125: proven zero support stops owning execution

A zero-false PredicateFact can now contract the execution domain itself instead of only masking value work inside each packet. The compiler proves constant/monotone/single-basin support topology, emits the original IEEE relation as one cold boundary witness, and Physical Reality retains ownership only for canonical leaves that can intersect the true support. Strict reductions preserve the immutable q=1 tree by replacing only proved-all-zero subtrees with exact `+0`; empty support closes directly to the reduction identity. No contact/Hertz matcher, active-set DSL, density threshold, second reduction backend, JIT, scheduler, or source-visible sparsity mechanism is added.

On the retained real penalty-contact benchmark (`n=8,000,000`, about 4473 active points), pinned single-CPU whole-process median falls from **6.638 ms in 1.3.124 to 0.886 ms in 1.3.125 (7.49x)** with the same strict checksum. Pure serial `-O3 -march=native` C/Fortran measure 8.842/7.819 ms; hand-bounded support implementations measure 1.344/1.753 ms. With four CPUs available, Wheelchair measures 0.858 ms versus 2.340 ms in 1.3.124 and naturally reprices the shrunken work rather than forcing full-domain multiplicity.


## 1.3.124: periodic facts keep their mathematical size

Deep dynamic affine coordinates no longer become physically huge merely because an unreduced u64 representative crosses the old reciprocal proof estimate. The quotient bound is derived from the affine relation itself, unsigned u64 coordinates convert exactly without scalar lanes, and genuinely wider periodic facts reuse the existing persistent AffineFact authority so exact ring expansion initializes retained value/step state instead of living in the hot loop. No depth matcher, benchmark route, compatibility evaluator, second periodic IR, JIT, scheduler, or source-visible parallel/periodic DSL is introduced.

On the retained pinned 16M-element depth-23 diagnostic, the 1.3.123 cliff contracts from **720.100 ms to 27.201 ms (26.47x)** and from a 21,833-byte executable to 8,985 bytes, while natural C/Fortran measure 580.733/588.603 ms and hand-composed C measures 25.001 ms. At depth 40, where the correlated reciprocal proof is genuinely insufficient, the exact retained realization improves **1070.342 -> 482.341 ms (2.22x)** and still beats natural C/Fortran, but remains far from the manual C ceiling; that residual gap is kept visible as physical-aging work.

## 1.3.123: periodic facts outlive one physical precision trick

Dynamic periodic affine coordinates no longer become source-language errors when the FP64 reciprocal realization leaves its strict proof domain. `PeriodicAffineFact(c,d,n)` remains one semantic fact. A compile-time physical proof keeps the mature reciprocal path where safe, expands it with exact integer ±2 quotient correction where the binary64 error bound proves that sufficient, and otherwise realizes the same fact with exact integer modular arithmetic. There is no depth matcher, benchmark route, source-visible mode, compatibility evaluator, second Tensor IR, JIT, or scheduling DSL.

The former `(3*i+b) mod n` depth wall disappears: weighted permutation-sensitive oracle tests pass through depth 40 at multiple runtime extents, while depth 12 keeps its prior executable byte-for-byte. On the retained pinned 16M-element benchmark, depths 13/21/22 run at 23.745/23.682/24.377 ms versus natural C at 344.997/496.447/506.645 ms and natural Fortran at 349.908/487.547/525.043 ms. The matching hand-composed C ceilings are 24.788/23.454/24.220 ms, showing that the automatic structure is essentially back at the manually collapsed physical workload. Depth 23 remains a documented physical-aging frontier: exact semantics compile, but the general integer-ring fallback is still slower than the manual ceiling.

## 1.3.122: parallel assembly authorities converge

Tensor no longer carries four mostly parallel frontend source bodies. ISA/profile-independent bodies live once in a common assembler-time authority, genuinely shared physical-profile bodies live once in a profile authority, and the four entry surfaces retain only the semantic/physical differences that actually exist. Field runtime follows the same rule for proof-neutral AVX2/AVX-512 bodies while proof-bearing frontier/reduction authorities remain explicit. The duplicate Field linker script is gone. There is no runtime ISA/profile dispatcher, generated source clone, compatibility frontend, workload matcher, scheduler, JIT, or DSL surface.

This is source convergence, not a performance trick. All eight production binaries remain byte-for-byte identical to the pristine 1.3.121 build, and the retained 12-pair structural-inflation program is still the same 8513-byte ELF with SHA-256 `ab7667c9bca6a2b39449b41bd4cbf3f81045e50d192d1d3350d62cca9176a569`. Eleven interleaved runs measure 5.400 -> 5.343 ms median; because the executables are identical, that ~1.1% difference is noise. Production `.S/.inc` source falls from 3,018,437 to 2,639,371 bytes (-12.56%); Tensor frontend authorities fall 29.51% and Field runtime authorities 20.56%. The release ZIP also stops shipping the generated `build/` tree while retaining historical `devtrash/` evidence and canonical `bin/` products.

## 1.3.121: CoordinateFacts compose before realization

Indexed periodic coordinates now compose symbolically before any SIMD carrier is allocated. Arbitrarily deep affine/remap chains therefore collapse into one canonical CoordinateFact; identity chains disappear completely, signed residue representatives normalize in the same Z/nZ materializer, and source nesting no longer leaks AVX-512 register cardinality into language expressibility. The former 24-indexed-map wall is gone without a larger limit, spill path, compatibility evaluator, workload matcher, or scheduling DSL.

The derived backend also retires its private 6-slot dense/mixed/scaled partitions and 2-slot induction partition in favor of the existing physical persistent Fact register authority. Front-end SIMD-byte budgets, the Field 8 MiB / 2x / 4x NT-store selector, a dead mutable-slot constant, and a defensive CPUID subleaf cap are removed rather than retuned. On the retained constant-mathematics structural-inflation benchmark, 0 through 200 canceling remap pairs emit the same 8513-byte executable. At 12 pairs, same-host 1.3.120 -> 1.3.121 wall time is 394.124 -> 99.647 ms (3.96x). In a separate same-host current-vs-C/Fortran run, Wheelchair is 99.541 ms versus 199.103 / 200.410 ms, about 2.00x / 2.01x faster.

## 1.3.120: periodic ShapeFact closure

Dynamic high-axis affine remaps now close through the same ShapeFact-N physical product ring as existing mixed-radix coordinates. Expressions such as `(b*97 + i*13 + 17) % n` no longer fall out of the structural tensor path. The compiler uses the identity `(L mod n) * S = (L*S) mod (n*S)` and the existing CoordinateFact authority; there is no rank-specific route, fixed-radix matcher, scalar fallback, second coordinate backend, or scheduling DSL. A retained benchmark records both the repaired coverage and the remaining gap to a hand-written recurrence ceiling.

## 1.3.119: Predicate support becomes physical

1.3.119 keeps AVX-512 floating PredicateFacts in native mask authority and lets exact `+0.0` false support become a zero-work guarded packet Region. A fully empty packet no longer computes the true relation; a mixed packet computes it once and masks inactive lanes exactly. This is the same Rank-N PredicateFact/Region chain, with no active-set DSL, density threshold, workload matcher, second tensor IR, or scheduler. Cross-packet compaction is deliberately not claimed.

In the retained strict 100M-element diagnostic, direct PredicateFact work improves **96.663 → 74.200 ms** on one CPU (**1.303×**) and reaches **1.227× C throughput**. With the same predicate behind nonconforming CoordinateFact remaps, Wheelchair improves **156.509 → 127.177 ms** and records **3.149× C / 3.145× Fortran** on one CPU. Dense and all-active probes also improve, confirming that the gain is not a sparse-density special branch.

## 1.3.118: Rank-N predicates become ordinary ValueFacts

Field/Tensor values now consume the same predicate relation that General already uses: FP `eq/ne/lt/le/gt/ge` produce Rank-N PredicateFacts, and `select(P, f64, f64)` remains inside the existing structured Physical DAG on AVX-512, native256, derived, and derived-native256 paths. This closes the former seam where CoordinateFact and SIMD mask machinery existed but a value-dependent Field predicate still forced structured-source rejection. No contact primitive, active-set container, workload matcher, second Predicate IR, JIT, scheduler, or source-visible parallel DSL is added.

The retained strict 100M-element diagnostic deliberately separates the new relation from CoordinateFact. With direct coordinates Wheelchair is near ordinary C scale (**95.40 ms vs 90.08 ms** on one CPU), so predicate support is not advertised as a speed trick. With the same predicate behind two nonconforming runtime remaps, Wheelchair records **159.55 ms vs 407.39 ms C / 422.86 ms Fortran** on one CPU (**2.553x / 2.650x faster**) and **55.75 / 104.89 / 107.67 ms** on four CPUs (**1.881x / 1.931x**). About 3.1% of elements are active, but 1.3.118 does **not** yet compact that support set; inactive lanes are not claimed to disappear.

## 1.3.117: proved root frontiers become fixed executions

General AOT root independence now survives into physical execution ownership. Ready roots still pass the existing work-vs-outward-lifecycle cost gate; only roots that repay a new lifecycle may anchor an additional execution, and invocation affinity remains the external multiplicity bound. Once those execution anchors exist, the complete already-ready root frontier is fused into immutable chains before launch. A child owns its chain from birth through completion and then returns to the OS. There is no ready queue, worker pool, work stealing, idle-CPU query, recipient search, or post-completion task transfer.

The fixed integer resident-count wall is also gone: integer StateFacts ask actual old/next GPR geometry, with borrowed R11/R12 carriers removed from the same anonymous temp pool. FP comparisons consume resident ValueFact/ConstantFact XMM operands directly instead of copying them through temporary registers. No Mandelbrot/fractal/pixel matcher, thread API, source-visible parallel DSL, JIT, scheduler, kernel-offload path, compatibility execution graph, or second IR is introduced.

On the exact 16-root whole-domain Mandelbrot regression, 15 interleaved four-CPU runs move Wheelchair from **212.75 ms in 1.3.116 to 73.21 ms in 1.3.117**, a **2.906x** speedup and **65.59%** wall-time reduction; median effective CPU use rises from **1.02 to 3.44 cores**. One-CPU time changes only **212.42 -> 209.01 ms (1.016x)**, isolating the main gain to execution ownership. Fresh strict C/Fortran medians are **42.63 / 43.42 ms**, so parity is not claimed. Checksum remains `0x00000000032e223d`.

## 1.3.116: predicates become physical regions

Repeated PredicateFacts now control one Guarded Physical Region instead of decorating every next-StateFact with an independent select diamond. Exact shared guards are discovered from the existing episode ValueFact graph; all guarded arms still consume the same old state generation, and identity arms emit zero update/commit work. Predicate control consumers can use FLAGS or the resident BOOL carrier directly instead of routing through RAX, and canonical BOOL `and/or/xor` over resident facts map directly to the existing XMM bit relation. Integer literals that fit the architectural immediate relation are consumed as ISA operands rather than transient GPR ValueFacts.

No Mandelbrot/fractal/pixel recognizer, state-count workload route, JIT, runtime scheduler, source-visible parallel DSL, kernel-offload path, compatibility evaluator, or second control IR is added. The region is a compile-time projection of PredicateFact identity plus existing StateFact carriers. Visible trap semantics remain unchanged.

On the retained strict scalar Mandelbrot diagnostic, 15 pinned interleaved runs move the median from **359.70 ms in 1.3.115 to 213.67 ms in 1.3.116**, a further **1.683x** speedup and **40.60%** wall-time reduction with checksum `0x00000000032e223d` unchanged. Fresh strict C and Fortran medians are **143.14 ms** and **144.82 ms**, leaving Wheelchair at about **1.493x C / 1.475x Fortran** rather than claiming parity. The generated trailer contracts from **3193 to 2926 bytes**; static `movabs` sites fall **27 -> 18**, `test` **45 -> 31**, and `jmp` **35 -> 27**. Pure FP1/FP2 scalar recurrences remain essentially neutral, isolating the gain to control/state physicalization.

## 1.3.115: basic ValueFacts stay physical

Basic scalar operators no longer get a veto over an otherwise native Physical episode merely because their emitter realization was missing. FP `neg/abs/min/max`, representation-preserving scalar casts, integer bit relations and signed/unsigned `min/max`, wrap-total integer `neg/abs`, and BOOL `xor` now reuse the existing carrier/CSE/ConstantFact authorities. FP sign masks are ordinary ConstantFacts: when physical pressure retains one, sign transformation collapses to a single XMM bitwise operation; otherwise the same DAG uses a transient bit carrier rather than switching evaluator.

No workload matcher, local generic-island compatibility layer, JIT, runtime scheduler, source-visible parallel DSL, or second scalar backend is added. Visible trap semantics remain proof-gated rather than being weakened for native admission.

Pinned A/B diagnostics versus 1.3.114 improve **2.112x** for `abs(f64)`, **3.391x** for FP `min/max`, **2.535x** for INT `min/max`, and **2.537x** for the formerly generic `select + neg` probe. The latter is now **1.480x** the matching C time instead of **3.755x**. Strict scalar Mandelbrot is essentially neutral (**352.47 ms -> 351.58 ms**) with the same `0x00000000032e223d` checksum, so the release does not use an unrelated workload as evidence.

## 1.3.114: repeated predicates become episode ValueFacts

Repeated compare/boolean relations now share the same episode-scoped Physical ValueFact authority as repeated arithmetic. The compiler may retain exact PredicateFacts in the existing pressure-derived shared carrier pool, and retained parent/child arithmetic facts are no longer forced into an artificial antichain when both still have independent consumers. Shared facts are materialized from structural leaves toward parents so selected parents reuse selected children instead of rebuilding them. The native iterate condition now uses the same Physical predicate emitter rather than the generic expression stack.

No Mandelbrot/fractal/pixel recognizer, predicate-cache knob, control-flow DSL, JIT route, runtime scheduler, workload selector, or second scalar backend is introduced. This is General Physical-DAG convergence.

On the retained strict scalar Mandelbrot diagnostic, 15 interleaved runs move the Wheelchair median from **513.52 ms in 1.3.113 to 347.94 ms in 1.3.114**, a further **1.476x** speedup with identical `0x00000000032e223d` output. Generated trailer counts contract from `vucomisd/seta/setae = 8/8/8` to **1/1/1**, `sete` from **4 to 1**, `vaddsd` from **12 to 5**, and trailer bytes from **3661 to 3193**. C and Fortran remain around **140 ms**, so scalar-control parity is not claimed.

## 1.3.113: control facts stay inside Physical DAG

General scalar realization now treats comparisons, lazy boolean relations, and `select` as ordinary Physical-DAG values instead of ejecting the whole recurrence into the generic stack/state path. Integer `trap` overflow is realized in the same native transition with its strict failure edge; `wrap` remains the same relation rather than a second backend. CSE and effective-state liveness now traverse the complete expression graph, so arithmetic facts below control nodes remain visible to the existing residency authority.

No Mandelbrot/fractal/pixel recognizer, control-flow DSL, scheduler, JIT route, workload selector, or second scalar backend is introduced. The change is a General control/value convergence: predicates may control physical regions without ceasing to be ValueFacts.

On the retained strict scalar Mandelbrot diagnostic (768x768, 512-iteration bound, one fixed CPU, no SIMD), 11 interleaved old/new runs move the Wheelchair median from **2252.69 ms to 523.44 ms**, a **4.304x** speedup with identical `0x00000000032e223d` output. The generated trailer contracts from about **1458 to 983 disassembly lines**, `push+pop` from **386 to 82**, and scalar multiply sites from **20 to 8**. Fresh strict C and Fortran medians are **143.44 ms** and **143.34 ms**; 1.3.113 therefore repairs the major rollback but does not claim scalar-control parity yet.

## 1.3.112: tolerance becomes a proof bound, not a fast mode

For `P > 64`, the existing program-level `tolerance N` contract now reaches Rank-N mathematics as one conservative `ToleranceFact`. Basic `add/sub/mul/div` remain the same strict P-bit operations and still close through the single Strict/RNE authority. Tolerance changes only the stopping proof of convergent relations: `sqrt` uses its Newton update bound, `exp` and `log` use contracted series-tail bounds, and the shared `sin/cos` relation requires both alternating tails to fit a conservatively back-propagated budget before double-angle restoration. If a proof is unavailable, execution falls back to the existing strict convergence condition.

This is not `fast-math`: no precision is silently reduced, no primitive is reassociated, and no tolerant arithmetic backend or selector exists. The previously accepted parameterized type-local form `fpP ~(abs=...,rel=...)` is now rejected because General did not preserve that local error object; the release does not keep a syntax that silently means Strict. Program-level `tolerance N` is the single admitted high-precision tolerance authority in 1.3.112.

Against 1.3.111, whose high-precision tolerant programs were effectively strict, the retained fixed-CPU A/B at tolerance `1e-10` measures about **5.0x-5.6x** for 4096-bit `exp/log/sin/cos`, **12.6x-17.2x** at 8192 bits, and **31.1x-43.1x** at 16384 bits. `sqrt` improves more moderately, about **1.11x / 1.49x / 1.81x** at those precisions. A 240-case exact-rational validation grid has zero bound violations. A longer Strict recheck resolves the earlier short-run noise: representative 4096- and 16384-bit probes remain essentially at 1.3.111 speed while retaining bit-identical results.

## 1.3.111: high precision carries facts, not empty storage

The P>64 Rank-N path is physically older and smaller without adding another arithmetic family. Big/big division now keeps its base-2^32 recurrence in real u32 digits, reuses the quotient high-water fact at the existing StrictClose boundary, and no longer pays for zero-extended qword slots. The historical `512*N+4096` object envelope is gone: PrecisionFact plus the existing Fourier TypePhysicalFact geometry now determine the exact live add/mul/div span used by compiler temporaries, decimal ingress and advanced mathematics.

Direct big/big division improves by roughly 1.17x-1.34x over 1.3.110 in the measured 4096-262144-bit range. Experiments that were mathematically valid but physically regressive were removed rather than retained as alternate paths.

## 1.3.110: Field rank is a fact, not a file width

Field no longer has a semantic Rank-8 ceiling. `WHFLD217` carries one u64 RankFact followed by exactly `rank` extent and stride facts; Surface, canonical Field metadata, AddressFact deltas and runtime hot tables all derive their axis storage from that same invocation RankFact. The historical `FIELD_RUNTIME_RANK_CAP`, fixed 32-byte access delta, fixed `extent[8]/stride[8]`, and `r1..r8` runtime address/load/store families are gone.

Native512 and Native256 now consume one runtime-rank address relation. AVX-512 spare coordinate registers remain physical resources rather than a language width authority. Current release probes execute rank 9, 17 and 33 through the same path, while old `WHFLD216` files are rejected rather than translated. Padded/strided output remains truthful through the unified scatter relation.

A 1,048,576-element strict reduction shows no low-rank tax versus 1.3.109: sampled medians are about **1.039x** at rank 3 on Native512, **1.006x** at rank 3 on Native256, **0.999x** at rank 8 on Native512, and **1.018x** at rank 8 on Native256. These are small measurements, so the release claims structural convergence rather than a broad speedup. The separate signed-dword coordinate/span frontier remains explicit and is not disguised as a rank limit.

No old-format compatibility reader, rank selector, workload route, DSL parallel surface, JIT, scheduler, worker pool, or second Field backend is added.


## 1.3.109: local facts are not rediscovered globally

Rank-N physical aging continues without a second high-precision system. General division now carries geometry already implied by normalized `fpP` and quotient production instead of rescanning U/V/Q. Strict RNE carry-out closes directly from the carry fact rather than shifting the complete P-bit carrier again. Fourier twiddle construction starts from the exact unit value, and the shared `sin/cos` relation keeps disposable sign and exact powers of two local instead of cloning a complete ValueFact or performing an extra high-precision addition.

Seven obsolete carrier/geometry helper authorities are absent from the final General runtime. On the same `sin(fp8192)` generated probe, `.text` contracts from **16605 B to 16029 B (-3.47%)**. Wall-time probes are mostly neutral with low-single-digit movement in both directions, so this release makes no broad speedup claim; an experimentally shorter cross-span pointer-rotation realization was rejected after it increased cache/TLB work.

The current release remains one `fpP`, one Rank-N/PrecisionFact authority and one Strict/RNE closure. No named-width backend, local-float dialect, precision selector, algorithm-threshold tree, JIT, kernel offload, scheduler, worker pool, workload matcher or source-visible parallel mechanism is added.


## 1.3.108: advanced mathematics keeps local facts local

Rank-N advanced relations now stop inflating exact scalar series coefficients into full `fpP` ValueFacts. `exp`, `log`, and the shared `sin/cos` propagation authority consume one shared exact `rankn_fp_div_u64` relation; the quotient is closed through the same strict RNE authority used by the rest of Rank-N. Representation convergence likewise uses one bit-identical ValueFact-silence predicate instead of invoking full numerical ordering.

The compiler-side `fpP` constant/cast regression introduced by the earlier type-physicalization aging is repaired at its root: binding kind is stable local state across inference and Rank-N type materialization rather than a caller-saved register. Shared arithmetic zero identities also close centrally, so `sqrt(0)`, `exp(0)`, `log(1)`, `sin(0)`, and `cos(0)` no longer need or receive per-function compatibility branches.

Same-host whole-process A/B against unmodified 1.3.107 shows the intended high-precision scaling: at 4096 bits, `exp/log/sin/cos` improve about **3.39x / 3.40x / 5.27x / 5.66x**; at 8192 bits, about **4.08x / 4.81x / 9.74x / 11.32x**. `sqrt` remains essentially a control because its dominant relation is true big/big division rather than a scalar series quotient. Representative MPFR RNDN probes at 1024/4096/8192 bits are bit-identical to 1.3.107, so the speedup does not come from relaxing the existing numerical result.

No transcendental width selector, named-precision backend, `localfp` dialect, JIT, kernel offload, scheduler, worker pool, workload matcher, or second math backend is added.


## 1.3.107: Local-Strict becomes physical aging, not a new dialect

Rank-N add/sub now projects each canonical `fpP` operand directly into one operation-local guard/sticky carrier. The old `copy -> <<3 -> exponent shift -> sticky` sequence is gone from the production add/sub core. That carrier never escapes the semantic operation: the result still closes through the single strict normalization/RNE authority, so local representation does not defer rounding across later operations.

The old Local-Strict research prototypes are absorbed only at the level that survives architecture review. Fixed local cell widths, sparse/local alternate representations, and separate numerical modes are not imported. `fpP` remains the only source surface and `PrecisionFact(P)` remains the only semantic precision authority.

Pinned three-run medians versus unmodified 1.3.106 show add speedups of about **1.145x at 4096 bits**, **1.170x at 16384 bits**, **1.237x at 65536 bits**, **1.174x at 524288 bits**, and **1.140x at 1048576 bits**. Small widths improve only a few percent because fixed call overhead dominates. Multiplication and division receive no new algorithm family in this release and remain controls near their previous performance. Wheelchair still does not beat GMP overall in high-precision addition. Exact GMP oracles pass add/sub through 65536 bits and multiplication/RNE through 1048576 bits.

No local-float DSL, precision selector, schoolbook/Karatsuba/Toom threshold tree, JIT, kernel-offload surface, scheduler, worker pool, workload matcher, or source-visible parallel mechanism is added.


## 1.3.106: Rank-N physical work stops repeating itself

High precision keeps one arithmetic authority while redundant physical work is removed around it. Every `fpP` type now owns one AOT `TypePhysicalFact` containing precision and Fourier geometry; numeric ValueFacts no longer carry geometry, and the runtime Fourier planner is gone. Exponent alignment is one word+bit relocation, same-P copies are direct carrier clones, normalized zero tests are O(1), destination initialization occurs only at final RNE commit, and division drops redundant scratch clears.

Decimal ingress now accumulates source digits with the exact integer relation `D = 10D + digit` and normalizes only after the decimal sequence is complete. The old path invoked Rank-N Fourier multiplication for every decimal digit. In an fp4096 diagnostic with two roughly 900-digit inputs, whole-process median wall time falls from 102.55 ms in 1.3.105 to 0.407 ms in 1.3.106, about 252x. Direct arithmetic sees smaller but structural gains: add is about 1.24x to 1.46x faster across the sampled range, and small/mid-width multiplication reaches roughly 2x to 3x versus 1.3.105.

GMP is not globally defeated. Against GMP 6.3.0 `mpf`, the sampled 524288-bit multiplication point is about 1.15x faster, while neighboring 262144-bit and 1048576-bit points remain slower; add and division remain clear frontiers. An independent GMP integer oracle passes exact product/RNE checks from 65 through 1048576 bits. No algorithm threshold tree, named-width backend, JIT, workload route, scheduler, worker pool, or source-visible parallel mechanism is added.


## 1.3.105: Rank-N precision becomes a fact

Parameterized floating precision is no longer packed into the low 30 bits of a semantic type ID. `fpP` now interns one compact type identity while the actual `P` lives in an exact-sized u64 PrecisionFact trailer derived from the represented program. The generated runtime maps that same trailer and copies precision once into the hot Rank-N object header. Limb count is derived from `P`; the duplicate stored limb-count field is gone.

The historical `0x3fffffff` precision ceiling is therefore absent from compiler admission. `fp1073741824`, the first precision beyond the former wall, compiles through the ordinary path without a named-width backend or replacement threshold. Canonical Rank-N output exposes precision itself rather than the compiler-internal interned type identity.

This release does not claim that every arithmetic kernel can physically execute every u64 precision. Local digit/index widths that belong to existing arithmetic realizations remain explicit implementation frontiers and are not promoted into semantic type limits. No JIT, kernel-offload surface, runtime width selector, scheduler, worker pool, or source-visible parallel mechanism is added.


## 1.3.104: capacity follows facts, not magic numbers

Arbitrary capacity tables now age into authorities that already exist. General physical CSE/constant candidates and Tensor profiling/cache facts follow instance-sized arenas instead of 32/16/64-slot tables. Invocation affinity storage grows to the kernel-reported cpuset width instead of assuming 128 bytes, while static placement remains locality-only. The native driver reuses process-start argv and mmap-sizes path storage rather than maintaining fixed copies.

CPUID topology/cache scans now stop on architectural terminators. Structured matrix/vector dimensions leave the old 255-wide tag window, and the AOT-static `zeta`, `polylog`, and `tetration` relations no longer carry 32/16/8 semantic ceilings. None of these changes introduces a workload route, scheduler, worker pool, JIT, source-visible parallel directive, or second backend.

`WHFLD216` rank/geometry remains an explicit format/runtime representation frontier in this release. It is not papered over by increasing `8` to another constant.


## 1.3.103: dead authority becomes the next value

General scalar FP realization now consumes its existing effective last-use frontier when placing a next StateFact. If the old authority is already dead before that update, the next value is born in the dead carrier instead of creating a separate output carrier and copying it back at the timestep boundary. Scalar FP carrier copies also converge onto the existing VEX/EVEX scalar emitter; the duplicate low-register copy encoder is gone.

No dynamics recognizer, timestep heuristic, workload route, scheduler, worker pool, runtime CPU query, source-visible parallel directive, JIT path or second FP backend is introduced. A two-region explicit-dynamics diagnostic with a 10:1 timestep ratio removes four pure carrier transports per timestep in the four-state recurrence. Longer pinned wall-time A/B is neutral within measurement noise, so 1.3.103 makes no speedup claim for that case; the structural reduction is retained because it removes redundant physical work without adding a branch family.

## 1.3.102: execution admission becomes an invocation fact

Execution expansion no longer treats compiler-host CPU width as permanent image authority. At launch, Wheelchair reads the invocation's admitted affinity domain once; AOT static placement may only intersect that domain, never widen it. Tensor and Field expose arbitrary-cardinality ownership without the old power-of-two launch frontier, while General exposes completion-local ready siblings without adding a global ready queue, worker pool or work stealing.

Strict Tensor arithmetic is now independent of execution cardinality: ownership may change across 1/2/3/4/5 admitted CPUs, but the canonical pairwise reduction tree does not. Tolerance retains its explicit permission to condense arithmetic across ownership regions.

On the Cross-Axis diagnostic, correcting a 5-way compiled admission running inside a 4-CPU invocation raised observed slot occupancy from about **84% to 94%** and cut an intermediate candidate from about **823.7 ms to 751.0 ms** before the final Strict canonical-tree repair. Final Tolerance A/B against 1.3.101 measured about **1.054x** in a five-round paired run. On the low-arithmetic high-entropy permutation probe, a fresh three-round Strict check measured about **71.1 ms** for Wheelchair 1.3.102 versus **181.8 ms C** and **216.9 ms Fortran**, with bit-identical checksums in that run.

No idle-CPU query, workload matcher, source kernel, JIT path, runtime scheduler, worker pool, second Tensor IR, or DSL execution surface is added.

## 1.3.101: fact identity and tolerance realization age into one path

Scaled `CoordinateFact` allocation no longer lets the physical ZMM allocator overwrite the logical fact-table slot. The repair restores the existing ownership pool instead of adding another carrier family. Separately, Tolerance mode now consumes its already-declared permission for division by a finite normal compile-time literal: one reciprocal is formed at AOT time and the existing multiply/FMA path is emitted. Strict never enters this relation and preserves its original rounding boundaries.

On the same 100%-connected `8192 x 127 x 127` Dense Permuted All-Pairs probe, 31 paired four-core Strict rounds show a conservative paired-ratio median of **1.005x** (medians 249.973 -> 243.187 ms). Twenty-five paired Tolerance rounds improve 231.083 -> 221.466 ms with a paired-ratio median of **1.084x**. Single-core medians improve 749.714 -> 740.505 ms in Strict and 757.966 -> 681.198 ms in Tolerance. The Tolerance image's six `vdivpd` instructions fall to zero.

No workload matcher, `fast-math` bundle, source kernel, JIT path, runtime radix selector, worker model, or second Tensor IR is added.

## 1.3.100: mixed-radix CoordinateFacts become packet-persistent

The non-power-of-two coordinate path now keeps a single static mixed-radix carry recurrence across vector packets. Finite digits advance by packet width and exact wrap; outer digits consume the carry fact, and a live quotient reuses the already-owned residue wrap instead of rebuilding division from the physical root. This removes repeated integer reciprocal work without adding a workload matcher, runtime radix selector, alternate tensor IR, or parallel-language mechanism.

On the same 100%-connected `8192 x 127 x 127` Dense Permuted All-Pairs probe, a 21-round four-core Strict A/B improves the median from **267.034 ms** in 1.3.99 to **243.331 ms** in the 1.3.100 candidate (**1.097x**). Fast A/B improves **295.857 ms -> 265.949 ms** (**1.112x**). Generated hot code falls from **5497 B to 5249 B**; static `vpmuludq` count falls **84 -> 75** and ZMM moves **172 -> 153**. Sampled Strict outputs remain bit-identical.

## 1.3.99: mixed-radix CoordinateFacts stop rebuilding coordinates

Tensor/Topology lowering now carries non-power-of-two static coordinates as the same kind of persistent physical fact already used by dense Rank-N execution. Constant `div/mod` in a compile-time-proven `<2^32` domain is realized with exact integer reciprocal-high arithmetic and one correction; the former int-to-float reciprocal round trip disappears from that domain. Literal-scaled coordinates share the existing scaled CoordinateFact ownership table instead of receiving a workload-specific optimizer.

On the dense 100%-connected `8192 x 127 x 127` permuted all-pairs probe, 9 interleaved four-core rounds improve Strict from **641.747 ms** in 1.3.98 to **259.110 ms** in 1.3.99 (**2.477x**, **59.6%** lower wall time), and Fast from **660.481 ms** to **257.937 ms** (**2.561x**, **60.9%** lower wall time). Same-run controls measure 222.339/208.940 ms for C Strict/Fast and 230.461/215.541 ms for Fortran Strict/Fast. The repair changes coordinate materialization, not source semantics; sampled Strict checksums remain bit-identical to 1.3.98.

No benchmark matcher, source kernel, worker model, runtime radix selector, second Tensor IR, or DSL execution surface is added.

## 1.3.98: constant modulo joins one integer Physical Reality

General no longer abandons its register-native integer DAG when an exact `u64` expression ends in `% const`. Every nonzero compile-time divisor now uses one exact reciprocal relation. Powers of two have no mask compatibility branch, special admission rule, divisor table, runtime selector, workload route, or second backend.

In 21 interleaved 20:1 wait-slow rounds on the same host, 1.3.97 improves from 187.395 ms to **119.934 ms** in 1.3.98, a **1.5625x** throughput gain and **36.0%** lower wall time. The manually asynchronous controls measure 137.212 ms for C and 139.161 ms for Fortran. Existing FP General hot code for `mass3`, `chem6`, and `rigid7` remains byte-identical to 1.3.97.

## 1.3.97: StateFact generations can close onto one carrier authority

General now proves whether a complete resident FP state generation can keep one physical carrier identity across the timestep boundary after whole-episode CSE. Every next-state value must be safe to be born in its own old-state carrier after the final effective consumer, with Strict operation order unchanged. When the complete proof succeeds, the next-to-old transport layer disappears. When it fails, the existing disjoint generation realization is retained unchanged.

The choice is deliberately whole-generation, not a partial hybrid. There is no workload matcher, AMD/Intel route, update reordering backend, runtime allocator, source-visible parallel kernel, worker pool, or second General IR.

In 31 alternating 20M-step Strict rounds, `chem6` improves from 140.167 ms to **125.606 ms** (**1.1165x**) and all six scalar generation transports disappear. `mass3` and `rigid7` fail the complete fixed-point proof and keep 1.3.96 hot code byte-identical.

## 1.3.96: General scalar Physical Reality uses the real register file

General scalar FP now derives its carrier geometry from the compiler-wide ISA capability authority. A target exposing `ISA_CAP_WIDE_REGFILE` makes XMM16..31 ordinary carriers in the same Physical Reality; a narrower target retains the same 16-carrier realization. There is no AMD/Intel backend split, workload route, runtime allocator, source-visible parallel kernel, or second General IR.

The old source-order eight-constant/eight-CSE residency cliffs and the arbitrary two-temporary reserve are removed. Persistent CSE, immutable constants, state authorities and anonymous lifetimes now compete against the same physical carrier budget. Strict operation order and rounding points remain unchanged.

Same-host 20M-step Strict medians on the visible EPYC 9V74 execution set:

| workload | 1.3.95 | 1.3.96 | speedup | C Strict |
|---|---:|---:|---:|---:|
| mass3 | 149.417 ms | **118.921 ms** | **1.256x** | 110.943 ms |
| chem6 | 138.581 ms | **136.311 ms** | **1.017x** | 115.108 ms |
| rigid7 | 240.182 ms | **189.122 ms** | **1.270x** | 179.166 ms |

Raw alternating-run evidence is retained in `devtrash/benchmarks/general_scalar_physical_reality_1396/`. `chem6` deliberately remains a residual compiler probe rather than receiving a workload-specific scheduler.

## 1.3.94: spatial multiplicity and temporal quota are separate facts

A cgroup CPU quota is a time budget, not a proof that an affinity-visible execution context does not exist. 1.3.94 removes the old conversion of `cpu.max` into an integer worker ceiling:

```text
affinity set
    -> x86 execution multiplicity

cpu.max quota / period
    -> temporal budget

cache / NUMA identity
    -> placement and transport
```

All three remain Physical Reality facts. They no longer impersonate one another.

The old power-of-two expansion rule remains deleted. Five admitted contexts mean at most five execution leaves, never eight. There is still no worker pool, ready queue, work stealing, idle-CPU query, runtime silicon scheduler, source-visible parallel kernel, or benchmark-specific route.

## Same-host release A/B

| workload | 1.3.93 | 1.3.94 | speedup |
|---|---:|---:|---:|
| FSI 100M | 111.050 ms | **95.511 ms** | **1.163x** |
| lightweight Tensor 100M | 10.693 ms | **9.049 ms** | **1.182x** |
| dense Rank-3 | 27.886 ms | **23.352 ms** | **1.194x** |
| miniAMR 27-point | 24.160 ms | **19.784 ms** | **1.221x** |
| miniFE heat21 | 20.365 ms | **16.668 ms** | **1.222x** |
| CloverLeaf x-acceleration | 26.550 ms | **20.068 ms** | **1.323x** |

General `mass3 / chem6 / rigid7` remained continuity-level. Raw A/B data is retained in `devtrash/benchmarks/spatial_temporal_quota_1394/`.

## Silicon contract

The current contract is `wheelchair.silicon-reality/10`. It publishes `cpu_quota_usec` and `cpu_period_usec` directly. `execution_admission_capacity` follows the admitted affinity set. Cache-domain identity remains placement authority only.

x86 and reconfigurable fabric remain simultaneous Physical Reality domains, not mutually exclusive language targets. There is no `@fpga`, HLS kernel authority, fixed PE grid, fixed tile size, runtime device selector, or second fabric semantic IR. A real FPGA board bridge, RTL/place-and-route integration, and bitstream emitter are still absent, so no FPGA hardware speedup is claimed.

## Production toolchain

Production compiler/runtime authority remains handwritten x86-64 assembly and direct static ELF emission. The production build does not use C/C++, Rust, LLVM, MLIR, Python, a JIT, bytecode VM, HLS compiler, or FPGA kernel compiler.

```sh
./build.sh

bin/whexc INPUT.whex -o OUTPUT
bin/wheelchairc INPUT.wh -o OUTPUT
bin/topologyc INPUT.whex -o OUTPUT
bin/fieldc INPUT.json -o OUTPUT
```

## Release authority

The current release gate contains **29 tests**. Production authority remains under `compiler/`, `runtime/`, `surface/`, `tools/`, `build.sh`, and generated `bin/` executables. `devtrash/` contains regression, benchmark, historical, and archaeological material only.

See `ARCHITECTURE_AGING_1_3_105.md`, `PERFORMANCE_1_3_105.md`, `TESTING_1_3_105.md`, `PURE_ASSEMBLY_RELEASE_PROOF_1_3_105.md`, `RELEASE_SURFACE_CONVERGENCE_1_3_105.md`, and `WHEELCHAIR_CHARTER_1_3_105.md`.
