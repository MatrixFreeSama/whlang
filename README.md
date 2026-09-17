<p align="center">
  <img src="assets/icon/wheelchair-logo.png" alt="Wheelchair logo" width="240">
</p>

# Wheelchair

**An HPC- and simulation-first general-purpose programming language built around Rank-N structure, AOT compilation, ValueFacts, Physical Reality, Physical DAG execution, and direct native x86-64 code generation.**

Wheelchair targets the same broad numerical-computing territory as C and Fortran, but it does not start from a mandatory sequential instruction stream and then try to recover parallelism afterward. Its compiler treats mathematical structure, value identity, causal dependence, precision, locality, and physical realization as first-class compile-time information.

> Current release: **1.3.49**  
> Target: **Linux x86-64, static ELF64**  
> Source surfaces: **WH (`.wh`)** and **WHEX (`.whex`)**  
> [Download Wheelchair 1.3.49](./dist/Wheelchair-1.3.49.zip)

Archive SHA-256:

```text
d712d819319e3449eaaf8494ce6561466f67063074587e46553d990b844aa74d
```

---

## Features

- **English, Simplified Chinese, and Traditional Chinese source.** The three spellings are aliases of the same semantics and may be mixed in one file. Unicode identifiers, emoji, and mathematical symbols are also accepted by the human surface.
- **Conservative source auto-repair.** English keywords, selected built-ins, and declared names can recover from one insertion, deletion, or substitution. A recognized English token or declared name split by an accidental newline can also be rejoined. Repair is accepted only when the target is unique; ambiguous cases are rejected. Chinese, mixed-script, and emoji identifiers remain exact-only.
- **WH and WHEX.** WH is the compact human-facing surface; WHEX exposes structural Field/Rank-N relations more explicitly. Both lower into the same AOT architecture.
- **Native mathematical semantics.** Tensor/reduction, Field neighborhoods, matrices and contraction, differentiation, integration, root relations, complex values, special functions, and parameterized wide floating precision are part of the language surface.
- **Structural execution.** ValueFacts, causal dependence, lifetime, locality, and Physical DAG structure are available before final machine realization instead of being reconstructed from a mandatory sequential stream.
- **Native AOT toolchain.** The production compiler/runtime are handwritten x86-64 assembly and emit static ELF64 programs without a C/LLVM/JIT production backend.

### Multilingual source

The release archive contains equivalent English, Simplified Chinese, Traditional Chinese, and mixed-language programs under `surface/examples/`. For example:

```wh
程序 surface_shell_equivalence

输入 123🔥输入: u64 范围 1..1000
定义 123: u64 = 7
定义 9️⃣平方: u64 = 123🔥输入 * 123🔥输入 + `123`
张量 📦[0️⃣轴: 123🔥输入]: u64 = 9️⃣平方 + 0️⃣轴
归约 Σ总和[0️⃣轴: 123🔥输入]: u64 = 求和 📦[0️⃣轴]
发布 结果🚀 = Σ总和

测试 (1) => { 结果🚀 = 8 }
测试 (4) => { 结果🚀 = 98 }
```

In 1.3.49, the packaged English, Simplified Chinese, Traditional Chinese, and mixed `.wh` equivalents compile to byte-identical ELF64 output.

### Source auto-repair

The release also keeps a deliberately damaged source next to its clean counterpart:

```wh
progra repair_equivalence
inpput N: u64 range 1 .. 64
lett temperature: u64 = 7
let pressure: u64 = 3
tenspr values[i: N]: u64 = temperatur + i
reducf total[i: N]: u64 = su values[i]
let masked: u64 = bit_an(temperature, presure)
let hot: bool = tempera
ture >
= pressure
publisb total
pub
lish masked
publish hot
test (4) => { total = 34, maske = 3, hot = tru }
```

`surface/examples/auto_repair_typos.wh` and `surface/examples/auto_repair_clean.wh` compile to byte-identical ELF64 output in 1.3.49. The compiler redirects the repaired tokens internally; it does not rewrite the source file.

---

## Positioning: Fortran++

The project sometimes uses **Fortran++** as a market-positioning shorthand. It does not mean that Wheelchair is a Fortran dialect, source-compatible superset, or replacement frontend for an existing Fortran compiler.

The comparison is about the job the language is built to do:

- HPC, numerical computing, and simulation remain the primary territory;
- the human surface is intended to stay compact even as the mathematical and general-purpose language surface grows;
- Rank-N structure, Field relations, precision, causal dependence, and physical realization are compiler-visible semantics rather than conventions layered over ordinary sequential loops;
- native AOT code generation and low-level machine authority remain available instead of being hidden behind a managed runtime.

The `++` is therefore a direction rather than a universal benchmark claim: **Fortran-like numerical focus, with a broader language surface and a different execution architecture.** The benchmark sections below deliberately keep cases where GCC C or GFortran is still faster.

---

## Why the name Wheelchair?

The name comes from Chinese Soulslike gaming slang. In Chinese gaming communities, a **"wheelchair build" (轮椅)** is a build, weapon, or strategy with unusually high practical strength for the amount of mechanical skill it asks from the player. Instead of learning every dodge window, animation detail, or boss pattern, the player can skip part of that work and still get through the fight.

That is the joke behind the language name. If the mathematical structure is already known, the user should not have to manually spell out every loop, global matrix, scheduling decision, or low-level compiler detail just to express it.

The metaphor is deliberately stronger than the English gaming word **crutch**:

> A crutch still helps you walk.  
> A wheelchair lets you skip the walking.

`wheelchair` does not automatically carry this gaming meaning in ordinary English; the name specifically refers to the Chinese Soulslike usage.

---

## What Wheelchair is

Wheelchair is a native AOT language and compiler project designed primarily for HPC, numerical simulation, scientific computing, structured mathematics, and workloads where the program already contains more mathematical structure than a conventional sequential execution model can expose cleanly.

The central idea is simple:

```text
source syntax
    ↓
semantic structure
    ↓
ValueFacts / Rank-N relations
    ↓
Physical Reality
    ↓
Physical DAG
    ↓
ISA realization
    ↓
static native ELF
```

The compiler therefore tries to answer questions such as:

- Which values are actually distinct?
- Which dependencies are mathematically necessary?
- Which operations may exist at the same causal depth?
- Which values should stay resident instead of being transported or rematerialized?
- Which addresses, predicates, coefficients, matrix components, or neighborhood relations are already static facts?
- When is outward parallel execution physically worthwhile, and when is local continuation cheaper?
- What precision is required at the actual consumer edge?
- Which source constructs can disappear completely before runtime?

This is the core of Wheelchair's **structural execution** model.

---

## Design principles

Wheelchair's current production architecture follows a small set of hard rules.

1. **AOT first.** No JIT is required by the production compiler or runtime.
2. **Direct native authority.** Production code generation is implemented with handwritten x86-64 assembly and GNU binutils rather than a C, LLVM, MLIR, Python, or bytecode backend.
3. **Structure before source order.** Source order is not automatically execution order. Causal dependence is authoritative, while strict numerical contracts preserve ordering where ordering is semantically required.
4. **Rank-N first.** Tensor, Field, neighborhood, contraction, reduction, and multidimensional relations are native structural concepts rather than libraries layered over a scalar core.
5. **Matrix-free execution by default.** A global materialized matrix is not the mandatory execution representation. Structured matrix mathematics exists, but it does not force the whole program into a matrix-based runtime model.
6. **Precision is data.** Precision propagation happens before physicalization and may be carried as a semantic fact rather than being split into many unrelated implementations.
7. **Remove physical work before adding mechanisms.** Repeated computation, unnecessary transport, rematerialization, redundant predicates, avoidable communication, and needless execution-context creation are preferred optimization targets.
8. **No workload-name dispatch.** A benchmark name, solver name, matrix size, stencil name, or magic element-count threshold is not allowed to become a private production fast path.
9. **No work stealing or central ready queue.** Parallelism follows causal structure; completion releases resources without recipient-aware work redistribution.
10. **Old mechanisms must be assimilated, not accumulated.** A useful historical optimization must be re-expressed as a general capability of the current architecture before it can return to production.

The project deliberately accepts local performance imperfections when the alternative would be an algorithm zoo or a growing tree of benchmark-specific branches.

---

## WH and WHEX

Wheelchair currently exposes two source surfaces over the same general architecture.

### WH

**WH** is the human-oriented surface. It is intended to make structural programming concise enough that a user can describe the mathematical relation without manually spelling out the compiler's internal execution machinery.

A small example from the release archive:

```wh
program surface_shell_equivalence

input n: u64 range 1..1000
let base: u64 = 7
let square: u64 = n * n + base

tensor values[i: n]: u64 = square + i
reduce total[i: n]: u64 = sum values[i]

publish total

test (1) => { total = 8 }
test (4) => { total = 98 }
```

The real surface also supports Unicode identifiers, including mixed English, Simplified Chinese, Traditional Chinese, symbols, and emoji identifiers.

WH currently includes structural forms such as:

- `input`, `let`, `output`, `publish`, `test`;
- Rank-N `tensor` and `reduce`;
- `iterate`, persistent `state`, `while`, `update`, and `result`;
- `field`, `each`, neighborhood addressing, and periodic access;
- `select`, `min`, `max`, and compile-time branch erasure where facts are static;
- `record`, `dictionary`, lookup, nested values, and structural reductions;
- `cascade` causal relations;
- matrices, matrix access, contraction, structured mathematics, and root relations;
- strict/tolerant floating-point contracts and precision propagation.

### WHEX

**WHEX** exposes the structural semantics more explicitly and is useful when the user wants a lower-level view of Rank-N/Field relations.

Example:

```whex
program whex_heat_equivalence
tolerance 1e-10

input n: u64 range 4..100000000

field u[i in n]: f64 =
    0.25 + cast(f64, (i * 17 + 3) % 1024) / 1024.0

each i in n {
    next: f64 =
        u[i]
        + 0.125 * (
            u[periodic(i + n - 1, n)]
            - 2.0 * u[i]
            + u[periodic(i + 1, n)]
        )
}

sum checksum[i in n]: f64 = next[i]
output checksum
```

WH is the friendlier surface; WHEX is the more explicit structural surface. Both are lowered before final physical realization.

---

## Quick start

The release archive ships prebuilt static compiler binaries under `bin/`.

```sh
unzip Wheelchair-1.3.49.zip
cd Wheelchair-1.3.49

./bin/wheelchairc surface/examples/equivalent_en.wh -o demo
./demo 4
```

The same archive can rebuild the production binaries from source:

```sh
./build.sh
```

Typical compiler entry points are:

```sh
bin/wheelchairc INPUT.wh   -o OUTPUT
bin/whexc      INPUT.whex -o OUTPUT
```

The archive also contains lower-level physical compiler entry points (`topologyc*` and `fieldc*`). Normal source users generally do not need to select them manually; the production launcher performs compile-time structural classification before invoking the appropriate physical compiler.

### Build requirements

The current production build expects a Linux x86-64 environment with standard POSIX shell tooling and GNU binutils, including tools such as:

```text
sh
as
ld
nm
objcopy
readelf
awk
grep
sha256sum
```

The production build does not use Python as a compiler generator and does not route generated user code through GCC, Clang, LLVM, MLIR, or a JIT backend.

---

## Core semantic model

### ValueFacts

A **ValueFact** is more than a temporary variable. It represents a semantic value together with the information required to reason about its identity and physical realization, such as precision, version, reuse, provenance, and causal lifetime.

This lets the compiler reason about questions that would otherwise become repeated runtime work or ad-hoc optimizer guesses.

Examples include:

- identical immutable loads;
- repeated predicates;
- constants reused across multiple outputs;
- old-state versus new-state values in simultaneous updates;
- precision-neutral constants such as zero and one;
- structured values whose scalar components can be shared;
- values whose last consumer is already known at AOT time.

### Physical Reality

**Physical Reality** is Wheelchair's compile-time description of how a proved semantic relation maps onto actual machine constraints and costs.

It includes facts such as:

- available ISA shape;
- physical vector width;
- register/carrier pressure;
- load and address cost;
- locality and reuse;
- materialization cost;
- execution-context creation cost;
- value lifetime;
- strict versus tolerant numerical constraints.

The goal is not to build a runtime autotuner. The goal is to make physical decisions from AOT-known facts whenever the program structure already contains enough information.

### Physical DAG

The **Physical DAG** represents the necessary partial order of physical work.

Independent work may occupy the same causal depth. Serialization appears only when a real dependency, numerical contract, state transition, or other semantic relation increases the required causal span.

A simplified view is:

```text
semantic relation
      ↓
ValueFacts
      ↓
causal dependency graph
      ↓
physical lifetime / locality / ISA facts
      ↓
Physical DAG
      ↓
local continuation or outward realization
      ↓
native machine code
```

---

## Structural execution

Wheelchair does not define parallelism as "take a sequential program and distribute loop iterations to workers." Instead, it treats independent causal structure as independently realizable physical work.

The project uses the structural model:

```text
S_struct(P) = W / (max(W/P, S) + H)
```

with the idealized form:

```text
S_struct_ideal(P) = min(P, W/S)
```

where:

- `W` = necessary physical work;
- `S` = weighted causal span;
- `H` = critical-path realization overhead;
- `W/S` = intrinsic causal parallelism.

This model is diagnostic, not a runtime scheduler.

### Local continuation vs outward execution

A ready piece of work means that it **may** execute independently. It does not mean that Wheelchair must create another OS execution context.

The same causal subtree can be realized as:

```text
local continuation
```

or:

```text
outward execution
```

and the AOT physical-cost model selects between them. There is no fixed "more than N elements means clone" threshold.

This distinction became especially important in 1.3.18, where lightweight independent work stopped paying unnecessary clone/wait/exit/context-switch cost while heavy independent work could still expand outward.

### Resource release

Wheelchair's parallel architecture does not use work stealing, donor/recipient lookup, a central ready queue, or persistent idle workers searching for work.

When a causal execution region is finished, its resources are released. Where those resources are subsequently used is left to the external operating-system/hardware substrate rather than managed through a Wheelchair-owned global redistribution fabric.

---

## Where structural execution has beaten C, and where it has not

Wheelchair's benchmark history is intentionally mixed. The project keeps negative controls because the execution model has a real domain of advantage rather than a universal speed multiplier.

### Measured advantage region

Structural execution has shown its strongest results when the workload has **high intrinsic causal parallelism** and enough useful work to amortize realization cost, especially when the compiler can also eliminate transport, repeated address work, or redundant materialization.

Representative cases include:

- large independent Tensor reductions;
- heavy fluid-solid coupled spatial work;
- some regular Field/stencil kernels;
- workloads where one Physical DAG exposes independent regions without needing a central scheduler;
- workloads where local continuation avoids execution-context overhead for light independent work.

A landmark 1.3.18 same-host rematch measured:

| Workload | Wheelchair 1.3.18 | GCC C | GFortran | Result |
|---|---:|---:|---:|---|
| lightweight Tensor reduction, 100M | **7.773 ms** | 20.659 ms | 20.677 ms | Wheelchair ≈ **2.66× C throughput** |
| FSI, 100M | **46.626 ms** | 70.313 ms | 63.084 ms | Wheelchair ≈ **1.51× C throughput**, **1.35× Fortran** |

These were interleaved same-host measurements using GCC/GFortran 14.2-class native optimization. The lightweight reduction was bit-identical across languages; the FSI reduction used its declared tolerant numerical contract.

### Measured disadvantage region

Structural execution does not create parallelism that the mathematics does not contain.

Wheelchair has historically been weaker in regions such as:

- strongly causal scalar recurrences with low `W/S`;
- small state-transition loops where mature C/Fortran scalar code generation is already near the hardware limit;
- wide or irregular sparse neighborhoods where necessary memory work dominates and Wheelchair's current realization is less mature;
- workloads where constant realization, scalar scheduling, or register scheduling remains a larger cost than structural overhead;
- small arbitrary-precision products where the fixed cost of the single common Fourier multiplication authority dominates.

The same 1.3.18 rematch deliberately retained a negative control:

| Workload | Wheelchair 1.3.18 | GCC C | GFortran | Result |
|---|---:|---:|---:|---|
| 7-state rigid-body causal control, 1M | 15.359 ms | **9.706 ms** | 10.132 ms | Wheelchair ≈ **1.58× C time** |

Likewise, the 1.3.12 500M two-state recurrence measured 427.384 ms for Wheelchair versus 177.460 ms for C and 178.169 ms for Fortran. That release improved Wheelchair's own previous implementation by 4.783×, but it still remained about 2.4× slower than the mature scalar controls.

The intended boundary is therefore:

```text
high independent structural work + removable physical overhead
    -> Wheelchair can be very strong

low causal width / scalar recurrence / mature scalar scheduling problem
    -> C or Fortran may remain faster
```

---

## Representative benchmark history

The table below keeps a small set of benchmark landmarks rather than turning the README into a leaderboard. Headline comparisons use mainstream native references: GCC C, GFortran, and, for arbitrary precision, GMP's C library implementation.

| Release | Benchmark | Representative result | What it established |
|---|---|---|---|
| **1.2.11** | Fluid-solid coupling, 100M, q4 | Wheelchair 55.848 ms vs C 62.613 ms | First same-host C win on one heavy FSI point, while the six-case geometric mean still favored C. |
| **1.2.14** | Dense 128×128 Rank-3 bilinear contraction | Wheelchair ≈ 1.385× C time, but ≈ 0.814× Fortran time | Dense caretaker work materially improved Wheelchair, but expert C remained the stronger control. |
| **1.3.12** | 500M two-state recurrence | Wheelchair 427.384 ms vs C 177.460 ms vs Fortran 178.169 ms | Causal-state collapse gave a 4.783× internal speedup but exposed the low-causal-width scalar limit. |
| **1.3.18** | 100M lightweight Tensor reduction | Wheelchair 7.773 ms vs C 20.659 ms vs Fortran 20.677 ms | Local/outward realization removed execution-context overhead and produced a large structural win. |
| **1.3.18** | 100M FSI | Wheelchair 46.626 ms vs C 70.313 ms vs Fortran 63.084 ms | Heavy independent spatial work entered Wheelchair's strong region. |
| **1.3.18** | 1M rigid7 causal control | Wheelchair 15.359 ms vs C 9.706 ms vs Fortran 10.132 ms | Same release, same host, negative control: structural execution does not erase causal span. |
| **1.3.26** | miniAMR 7-point, 256³ | Wheelchair 12.113 ms vs C 12.481 ms vs Fortran 12.773 ms | Field ValueFact lifetime slightly exceeded the measured C kernel by about 3.0%. |
| **1.3.26** | miniAMR 27-point, 256³ | Wheelchair 24.636 ms vs C 17.750 ms vs Fortran 31.001 ms | Wider stencil remained behind C while still ahead of the measured Fortran control. |
| **1.3.40** | 262k–4M-bit multiplication | Wheelchair stayed within roughly ±20% of GMP `mpf_mul`; several measured sizes were faster | One common native Fourier multiplication authority reached the range of a mature arbitrary-precision library without a size-based algorithm tree. |
| **1.3.44** | mass3 / chem6 / rigid7 scalar recurrence set | geometric mean Wheelchair = 1.0978× C time; Fortran = 0.9783× C time | Native mathematics generalized while the remaining mature-scalar-codegen gap stayed visible. |

All numbers above are **host- and workload-specific measurements**, not universal language rankings. Absolute results depend on CPU, virtualization, affinity, compiler version, frequency behavior, memory system, and problem shape. Raw benchmark and validation material is retained inside the versioned release archives under `devtrash/`.

---

## Real sparse simulation probes

Wheelchair also keeps non-synthetic simulation kernels based on established miniapps. The 1.3.26 release archive contains matched C/Fortran/Wheelchair probes derived from:

- Mantevo miniAMR 7-point and 27-point stencil modes;
- Mantevo miniFE Hex8 steady heat-conduction interior assembly;
- CloverLeaf x-velocity acceleration pressure/viscosity-gradient kernel.

On the 1.3.26 validation host:

| Kernel | C | Fortran | Wheelchair 1.3.26 |
|---|---:|---:|---:|
| miniAMR 7-point | 12.481 ms | 12.773 ms | **12.113 ms** |
| miniAMR 27-point | **17.750 ms** | 31.001 ms | 24.636 ms |
| miniFE Hex8 heat, 21 numeric neighbors | **17.358 ms** | 50.167 ms | 25.817 ms |
| CloverLeaf x-acceleration | **15.635 ms** | 31.704 ms | 24.371 ms |

This is a useful snapshot of Wheelchair's real boundary: a regular narrow neighborhood can reach or slightly exceed C, while wider sparse/Field work still leaves room for the mature C compiler to win.

---

## Numerical contracts

Wheelchair does not treat all floating-point programs as if reassociation were always legal.

### Strict

Strict execution preserves the numerical ordering required by the source contract. Optimizations that would change strict operation order, such as prohibited reassociation or contraction, are not used merely to win a benchmark.

### Tolerant

A tolerant contract may permit transformations that are valid inside the declared tolerance boundary. This allows a broader physical realization while keeping the numerical contract explicit.

This distinction is important in the benchmark archive: strict and tolerant results are not silently mixed.

---

## Precision is data

Native `f32` and `f64` use direct CPU paths. Wider floating-point precision belongs to one parameterized semantic family:

```text
fpP
```

where `P > 64` is the significand precision in bits.

The architecture is intentionally not:

```text
fp128 implementation
fp256 implementation
fp512 implementation
fp2048 implementation
```

Instead:

```text
operands
    ↓
precision-propagation meet
    ↓
consumer-required precision
    ↓
physicalization
```

`precision_propagation 0` chooses the lower precision at the actual consumer edge; `precision_propagation 1` chooses the higher precision. Child expressions retain their natural precision until that edge.

For `P > 64`, current production multiplication uses one native Rank-N Fourier authority rather than switching among small/medium/large precision algorithm families.

---

## Mathematics

Wheelchair's human surface has grown into a native mathematical layer rather than a collection of external library calls.

Current families include, among others:

- elementary arithmetic and transcendental functions;
- trigonometric and hyperbolic functions and inverse forms;
- `sqrt`, `exp`, `log`, `sin`, and `cos` over parameterized `fpP` values;
- `hypot`, `fma`, `clamp`, interpolation, and `sinc`-style relations;
- Gamma/Beta-family relations;
- error functions;
- Lambert W;
- Bessel-family relations;
- zeta/polylog-style special functions;
- combinatorial functions;
- structured complex arithmetic;
- structured matrices, transpose, trace, inverse, decompositions, matrix functions, eigen/SVD-family relations where supported by the generalized workset;
- symbolic differentiation;
- Gauss-Legendre-style compile-time integration relations;
- `root(...)` as a sparse compile-time root relation.

### Root relation

The root surface is intentionally not split into separate "real root" and "complex root" solvers.

```text
root(x, expression, guess)
root(x, expression, guess, static_iterations)
```

One RootRelation performs AOT Newton work over the existing structured-number semantics and emits sparse validity, real, and imaginary facts. A real result is a projection of the same relation, not a second solver family.

---

## Rank-N, Tensor, Field, and Matrix

Wheelchair's numerical structure is not limited to flat arrays.

### Rank-N / Tensor

Rank-N semantics describe multidimensional coordinate relations, reductions, contractions, affine neighborhoods, periodic relations, axis erasure, and structured dependency facts directly.

### Field

Field semantics represent materialized spatial data with neighborhood relationships and physical load/address facts. The compiler can reason about resident immutable loads, address identity, mutation versions, local helpers, and phase lifetime without a runtime field scheduler.

### Matrix

Matrices are structured mathematical facts, not the mandatory global execution substrate. Named small matrix forms may exist as source aliases, while the underlying base relation is dimension-bearing. The project prefers one generalized relation over `matrix2`, `matrix3`, `matrix4`, `matrix5`, ... algorithm families.

Release 1.3.45 and 1.3.46 specifically improved the **human shell**, allowing matrix facts, selected-axis contraction, affine field neighborhoods, and compile-time static `select` relations to compose before erasing to the existing canonical Field graph.

The 1.3.46 compact Hex8 probe preserves the original **384-term accumulation order per output component** and is validated against the hand-expanded strict reference with byte-identical output fields.

---

## Compiler and runtime implementation

The production compiler/runtime sources are primarily handwritten x86-64 assembly and linker descriptions under:

```text
compiler/
runtime/
```

The build produces static ELF executables. The current architecture includes AVX2/native256 and AVX-512/native512 physical paths where applicable.

The production path intentionally excludes:

```text
C backend
C++ backend
LLVM backend
MLIR backend
JIT compiler
Python compiler generator
bytecode VM
runtime work-stealing scheduler
central global ready queue
benchmark-name dispatcher
```

C, Fortran, Python, GMP, and other external tools may appear under `devtrash/` as benchmarks, independent oracles, test harnesses, or historical evidence. They are not linked into the production compiler/runtime authority.

---

## Release archive structure

A current release ZIP is organized roughly as:

```text
Wheelchair-1.3.49/
├── README.md                         # release-internal engineering notes
├── VERSION
├── SHA256SUMS
├── build.sh
├── RELEASE_NOTES_1_3_49.md
├── WHEELCHAIR_CHARTER_1_3_49.md
├── PURE_ASSEMBLY_RELEASE_PROOF_1_3_49.md
├── PRODUCTION_BIN_SHA256_1_3_49.txt
├── bin/                              # production executables
├── compiler/                         # current compiler source authority
├── runtime/                          # current runtime source authority
├── surface/                          # WH/WHEX examples and surface authority
├── tools/                            # production build/inspection helpers
└── devtrash/                         # tests, benchmarks, history, archaeology
```

`devtrash/` is intentionally a **non-production archaeology zone**. Historical benchmarks, old release proofs, old source experiments, regression suites, and validation scripts can remain there without becoming active architecture again.

The rule is:

> Historical evidence may remain. Historical architecture does not regain production authority merely because the code still exists in the archive.

The Git repository itself stays comparatively small; complete release trees are stored as versioned archives under `dist/` rather than expanding every historical compiler tree into `main`.

---

## Landmark architecture releases

Wheelchair changes quickly, but the following releases mark major changes in the architecture rather than ordinary feature accumulation.

| Version | Landmark |
|---|---|
| **1.2.10** | Human WH/WHEX surface and general causal physicalizer moved into the handwritten native production chain; Python left the production compiler/runtime path. |
| **1.2.14** | Dense caretaker completion: induction, LICM, unrolling, delayed reductions, lifetime reuse, and related generic dense cleanup. |
| **1.2.15** | Rank-N coordinate algebra and native neighborhood relations matured. |
| **1.2.16–1.2.18** | Native Field ABI, Field locality work, and human Field surface became part of the common language path. |
| **1.3.1–1.3.7** | Physical Reality/ValueFact work progressively replaced repeated Tensor/Field physical work with common structural facts. |
| **1.3.10** | Blind Surplus Reflow removed resource-ownership behavior that kept silicon active without reducing elapsed time. |
| **1.3.12** | Causal State Collapse kept persistent recurrence state in physical carriers instead of generic state/temp materialization. |
| **1.3.16** | Whole-episode Physical DAG unified simultaneous-update CSE and carrier-pressure reasoning. |
| **1.3.18** | Emergent outward expansion: ready work became "may execute independently," not "must create another execution context." |
| **1.3.19** | Structural execution theory consolidated around `W`, causal span `S`, and realization overhead `H`. |
| **1.3.20–1.3.27** | Value transport, predicates, Field load lifetime, and carrier lifetime were progressively sparsified through the same Physical Reality architecture. |
| **1.3.28–1.3.36** | Native mathematical semantics, structured mathematics, differentiation/integration/root-related groundwork, and broader general-language abstractions expanded. |
| **1.3.38–1.3.40** | Parameterized wide floating precision matured; one native Fourier multiplication authority replaced named-width multiplication paths. |
| **1.3.41** | Sparse mathematics fusion merged overlapping mathematical cores instead of accumulating duplicate approximation families. |
| **1.3.42–1.3.43** | Sparse RootRelation and precision assimilation unified real/complex/wide-precision root work. |
| **1.3.44** | Matrix and parameterized mathematics generalized beyond historical small fixed shapes. |
| **1.3.45–1.3.46** | Human-shell static structure and static branch erasure made compact mathematical WH source collapse into the existing canonical graph without adding runtime authority. |
| **1.3.47–1.3.49** | Native256 ValueFact ownership/lifetime and native256/native512 sparse physical materialization were folded into common physical-cost and lifetime authorities rather than separate workload routes. |

The version numbers are retained here because they identify architectural turning points. Ordinary future releases do not require this table to be rewritten unless they introduce another comparable change in the execution model.

---

## Benchmark policy

README performance claims follow several rules:

- compare against mainstream native references rather than obscure or deliberately weak opponents;
- retain C/Fortran negative controls when they win;
- use matched mathematical work and explicit numerical contracts;
- record compiler flags, host, affinity, repetition count, and raw results in the release archive;
- distinguish strict bit-identity from tolerant numerical equivalence;
- avoid turning one favorable point into a universal language ranking;
- treat performance anomalies as evidence about `W`, `S`, `H`, locality, carrier pressure, or machine work rather than as justification for a benchmark-specific backend.

For this reason, the README intentionally contains both wins and losses.

---

## Current limitations

Wheelchair is still an experimental language/compiler project rather than a drop-in replacement for the complete C/Fortran ecosystem.

Current practical limits include:

- production target is currently Linux x86-64 / static ELF64;
- the compiler/runtime are highly architecture-specific;
- not every mathematical relation has equal maturity across all domains and precisions;
- extreme wide-precision trigonometric argument reduction remains a documented maturity frontier;
- some advanced matrix relations reject structures beyond their generalized workset rather than silently selecting another private implementation;
- scalar causal code generation and wide sparse-memory kernels can still trail mature GCC/GFortran code;
- benchmark results from cloud/virtualized hosts can vary materially between passes.

The project generally prefers an explicit rejection or visible performance gap over silently adding a second incompatible architecture to hide it.

---

## Repository policy

`main` is intended to remain a stable project entry point rather than a dump of every historical source tree.

- `README.md` describes the language and stable architecture.
- `dist/` stores versioned release archives.
- the complete production tree, release proofs, raw benchmark evidence, and historical archaeology travel inside each release archive.
- future README edits should normally be limited to the current-release line, a genuinely new architectural landmark, or a benchmark that changes the known performance boundary.

That policy is deliberate: the README should describe **Wheelchair**, not narrate every patch release.

---

## 中文简要说明

Wheelchair 是一个面向 **HPC、数值计算和仿真** 的通用型 AOT 编程语言。它的核心不是把传统顺序程序再并行化，而是从 Rank-N、ValueFact、因果依赖和 Physical DAG 出发，直接决定哪些计算必须串行、哪些计算天然同层、哪些中间值和通信可以在编译期消掉。

简单来说：

- `WH` 是面向人的简洁语法，`WHEX` 是更显式的结构语义；
- 当前生产链是 **手写 x86-64 汇编编译器 + AOT + 静态 ELF**，不以 C/LLVM/JIT 作为生产后端；
- 结构执行在大型独立 Tensor/Field/FSI 工作中曾实测超过 GCC C 和 GFortran；
- 在强因果标量递推、宽稀疏访存和成熟标量调度区域，C/Fortran 仍然可能更快；
- README 的性能表同时保留胜局和败局，不把单个 benchmark 当成整个语言的排名；
- 以后普通版本升级原则上只需要改顶部的当前版本，主体只有在执行架构或已知性能边界真正变化时才需要修改。
