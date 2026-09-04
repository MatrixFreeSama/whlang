# Wheelchair 1.0.3 Compiler Repair Proof

## Reproducible compiler changes

- `MAX_NODES`: 8192 -> 65536.
- `EVAL_CAP`: 65536 -> 4194304 bytes for each scalar/vector AOT arena.
- ZMM13 is an emergency-only vector temporary; the original primary register order is preserved.
- Recursive compile-time folding of typed u64 add/sub/mul/mod trees.
- Explicit `contracts.floating_point = "tolerant"` recognition.
- Native float64 `vfmadd231pd` lowering for admitted tolerant multiply-add shapes.
- Strict input is prohibited from taking that FMA contraction path.

## Differential validation

A generated differential suite compiled 96 structural programs twice: once with vector lowering enabled and once with vector lowering disabled to provide the scalar oracle.  The suite was repeated after changing the same programs to `floating_point = "tolerant"`.

- strict cases compiled: 96/96
- strict cases above 1e-12 relative difference: 0
- tolerant cases compiled: 96/96
- tolerant cases above 1e-10 relative difference: 0

The matrix-free FEM aggregate regression was also compared as scalar oracle vs AVX-512 for four independent contraction shards.  Maximum observed relative difference was approximately 1.60e-15.

## Regression preservation

The canonical strict Heat, Wave, and Sparse programs produced byte-identical generated ELF files between 1.0.2 and 1.0.3.  This is intentional: ZMM13 is borrowed only when actual vector pressure exhausts the original temporary pool.

## Rejected experiment

A generic scalar stack fallback was prototyped while investigating very wide unnormalized trees.  It was not retained because it did not pass the required semantic evidence.  The release contains no such fallback.

## Scope

This proof supports the compiler changes listed above. It does not claim that arbitrary linear expressions are automatically reduced from 72 terms to 24 terms by the 1.0.3 compiler.
