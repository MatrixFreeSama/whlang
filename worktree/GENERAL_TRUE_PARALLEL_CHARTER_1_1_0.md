# Wheelchair / WHEX General True-Parallel Charter — 1.1.0

## Highest rule

A higher abstraction is acceptable only when it preserves or improves the proven
machine topology. Wheelchair does not pay abstraction tax merely because the source
language becomes richer.

```text
human abstraction rises
        +
compile-time structural knowledge rises
        ->
false dependencies fall
runtime objects fall
serial work does not appear
```

The release contract is:

```text
FeatureComplete = Correct && Erased && Parallel && NonRegressive
```

## Structural path

```text
Human Semantic Layer
    -> Axis Algebra
    -> Region / Ownership Algebra
    -> Effect Algebra
    -> Operator / Relation Algebra
    -> Dependency / Control Topology
    -> Parallelism Preservation Proof
    -> Resource Plan
    -> ISA Capability Realization
    -> Native Code
```

Syntax is not allowed to jump directly to a sequential machine loop.

## No hidden von-Neumann spine

Unless source semantics contain a real causal dependency, a lowering pass may not
introduce:

- a central fetch/dispatch loop;
- a global task queue;
- a root spawn-all loop;
- a root wait-all loop;
- a root sequential reduction sweep;
- a global barrier;
- a scalar boundary path;
- a scalar tail;
- a scalar tensor fallback;
- an implicit global lock;
- an implicit runtime borrow table that serializes independent work.

No dependency edge means no synchronization edge.

## Parallelism preservation

Every structural pass must preserve the independent domain width unless it proves
that the corresponding work is mathematically unnecessary.

Mathematical elimination is not serialization. Examples include:

- canceled operator directions;
- identical pure-map common subexpressions;
- periodic relation collapse;
- predicate erasure in proven interior regions;
- irrelevant Rank-N axis elimination.

A resource shortage may select another vector recipe or reject compilation. It may
not select scalar tensor execution.

## Effect and ownership discipline

The pure lane is immutable and race-free by construction. Future mutable semantics
must be expressed through Region/Effect relations and must prove disjointness,
atomicity, or causal ordering. Failure to prove one of those conditions is a compile
rejection, not permission for the compiler to insert a hidden global lock.

## Control discipline

Source `if`, `match`, `select`, or future loop syntax describes semantic control, not
a required central program-counter sequence. Lowering first attempts predicate/dataflow,
state graph, recurrence, scan, reduction, wavefront, or independent-axis structure.
Only a genuinely causal source relation may survive as ordered execution.

## Runtime erasure

Any fact known at compile time must remain compile-time knowledge unless runtime
publication is semantically observable. Shape metadata, region names, pure structural
functions, record containers, effect annotations, dependency metadata, and proven
axis relations are not runtime objects in the current WHEX lane.

## Performance preservation

A language-semantic release may not regress existing native kernels. 1.1.0 therefore
requires old WHEX canonical graphs and native ELFs to remain byte-identical. New
high-level abstractions are compared against manually inlined equivalents and must
also erase to byte-identical native output.

A future release that intentionally improves native code may update the frozen
machine-code baseline only after numerical, topology, and performance gates establish
that the change is an improvement rather than abstraction overhead.

## No benchmark specialization

Optimization decisions may depend on algebraic, axis, region, effect, dependency,
capability, or machine-resource properties. They may not depend on workload, solver,
benchmark, language-opponent, or file names.

## Rank-N rule

Dimensional information is preserved through proof. It must not be flattened early
for implementation convenience. When an axis is mathematically irrelevant it may be
eliminated before native realization. When a used Rank-N structure lacks a physical
realizer, compilation rejects explicitly rather than fabricating a hidden serial nest.

## Peak-preservation law: generality may not erase technical spikes

Generality is not allowed to mean convergence toward a slower common denominator.
When a narrow mature path has already demonstrated a stronger machine realization,
a later generalized abstraction must either preserve that realization directly or
recover the same structural facts through generic proof.

The compiler therefore treats every established technical peak as a retained proof
obligation, not as disposable specialization. A generalized pass may replace a
narrow implementation only when it proves all of the following:

- semantic equivalence is preserved;
- independent width is preserved or mathematically increased;
- no new serial backedge, global barrier, central queue, scalar boundary, scalar
  tail, or scalar fallback is introduced;
- previously eliminated arithmetic, dimensions, predicates, communication, and
  runtime state do not silently reappear;
- previously established recurrence, induction, relation, locality, residency,
  boundary/interior, and ISA-capability facts remain recoverable from generic
  structure rather than workload names;
- the mature performance envelope is preserved within measurement noise, unless
  the new realization is demonstrably faster.

A generalized representation that loses a previously known relation and later
recomputes it numerically is a regression even when the final checksum is correct.
Likewise, replacing a narrow zero-cost path with a universal runtime mechanism is a
regression even when the new mechanism is easier to implement.

The required direction is:

```text
narrow technical peak
    -> identify the property that created the peak
    -> promote that property into Axis / Operator / Region / Effect / Capability algebra
    -> prove it generically
    -> reproduce or improve the original native realization
```

The forbidden direction is:

```text
narrow technical peak
    -> generalized representation
    -> structural information is discarded
    -> ordinary loop / modulo / branch / synchronization is reconstructed
    -> performance collapses toward a common baseline
```

This is the **Technical Peak Preservation Contract**.

A release that expands generality but measurably destroys an established technical
peak is not considered mature. The regression must be repaired by promoting the
missing optimization into a generic structural rule, not by restoring a workload-
specific fast path.

The 1.2.1 Interior Periodic Composition Erasure is the reference example: the mature
Newton/Jv slice exposed that a generalized path had lost a periodic affine relation.
The repair did not add a Newton/Jacobian switch. It promoted the missing relation to
generic affine/modulo algebra, removed redundant interior modulo work, retained exact
boundary semantics, and restored the performance peak for every program satisfying
the same proof.

Accordingly, release validation must retain both broad semantic coverage and a
**peak-regression corpus** containing previously demonstrated machine-code peaks.
For each peak, the release must record:

1. the structural property responsible for the peak;
2. the canonical proof that still recovers that property;
3. the native-code invariant that must not regress;
4. the numerical/topology equivalence gate;
5. the same-host performance envelope or a stronger machine-code identity gate;
6. a no-workload-dispatch audit proving the optimization remains general.

Generality therefore expands the set of programs that can reach a technical peak;
it may not flatten the peak itself.

## Release gates

Every mature semantic feature must provide:

1. semantic correctness evidence;
2. abstraction-erasure evidence;
3. dependency/parallelism evidence;
4. serial-introduction report;
5. old-performance baseline preservation;
6. no-workload-dispatch audit;
7. explicit rejection evidence for unsupported semantics.

The goal is not to make Wheelchair resemble a conventional language with more SIMD.
The goal is to let the source language become more general while preserving the
structural information required to remain in the hand-tuned machine-code performance
regime.
