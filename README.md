# Wheelchair

**Wheelchair** is an ahead-of-time, native, structure-first programming language project for general programming and high-performance numerical work.

Current release: **1.2.1**

Wheelchair has two human-facing source styles over the same structural core:

- **WH (`.wh`)** is the inference-heavy human surface. It may use familiar forms such as `for`, `if`, records and functions while the compiler proves the underlying structure.
- **WHEX (`.whex`)** is the explicit expert surface. It exposes axes, fields, reductions, regions, effects and structural relationships directly.

For semantics implemented by both surfaces, the intended contract is:

```text
WH source                 WHEX source
   |                          |
   | structural recovery      | explicit structure
   v                          v
        Unified Structural Core
                 |
                 | proof + erasure + topology lowering
                 v
          Native x86-64 ELF
```

The familiar WH surface is not a second, slower implementation tier. If WH and WHEX express the same proven structure, they converge on the same canonical core and, where the current native realizer accepts that graph, the same native image.

Wheelchair is deliberately conservative about unsupported semantics. A construct that cannot yet be given a genuine structural/native realization is rejected instead of being silently converted into a scalar fallback, a hidden global queue, or a conventional sequential execution spine.

---

## Release download

The current source/evidence release is:

```text
dist/Wheelchair-1.2.1.zip
```

SHA-256:

```text
8ed8f27125a47d816dbae8d56b6f71060d28e75b33ab76edb664596569884490
```

The previous 1.2.0 archive is retained in `dist/` for historical comparison.

---

## What changed in 1.2.1

Wheelchair 1.2.1 preserves the 1.2.0 WH/WHEX human surfaces and canonical semantics while improving the physical realization.

### Interior Periodic Composition Erasure

1.2.1 adds a generic structural rule for proven interior periodic coordinates.

A dynamic periodic index is normalized to an affine relation:

```text
c*axis + q*n + d
```

The exact `q*n` term disappears in the modulo ring. The compiler then composes the remaining affine coordinate with the current logical root and proves that every active lane of the already-proven interior vector region lies in `[0,n)`.

Only after that proof may the physical dynamic modulo be erased.

Boundary regions retain exact periodic semantics. An unproved case retains the full modulo path. No workload or solver name participates in the decision.

### Technical Peak Preservation Contract

Wheelchair 1.2.1 makes a new release invariant explicit:

> **Generality is additive, not flattening.**

Generalization may not turn a previously demonstrated technical performance peak into a slower common denominator merely to make the implementation look uniform.

The required direction is:

```text
narrow technical peak
        |
        v
identify the structural property
        |
        v
promote it into generic algebra
        |
        v
prove it for every matching program
        |
        v
reproduce or improve the native realization
```

The forbidden direction is:

```text
narrow technical peak
        |
        v
general representation
        |
        v
important information discarded
        |
        v
ordinary loop / modulo / branch / synchronization rebuilt
        |
        v
performance collapse
```

The Newton/Jv restoration in 1.2.1 is the reference case. The lost periodic-affine relation was promoted into generic structural algebra instead of being restored as a benchmark-specific fast path.

### Lane identity hardening

Source typo repair is intentionally conservative.

An exact structural marker may select the structural lane. If no exact marker exists, a single fuzzy spelling coincidence is not allowed to change the execution model. At least two independent repairable line-leading structural markers are required before fuzzy repair can select the structural lane.

After the lane is selected, ordinary one-character repair remains available inside that lane.

---

## Current platform

The current native toolchain targets **Linux x86-64** and is built directly with GNU binutils.

You need:

- an x86-64 Linux system;
- Python 3 for the human-facing compile-time surfaces;
- GNU `as`, `ld`, `readelf`, and related binutils tools;
- a POSIX shell.

For the current structural tensor/WHEX native path, the physical realizer is 512-bit and requires **AVX-512F-class capability**.

AVX-512DQ operations may use native instructions or proven AVX-512F foundation recipes where implemented. AVX-512VL is not a semantic requirement of the current 512-bit realizer.

AVX2 is represented in the ISA capability model, but 1.2.1 does **not** claim a complete 256-bit structural tensor backend. A structural program that requires the 512-bit realizer is rejected under an AVX2-only ceiling instead of being silently converted to scalar tensor execution.

The native backend does not depend on C, C++, LLVM, or a JIT. The core native compiler/runtime path is handwritten x86-64 assembly. Python participates at the human surface during AOT compilation, not in the emitted native program.

---

## Build from source

Clone the repository and extract the current release:

```bash
git clone https://github.com/MatrixFreeSama/whlang.git
cd whlang
unzip dist/Wheelchair-1.2.1.zip
cd Wheelchair-1.2.1
```

Build:

```bash
./build.sh
```

A successful build ends with:

```text
WHEELCHAIR_BUILD=PASS
```

The native build path is intentionally direct:

```text
runtime assembly
    -> static runtime image
    -> generated runtime offsets
    -> handwritten compiler assembly
    -> static topology compiler
```

The release gates check the produced native tools and generated programs for the intended static/native properties.

---

## Your first WH program

Create `first.wh`:

```text
program structural_sum
strict
input n: u64 range 4..1024

axis i in n

region compute effect pure parallel {
    for i in 0..n {
        let x[i]: f64 = cast(f64, i) + 1.0
    }

    for i in 0..n {
        total += x[i]
    }
}

output total

test (4) => { total = 10.0 }
```

Compile it:

```bash
./wheelchairc first.wh -o first
```

Run it:

```bash
./first 4
```

The current structural runtime reports the output as raw IEEE-754 bits:

```text
checksum_bits=0x4024000000000000
```

`0x4024000000000000` is binary64 `10.0`.

The important point is not the syntax. It is what the syntax means structurally.

---

## WH execution model

### `for` is not a promise of a serial loop

Consider:

```text
for i in 0..n {
    let x[i]: f64 = cast(f64, i) * 2.0
}
```

A conventional imperative interpretation would be:

```text
i = 0 -> execute body
i = 1 -> execute body
...
```

That is **not** the structural WH contract.

The compiler first asks whether the points are independent. If they are, the semantic object is an axis map. Its physical realization may use:

- independent executor regions;
- fused vector episodes;
- AVX-512 lanes;
- masked vector tails;
- cross-vector induction;
- boundary/interior vector regions.

The source spelling does not require a scalar serial machine loop.

```text
source for != required serial machine loop
```

### `+=` expresses reduction intent

Inside a structural map:

```text
for i in 0..n {
    total += x[i]
}
```

`+=` means an associative reduction over the axis. It does not request one globally shared scalar updated one element at a time.

### `if` is predicate/dataflow control

Structural WH may write:

```text
for i in 0..n {
    let x[i]: f64 = if i == 0 { 2.0 } else { 1.0 }
}
```

Its canonical structural form is a `select` expression:

```text
select(i == 0, 2.0, 1.0)
```

The source `if` does not authorize a central sequential dispatcher. A native branch may still be used when it is a justified physical realization of the proven predicate topology, but the source syntax itself does not demand one.

---

## Structural declarations

The current structural WH surface accepts the mature WHEX structural vocabulary, including:

```text
axis
pure [generic] fn
record
region ... effect ... parallel
strict / tolerance
field / each / sum
periodic(...)
```

### Pure structural function

```text
pure fn square(x: f64) -> f64 = x * x
```

### Compile-time record

```text
record constants {
    alpha = 0.125
    shift = 2.0
}
```

These are structural source objects. Where they can be proven away, they do not require runtime function objects, runtime call boundaries, heap records, region objects or effect dispatch machinery.

Compile-time knowledge should disappear before runtime whenever its meaning can be preserved without materialization.

---

## Independent regions and dependencies

Wheelchair derives ordering from real data dependencies, not from arbitrary source order.

If two pure regions have no dependency edge, the compiler is not allowed to invent one merely because one appears earlier in the file.

The semantic plan tracks:

- binding dependency edges;
- region dependency edges;
- independent bindings and regions;
- critical depth;
- ownership/read sets;
- synthetic ordering.

For the current mature pure structural lane, hidden global locks, hidden allocator locks and synthetic ordering are forbidden.

```text
no dependency != invented synchronization
```

---

## Rank-N axes

Rank-N means that the structural problem owns N independent axes. It does **not** mean "emit N nested serial loops."

Wheelchair keeps axes structural until proof.

If an extra static axis is mathematically irrelevant to an expression, the compiler may erase that axis and fold its multiplicity into the remaining expression.

If an extra axis is genuinely used, the current rank-1 physical realizer does not flatten it into a fake serial nest just to claim support. The unsupported topology remains structured and compilation rejects until a genuine realization exists.

The rule is:

```text
prove and erase when mathematically valid
otherwise preserve structure
never fake Rank-N with hidden serial nesting
```

---

## What happens to `while`

WH recognizes `while` as control intent, but arbitrary dynamic `while` is not currently admitted by the unified structural native core.

An unproved dynamic loop is **not** converted into a conventional backward branch and is **not** retried through another lane.

A future accepted `while` must first prove a genuine dependency topology such as:

- recurrence;
- fixed point;
- scan;
- wavefront;
- frontier evolution;
- another explicitly modeled dependency structure.

Until then, rejection is part of the language contract.

---

## WHEX: the explicit expert surface

WHEX exposes the structure that WH attempts to infer.

The Newton/Jv release witness is written as:

```text
program newton_jv_mature
tolerance 1e-10
input n: u64 range 4..100000000
field u[i in n]: f64 = 0.25 + cast(f64, (i * 17 + 3) % 1024) / 1024.0
field v[i in n]: f64 = -0.5 + cast(f64, (i * 29 + 7) % 1024) / 1024.0
field jv[i in n]: f64 = (2.0 + 0.375 * u[i] * u[i]) * v[i] - v[periodic(i + n - 1, n)] - v[periodic(i + 1, n)]
sum checksum[i in n]: f64 = jv[i]
output checksum
```

The repository exposes this exact benchmark source at:

```text
benchmarks/newton_jv/mature.whex
```

WHEX is useful when the programmer already knows the domain structure and wants to state it directly instead of asking WH to recover it from familiar syntax.

---

## WH and WHEX equivalence

For shared mature semantics:

```text
Canonical(WH) == Canonical(WHEX)
```

and when the graph is accepted by the current native topology realizer:

```text
NativeELF(WH) == NativeELF(WHEX)
```

The 1.2.1 release keeps the 1.2.0 WH/WHEX surface and canonical equivalence contracts while intentionally improving the shared physical realizer.

The language therefore should not be read as:

```text
WH   = easy but slow
WHEX = hard but fast
```

It should be read as:

```text
WH   = familiar syntax + structural inference
WHEX = explicit structure + expert control over expression

both -> one structural core
```

---

## Strict and tolerant numerical contracts

Wheelchair separates numerical intent from accidental implementation order.

`strict` preserves the stricter evaluation contract required by the current strict lane.

`tolerance` allows transformations that are legal under the declared numerical tolerance, including approved reduction reassociation.

A tolerant program does not mean "anything numerically close is acceptable." The permitted transformations remain governed by the compiler's structural and numerical proofs.

The Newton/Jv witness uses:

```text
tolerance 1e-10
```

and the release audit additionally freezes bitwise reference checksums for the measured 10M and 100M cases.

---

## Executors

An executor is a physical realization resource, not a hidden source-level serial controller.

The current command-line compiler supports the established executor counts used by the structural runtime, including 1, 2 and 4 for the release benchmark:

```bash
./wheelchairc first.wh -o first-4 --executors 4
```

A valid structural program must preserve its mathematical contract across supported executor counts.

Resource pressure is not permission to fall back to scalar tensor execution. If the requested structural realization cannot be proven or physically supported, the implementation must choose another proven structural recipe or reject.

---

## Inspect the semantic plan

The structural compiler can emit a semantic plan for inspection:

```bash
./wheelchairc program.wh -o program --semantic-plan plan.json
```

The useful questions are:

- Which axes survived?
- Which axes were mathematically erased?
- Which dependencies are real?
- Which regions are independent?
- Which source abstractions disappeared?
- Did any serial backedge appear?
- Did any global barrier or central queue appear?
- Did scalar tensor fallback appear?

The release contracts treat these as machine-auditable properties rather than documentation-only promises.

---

## ISA capability selection

Wheelchair models ISA features as capabilities rather than allowing raw instruction-set names to redefine language semantics.

The current 512-bit tensor realizer includes capability rules for operations such as:

- vector FP arithmetic;
- masked tails;
- vector integer multiply;
- signed integer to FP64 conversion;
- proven nonnegative FP64 to integer truncation;
- predicate materialization;
- broadcast;
- cross-vector persistent state;
- reduction-tree support.

Some operations have both native AVX-512DQ forms and mathematically equivalent AVX-512F foundation recipes.

If the required capability cannot be realized at the selected ISA ceiling, the tensor path rejects. It does not secretly become scalar code.

---

## Conservative source auto-repair

Wheelchair supports conservative typo repair for the human surface, including selected one-character English keyword and identifier errors.

The critical boundary is lane identity:

1. exact structural vocabulary is decisive;
2. one fuzzy coincidence is not sufficient to switch execution models;
3. without an exact marker, at least two independent line-leading structural repair witnesses are required to select the structural lane;
4. typo repair then proceeds inside the already-selected lane.

This keeps source repair useful without turning spelling similarity into permission to change program semantics.

---

## Newton/Jv performance evidence

Wheelchair 1.2.1 includes a same-host restoration audit against two deliberately strong C controls.

### Audit configuration

- CPU: **Intel Xeon Platinum 8370C @ 2.80 GHz**
- virtualized x86-64 host
- fixed CPU affinity
- 1, 2 and 4 executors/cores
- N = 10,000,000 and 100,000,000
- FP64 tolerant reduction
- 65,536-coordinate chunks
- four logical accumulation carriers
- deterministic reduction topology
- three warm-ups
- 21 shuffled/interleaved whole-process measurements per contestant
- result: median wall time

### Final medians

| N | cores | **Wheelchair 1.2.1** | matched expert C | explicit AVX-512 C |
|---:|---:|---:|---:|---:|
| 10,000,000 | 1 | **15.087 ms** | 20.835 ms | 21.329 ms |
| 10,000,000 | 2 | **14.430 ms** | 18.768 ms | 18.296 ms |
| 10,000,000 | 4 | **9.977 ms** | 15.346 ms | 13.118 ms |
| 100,000,000 | 1 | **106.144 ms** | 141.877 ms | 120.285 ms |
| 100,000,000 | 2 | **63.041 ms** | 88.667 ms | 76.908 ms |
| 100,000,000 | 4 | **48.754 ms** | 64.366 ms | 56.485 ms |

Wheelchair 1.2.1 has the lower 21-run median at all six measured points on this host.

For N = 10M it uses 23.1% to 35.0% less median time than the matched C control and 21.1% to 29.3% less than the explicit AVX-512 control.

For N = 100M it uses 24.3% to 28.9% less median time than the matched C control and 11.8% to 18.0% less than the explicit AVX-512 control.

This is **not** a universal C-versus-Wheelchair ranking. It is one workload, one host and one documented numerical/measurement contract.

Full public benchmark documentation:

```text
benchmarks/newton_jv/README.md
benchmarks/newton_jv/CONFIG_1_2_1.md
benchmarks/newton_jv/results_summary_1_2_1.json
benchmarks/newton_jv/CONTROL_SOURCE_IDENTITIES.md
benchmarks/newton_jv/mature.whex
```

The cryptographically frozen release archive also contains the authoritative raw 21-run sample files:

```text
benchmarks/newton_jv/10M_21run.json
benchmarks/newton_jv/100M_21run.json
```

---

## Why 1.2.1 restored the Newton peak

The 1.2.0 proven interior still reconstructed full dynamic `% n` quotient/correction machinery for the left and right periodic neighbors before applying the downstream affine `v` map.

1.2.1 proves when those interior periodic compositions can be simplified generically.

For the mature one-executor Newton/Jv image:

```text
VCVTTPD2QQ count:      4 -> 2
VPMULLQ count:         10 -> 6
generated RX payload:  1305 -> 1209 bytes
```

The removed work is the pair of redundant interior-neighbor dynamic-modulo paths. The boundary body still retains the machinery required for exact periodic semantics.

This matters architecturally because the optimization is not named `newton_fast_path`. It is a generic relationship that any matching program may inherit after the same proof.

---

## Python is not in the timed native path

The 1.2.1 Newton audit explicitly tested the human-surface boundary.

For 1, 2 and 4 executors:

1. WHEX was lowered through the Python surface to canonical `wheelchair.tensor/1` JSON;
2. the canonical graph was also passed directly to the handwritten topology compiler;
3. the two native ELFs were compared byte-for-byte.

The result was:

```text
DIRECT_CANONICAL_ELF_EQ_E1=PASS
DIRECT_CANONICAL_ELF_EQ_E2=PASS
DIRECT_CANONICAL_ELF_EQ_E4=PASS
```

Python therefore contributes compile-time surface processing for this route, not timed runtime work and not a different native image.

---

## External C control provenance

The final audit used:

```text
matched expert C
SHA-256:
a9a9d3e908d08983e2c74f99c391e57597e37a5a404bafa153c3c140a06979b2

explicit AVX-512 C
SHA-256:
05e141dff01fcdf04a0821395fe675dc4876dfce1d60115613c18252388701ea
```

The exact external C source files were not retained in the Wheelchair 1.2.1 release tree. This repository records their cryptographic identities and does **not** reconstruct new files and falsely attach the historical results to them.

The Wheelchair source itself is retained verbatim in the repository.

If the C controls are reconstructed in the future, they must be treated as new controls with new source hashes and fresh measurements.

---

## Release gates

The 1.2.1 release completed the monolithic harness with:

```text
RC=0
WHEELCHAIR_1_2_1_COMPLETE=PASS
```

Important retained invariants include:

```text
TENSOR_HIDDEN_SCALAR_FALLBACK=0
PARALLEL_SCALAR_FALLBACK=0
RUNTIME_ERASURE=PASS
SERIAL_SPINE_ERASURE=PASS
CENTRAL_SPAWN_LOOP=0
CENTRAL_WAIT_LOOP=0
CENTRAL_REDUCTION_LOOP=0
GLOBAL_TASK_QUEUE=0
COMMUNICATION_NO_GLOBAL_SYNC=PASS
WH_SERIAL_INTRODUCTION_REPORT_ZERO=PASS
WH_DYNAMIC_WHILE_NO_SERIAL_FALLBACK=PASS
INTERIOR_PERIODIC_SCALAR_FALLBACK=0
WH_WHEX_CANONICAL_EQUIVALENCE=PASS
WH_WHEX_NATIVE_BYTE_EQUIVALENCE=PASS
WH_WHEX_SURFACE_EQUIVALENCE_1_2_1=PASS
```

Inside the release archive, the main evidence files include:

```text
RELEASE_PROOF_1_2_1.md
MATURE_1_2_1_PROOF.md
PERFORMANCE_1_2_1_NEWTON_RESTORATION.md
GENERAL_TRUE_PARALLEL_CHARTER_1_1_0.md
RELEASE_GATES.txt
SHA256SUMS
```

---

## Current maturity boundary

Wheelchair 1.2.1 has a mature structural foundation, but it does not pretend every future systems-language feature is already physically realized.

Current explicit boundaries include:

- arbitrary non-erasable Rank-N native execution is not complete;
- arbitrary dynamic `while` does not receive a hidden sequential fallback;
- mutable/shared-state structural effects are not silently lowered to locks or queues;
- I/O/device/external structural effects require genuine future realizations;
- a complete AVX2 256-bit structural tensor backend is not claimed;
- general-language memory safety is not claimed as complete.

A parsed feature is not automatically a mature feature. Mature support must either erase under proof, have a genuine topology-native realization, or reject explicitly.

---

## Design rules

### 1. Syntax does not dictate physical execution

A familiar source form may be only a human-facing skin over a different structural realization.

### 2. No dependency means no invented synchronization

Independent regions must not acquire artificial ordering merely because of source order.

### 3. Mathematical erasure comes before instruction tuning

Prefer to remove:

1. work;
2. dimensions;
3. state;
4. communication;
5. unnecessary control;

before spending effort tuning instructions that should not exist at all.

### 4. Resource pressure is not permission for scalar fallback

A structural parallel program does not become scalar merely because the requested realization is difficult.

### 5. Compile-time knowledge should not become runtime machinery

Functions, records, regions, effects, axes and relationships that can be proven away should disappear.

### 6. True parallelism must not hide a serial spine

The project gates central spawn loops, central wait loops, central reduction loops, global task queues, scalar tensor fallback and other accidental re-centralization.

### 7. Generality must preserve technical peaks

A generalized representation must preserve the structural facts that made a mature native path strong. If a narrow optimization is lost, recover its property generically rather than reintroducing a workload-specific shortcut.

### 8. Unsupported semantics reject rather than masquerade as support

A feature is mature only when its semantics survive into a valid structural/native realization or are mathematically erased.

---

## Repository layout

The GitHub root is intentionally small:

```text
README.md
assets/
dist/
    Wheelchair-1.2.0.zip
    Wheelchair-1.2.1.zip
benchmarks/
    newton_jv/
        README.md
        CONFIG_1_2_1.md
        CONTROL_SOURCE_IDENTITIES.md
        mature.whex
        results_summary_1_2_1.json
```

The complete 1.2.1 source tree, compiler/runtime sources, tests and release proofs remain inside the frozen release archive in `dist/`.

---

## A practical learning path

1. Start with ordinary WH: `program`, `input`, `let`, `output`, `test`.
2. Learn structural WH: `axis`, `region`, structural `for`, reduction `+=`, `if`, pure functions and records.
3. Rewrite the same ideas in WHEX using `field`, `sum`, `each`, axes and regions.
4. Inspect the semantic plan and verify what disappeared.
5. Inspect generated machine code and compare equivalent WH/WHEX output.
6. Study the Newton/Jv benchmark not as a leaderboard, but as an example of a structural fact surviving all the way down to machine code.

The central question in Wheelchair is not simply:

> What syntax did I write?

It is:

> What mathematical and dependency structure did the compiler prove, what information could be erased, and what physical topology remained after the proof?

That is the intended path from a readable human surface to aggressive native execution without rebuilding a hidden conventional serial machine underneath it.
