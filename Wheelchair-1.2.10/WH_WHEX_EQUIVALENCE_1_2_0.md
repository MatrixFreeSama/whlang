# WH / WHEX Surface Equivalence Contract — 1.2.0

## Definition

Wheelchair has one structural semantic core and two human source surfaces:

- **WH** is the inference-heavy, familiar surface. Sequential-looking syntax is an intent notation only.
- **WHEX** is the explicit-structure expert surface. Axis, region, dependency and reduction structure is written directly.

For every semantic construct implemented by both surfaces, the release contract is:

```text
Canonical(WH) == Canonical(WHEX)
```

and, whenever the current native topology realizer accepts that canonical graph:

```text
NativeELF(WH) == NativeELF(WHEX)
```

Byte identity is the strongest available zero-cost abstraction proof: the WH skin may not insert a loop object, branch dispatcher, runtime record, scheduler, lock, queue, scalar fallback, or extra native instruction.

## WH familiar syntax

### Structural map

WH:

```text
for i in 0..n {
    let x[i]: f64 = expression
}
```

is structural sugar for WHEX:

```text
field x[i in n]: f64 = expression
```

The WH `for` does **not** request a serial machine loop. It declares an axis-indexed independent map. The compiler must prove the structural interpretation before native lowering.

### Structural sum reduction

WH:

```text
for i in 0..n {
    total += expression
}
```

is structural sugar for WHEX:

```text
sum total[i in n]: f64 = expression
```

The `+=` spelling does not create mutable scalar state. It denotes an associative reduction topology and therefore inherits the causal fan-in tree and the existing no-root-sweep contract.

### Conditional expression

WH:

```text
if condition { a } else { b }
```

is structural sugar for WHEX:

```text
select(condition, a, b)
```

The syntax does not request a machine branch or central control dispatcher. It becomes predicate/dataflow control in the unified semantic plan.

### Pure functions, records, regions and Rank-N axes

WH accepts the same current structural declarations as WHEX:

```text
axis
pure [generic] fn
record
region ... effect ... parallel
strict / tolerance
field / each / sum
periodic(...)
```

A WHEX source body, when written with the `.wh` extension, must therefore lower to the same canonical graph through the WH structural surface. The `.whex` extension remains reserved for `whexc`; surface equivalence does not remove extension isolation.

## Dynamic `while`

WH deliberately recognizes `while` as control intent without treating it as permission to create a serial backedge.

The current unified structural native core does not yet have a general recurrence/fixed-point realization for arbitrary dynamic `while`. Therefore such a request in the WH structural lane is an **explicit compile rejection**.

This is a release invariant:

```text
unproved while
    != sequential fallback
    != general-lane retry
    != hidden central loop
```

A future accepted `while` must first prove a recurrence, fixed-point, wavefront, scan, frontier or other dependency topology. Only semantically necessary ordering may survive.

## Rank-N policy

WH and WHEX share the same current Rank-N rule:

1. preserve all source axes through structural proof;
2. algebraically erase an axis only when the expression is proved independent of it;
3. fold the erased static multiplicity into the expression;
4. never flatten a genuinely used additional axis into a serial nest merely to satisfy the current rank-1 physical realizer;
5. reject unsupported non-erasable Rank-N topology explicitly.

## Parallelism preservation

The WH structural lane inherits the WHEX plan invariants:

```text
new_serial_backedges = 0
new_global_barriers = 0
new_central_loops = 0
new_scalar_regions = 0
new_scalar_tails = 0
new_scalar_fallbacks = 0
new_global_queues = 0
new_ordered_dependencies = 0
```

The WH-specific erasure report additionally requires:

```text
runtime_loop_objects = 0
runtime_if_dispatchers = 0
runtime_surface_objects = 0
imperative_syntax_implies_serial_execution = false
```

## Failure and routing contract

Compiler-lane identity is selected before native compilation.

- a structural `.wh` program enters the unified structural lane;
- if its structural proof/native realization fails, compilation fails;
- it is never retried through the sovereign legacy general lane;
- it is never scalar-emulated;
- legacy `.wh` programs that do not select the structural grammar keep the existing general/GTR behavior.

## WHEX byte freeze

1.2.0 changes no WHEX parser, WHEX semantic planner, topology compiler, ISA-capability code, or tensor/general native runtime source from the 1.1.0 release.

`tests/WHEX_FROZEN_1_1_0_SHA256.txt` freezes those implementation files, while `test_wh_equivalence_120.sh` also freezes representative 1.1.0 WHEX canonical graphs and native ELFs.

This guarantees that WH gains the WHEX semantic power by adding an inference surface, not by perturbing WHEX.

## Current maturity boundary

1.2.0 establishes **surface equivalence for the current mature WHEX semantic set**. It does not claim that arbitrary mutable state, I/O effects, general dynamic `while`, arbitrary non-erasable Rank-N tensors, or the future 256-bit AVX2 tensor realizer are complete. Those capabilities remain explicit semantic/rejection boundaries on both sides rather than excuses for hidden sequential execution.
