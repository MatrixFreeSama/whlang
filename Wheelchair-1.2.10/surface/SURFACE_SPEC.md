# WH Human Surface Specification — 1.2.0

## Definition

`.wh` is the inference-heavy human surface of Wheelchair. It may look familiar and imperative, but source syntax does not dictate physical execution. The 1.2.0 architecture has two compile-time WH lanes selected before native compilation:

```text
legacy/general WH
    -> canonical wheelchair.tensor/1
    -> closed static elimination
    -> General Topology Recovery when provable
    -> topology backend OR sovereign direct-general backend

structural/inference WH
    -> familiar for/if/reduction syntax + structural declarations
    -> Axis / Region / Effect / Ownership / Dependency / Control proof
    -> abstraction erasure
    -> the same canonical wheelchair.tensor/1 graph as equivalent WHEX
    -> the same topology backend
```

There is no failure-driven structural-to-general fallback.

## Surface equivalence with WHEX

WH and WHEX are two source surfaces over one structural semantic core. For semantics implemented by both surfaces:

```text
Canonical(WH) == Canonical(WHEX)
```

and when the current native topology realizer accepts the graph:

```text
NativeELF(WH) == NativeELF(WHEX)
```

WHEX asks the programmer to expose structure directly. WH asks the compiler to recover that structure from a more familiar spelling.

## Familiar structural sugar

### `for` map

```text
for i in 0..n {
    let x[i]: f64 = expression
}
```

means an independent axis map, equivalent to WHEX `field x[i in n]`.

### `for` reduction

```text
for i in 0..n {
    total += expression
}
```

means an associative sum reduction, equivalent to WHEX `sum total[i in n]`.

The source `+=` is not mutable scalar state and does not authorize a root serial sweep.

### `if`

```text
if condition { a } else { b }
```

means predicate/dataflow selection and canonicalizes to `select(condition,a,b)`. It is not a request for a branch dispatcher.

### `while`

`while` is recognized as control intent. Arbitrary dynamic `while` is not yet admitted by the unified structural native core and therefore rejects explicitly. It never falls through to a sequential backedge merely because the surface resembles a traditional language.

## Structural declarations available in WH

The `.wh` structural surface accepts the current WHEX structural vocabulary, including:

```text
axis
pure [generic] fn
record
region ... effect ... parallel
strict / tolerance
field / each / sum
periodic(...)
```

WH additionally provides the familiar `for` and `if` skins above.

## Rank-N rule

Rank-N axes are preserved until proof. An irrelevant static axis may be mathematically erased and its multiplicity folded into the expression. A genuinely used extra axis is never flattened into a serial nested loop to satisfy the current rank-1 native realizer; it remains structured and rejects until a genuine physical realization exists.

## Serial-introduction and erasure invariants

Accepted structural WH plans require zero:

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

and zero WH-surface runtime artifacts:

```text
runtime_loop_objects
runtime_if_dispatchers
runtime_surface_objects
```

## Legacy general WH

The pre-1.2.0 general grammar remains available for inputs, scalar compute, tensor/map, reductions, iterate state, records, dictionaries/lookups, nested literals/reductions, cascades, outputs/tests and the established expression set.

Closed dictionary/cascade elimination and General Topology Recovery remain unchanged. A legacy program is not silently reclassified as structural merely because it contains a similarly named identifier.

## Extension isolation

- `wheelchairc` accepts `.wh` only.
- `whexc` accepts `.whex` only.
- equivalence is semantic, not an extension-name collapse.

See `WH_WHEX_EQUIVALENCE_1_2_0.md` for the formal surface-equivalence contract.
