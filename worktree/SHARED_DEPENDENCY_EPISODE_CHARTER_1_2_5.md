# Shared Dependency Episode Physicalization Charter — 1.2.5

Wheelchair 1.2.5 introduces a workload-name-blind AOT physicalization rule for high-pressure multi-field and multi-channel tensor graphs.

## Law

Multiple semantic fields do not imply multiple physical execution episodes.

A terminal reduction is recursively inspected through pure map bindings. Distinct `(binding, structural-coordinate)` loads form a compile-time pressure estimate. The estimate contains no physics name, solver name, source-file name, runtime type tag, or benchmark identifier.

## Recipes

- pressure `<= 10`: the mature 1.2.4 physical recipe is retained;
- pressure `11..14`: the Shared Dependency Episode wide recipe is selected;
- pressure above the proved wide capacity: the existing proved vector recomputation recipe is retained explicitly. There is no scalarization;
- Rank-N keeps its separately proved Rank-N physicalization.

The wide Rank-1 recipe owns:

- `ZMM16..ZMM29`: persistent dependency / CSE ownership;
- `ZMM30..ZMM31`: resident immutable constants;
- `ZMM12..ZMM15`: untouched runtime reduction ownership.

Constants that do not obtain residency are consumed from the immutable RIP-relative constant pool with vector broadcast addressing.

## Tolerant literal reciprocal erasure

Under tolerant floating-point semantics only, a finite non-zero literal division may be lowered as multiplication by an AOT-computed rounded binary64 reciprocal when that reciprocal is normal. Zero, non-finite, and subnormal-reciprocal cases retain the existing proved vector division recipe. Strict floating-point mode retains the mature exact-power-of-two rule and the original division rounding semantics otherwise.

The reciprocal computation belongs to compilation. No scalar division instruction is copied into generated runtime code. Rejecting subnormal reciprocal results also prevents inherited FTZ/DAZ state from changing the emitted program.

## Non-negotiable invariants

```text
WORKLOAD_DISPATCH=0
RUNTIME_DISPATCH=0
SCALAR_FALLBACK=0
HIDDEN_SERIAL_FALLBACK=0
RESOURCE_SHORTAGE_SCALARIZATION=0
RUNTIME_RESERVED_ZMM12_15=PROTECTED
NO_DEPENDENCY_EDGE_NO_SYNCHRONIZATION_EDGE=PASS
```

Low-pressure programs must preserve existing technical peaks. Newton/Jv and the 1.2.4 global-stiffness witness are required to remain native-byte identical.
