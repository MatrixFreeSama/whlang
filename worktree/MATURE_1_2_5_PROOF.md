# Wheelchair 1.2.5 Mature Proof

## Upgrade

Wheelchair 1.2.5 adds **Shared Dependency Episode Physicalization**, a compile-time structural recipe for tensor graphs whose persistent dependency pressure exceeds the mature 1.2.4 ten-register CSE ownership envelope.

The trigger is a canonical graph property, not a workload label. The compiler recursively expands pure map dependencies from terminal reductions, canonicalizes structural coordinates, and counts distinct map-load coordinates.

## Physical ownership

The admitted wide AVX-512 recipe uses `ZMM16..ZMM29` for persistent dependency ownership and `ZMM30..ZMM31` for resident constants. `ZMM12..ZMM15` remain runtime-owned and are never borrowed. A rejected prototype that borrowed runtime reduction registers was discarded after numeric validation detected corruption; no such recipe is present in 1.2.5.

## Preserved peaks

The selection rule is deliberately asymmetric:

- low structural pressure keeps the 1.2.4 recipe;
- only proven high-pressure graphs select the wide recipe.

Consequently the mature Newton/Jv and global-stiffness witnesses are required to remain native-byte identical to 1.2.4 for executors 1, 2 and 4.

## General tolerant reciprocal rule

A tolerant floating-point literal division may use an AOT-computed rounded reciprocal only when the divisor is finite and non-zero and the rounded reciprocal is normal binary64. Zero, non-finite, and subnormal-reciprocal cases retain the existing proved vector division recipe. Strict mode retains prior rounding semantics except for the already-mature exact-power-of-two rule.

This restriction makes the emitted result independent of inherited host FTZ/DAZ behavior.

## Development evidence before release authority

On a Xeon Platinum 8573C development host, the coupled two-field structural witness retained the exact 1.2.4 checksum bits while its generated hot body changed from approximately 491 decoded instructions to 297 and `VDIVPD` changed from 26 to 0. The same witness showed multi-fold speedups over 1.2.4. These development numbers are not the formal cross-host release authority; the release authority is recorded separately.

## Required gates

```text
SHARED_DEPENDENCY_EPISODE_STRUCTURAL_ADMISSION=PASS
SHARED_DEPENDENCY_EPISODE_NO_WORKLOAD_DISPATCH=PASS
SHARED_DEPENDENCY_EPISODE_RUNTIME_DISPATCH=0
SHARED_DEPENDENCY_EPISODE_SCALAR_FALLBACK=0
SHARED_DEPENDENCY_EPISODE_SUBNORMAL_RECIPROCAL_REJECT=PASS
NEWTON_JV_NATIVE_BYTE_IDENTITY_ON_1_2_5=PASS
GLOBAL_STIFFNESS_NATIVE_BYTE_IDENTITY_ON_1_2_5=PASS
WH_WHEX_SHARED_DEPENDENCY_NATIVE_BYTE_EQUIVALENCE=PASS
TOLERANT_LITERAL_RECIPROCAL_ERASURE=PASS
SHARED_DEPENDENCY_HOT_CODE_CONTRACTION=PASS
SHARED_DEPENDENCY_REACHABLE_CALL_EDGES=0
SHARED_DEPENDENCY_RUNTIME_ABI_ZMM12_15_PROTECTED=PASS
WHEELCHAIR_1_0_9_INVARIANTS_ON_1_2_5=PASS
```
