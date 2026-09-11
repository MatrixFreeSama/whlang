# WHEX Human Surface Specification — 1.1.0

## Definition

`.whex` means **Wheelchair Expert**. WHEX is the structural/HPC source lane whose
human abstractions must be proven and erased before native realization whenever
possible.

```text
UTF-8 human .whex
    -> conservative lexical repair
    -> high-level structural semantics
    -> Axis / Region / Effect / Dependency / Control proof
    -> abstraction erasure
    -> canonical wheelchair.tensor/1 graph
    -> handwritten topologyc
    -> ISA capability realization
    -> fused causal native execution
    -> static ELF
```

The 1.1.0 rule is stronger than "zero-cost syntax": a new abstraction is admitted
only if it either has a native structural realization or can be proven away. An
unsupported semantic construct rejects explicitly. It must never be routed through
a scalar fallback, central task queue, hidden general-language loop, or implicit
lock merely to make compilation succeed.

## Source-language boundary

- `.wh` is the sovereign general source lane.
- `.whex` is the topology/HPC structural lane.
- `whexc` rejects `.wh`.
- `wheelchairc` rejects `.whex`.
- a failed WHEX native proof is not permission to retry the same region through
  another semantic lane.

## Core declarations

The established numerical declarations remain:

```text
program
input n: u64 range min..max
strict
tolerance error_budget
field name[i in n]: f64 = expression
each i in n { name: f64 = expression }
sum name[i in n]: f64 = expression
output name
test (...) => { ... }
```

`periodic(index, extent)` remains erasable sugar for canonical modulo.

## 1.1.0 high-level structural semantics

### First-class axis declarations

```text
axis i in n
axis j in 4
```

Axis declarations are compile-time semantic objects. They create no runtime axis
metadata object.

Rank-N syntax is preserved through semantic analysis. The current physical realizer
is still rank-1, but 1.1.0 adds a real generic Rank-N elimination rule for sum
reductions: axes that are proven absent from the expression and have static positive
extents are removed algebraically before native realization.

For example:

```text
sum total[i in n, j in 4]: f64 = f(i)
```

is proven equivalent to:

```text
sum total[i in n]: f64 = 4.0 * f(i)
```

The generated canonical graph and ELF must be identical to the manually reduced
form. A genuinely used additional axis is preserved as Rank-N structure and rejected
by the current rank-1 physical realizer. It is never silently flattened into a
serial loop.

### Pure structural functions

```text
pure fn f(x: f64) -> f64 = x * x
pure generic fn g(x) = f(x) + 1.0
```

WHEX structural functions are compile-time expression transformers. Calls are
specialized and inlined before canonical IR. Recursive functions that would require
a runtime call are rejected in this lane.

Required erasure invariant:

```text
runtime function object = 0
runtime call boundary from structural function = 0
```

### Compile-time records

```text
record constants {
    alpha = 0.125
    shift = 2.0
}
```

Field access such as `constants.alpha` is substituted before canonical IR.
Records in the WHEX structural lane create no runtime aggregate object and impose no
physical memory layout. Logical structure and physical storage therefore remain
separate.

### Region / Effect / Parallel contract

```text
region compute effect pure parallel {
    field ...
    sum ...
}
```

A WHEX region is a compile-time ownership/dependency domain. In the current native
lane, a region must explicitly declare `parallel` and its effect must be `pure`.

The semantic effect vocabulary is:

```text
pure
local_state
region_write
shared_state
atomic
io
device
external
```

Only `pure` currently has a completed WHEX native realization. Other effects are
recognized as semantic categories but reject explicitly rather than being converted
to locks, queues, sequential dispatch, or the general lane.

## Dependency topology

Dependencies are inferred only from real expression references and indexed loads.
The semantic planner emits:

- binding dependency edges;
- region dependency edges;
- topological order;
- independent binding pairs;
- independent region pairs;
- critical binding depth;
- `synthetic_order_edges`.

For a valid WHEX true-parallel plan:

```text
synthetic_order_edges = 0
implicit_global_lock = false
implicit_global_allocator_lock = false
```

No reference edge means no synchronization edge.

## Control topology

Expression `select` is represented as dataflow/predicate control, not as permission
for a central sequential dispatcher.

The semantic contract records:

```text
source_loop_implies_serial_loop = false
predicate_regions_are_dataflow = true
```

Existing native boundary/interior vector partitioning remains the physical
realization for proven control regions where applicable.

## Ownership and race contract

The current WHEX pure lane uses compile-time unique output ownership:

- each binding owns one immutable result region;
- dependencies create read sets only;
- shared mutable writes are zero;
- no runtime borrow table is introduced;
- no implicit lock is introduced;
- uncertain aliasing in future mutable extensions must reject unless explicitly
  resolved by a genuine topology rule.

Current index safety policy is `native proof or compile rejection`.

## Parallelism Preservation Contract

Every admitted WHEX binding is marked `parallel_required`.

The formal rule is:

```text
preserve independent domain width unless work is mathematically erased
```

Mathematical Rank-N axis elimination counts as work elimination, not lost
parallelism. Resource pressure is never permission to generate scalar tensor code.

## Serial-Introduction Report

The 1.1.0 planner emits explicit counters:

```text
new_serial_backedges
new_global_barriers
new_central_loops
new_scalar_regions
new_scalar_tails
new_scalar_fallbacks
new_global_queues
new_ordered_dependencies
```

For the current pure WHEX lane every counter must remain zero. Future language
features must make any semantically necessary ordering explicit rather than hiding it
inside runtime machinery.

## Abstraction and runtime erasure

The semantic plan separately reports surface and runtime objects. Current invariants:

```text
surface function -> runtime function object = 0
surface function call -> runtime call boundary = 0
surface record -> runtime record object = 0
surface region -> runtime region object = 0
effect declaration -> runtime effect dispatcher = 0
axis declaration -> runtime axis metadata object = 0
```

Compile-time knowledge is not re-materialized as runtime work.

## Machine-code non-regression

1.1.0 is a semantic-layer expansion over the 1.0.15 native backend. Existing WHEX
programs must preserve their canonical graph and native ELF byte-for-byte. The release
gate freezes the 1.0.15 periodic-heat native image hash and its historical checksum.

New abstractions are tested against manually inlined equivalents. The abstract and
inline source must produce byte-identical canonical graphs and byte-identical native
ELFs.

## Physical native contract inherited unchanged

The current rank-1 tensor realizer retains:

- fused generated vector episode;
- cross-vector axis induction;
- cross-episode constant residency;
- AVX-512 capability recipes;
- masked vector tail;
- vector boundary/interior partition;
- distributed causal fan-in reduction;
- zero tensor scalar oracle;
- zero `call eval_slot` runtime sites;
- no central spawn/wait/reduction loop;
- no global task queue;
- no tensor-to-general retry.

## Explicit current boundary

1.1.0 is the mature **general true-parallel semantic foundation**, not a false claim
that every system-language facility already has a native WHEX realization.

Completed in the WHEX structural lane:

- first-class axis metadata;
- one generic Rank-N algebraic axis-erasure lowering for reductions;
- pure/generic structural functions;
- compile-time records;
- Region/Effect semantics;
- dependency and region topology;
- control-topology reporting;
- compile-time ownership/race contract;
- serial-introduction audit;
- abstraction/runtime erasure audit;
- machine-code non-regression contract.

Not silently faked in this release:

- arbitrary used Rank-N physical realization;
- mutable/shared-state WHEX regions;
- I/O/device/external effects;
- runtime closures;
- runtime object/variant storage;
- dynamic module loading.

Those constructs require future genuine topology-native realizations. Until then,
explicit rejection is part of the language contract.
