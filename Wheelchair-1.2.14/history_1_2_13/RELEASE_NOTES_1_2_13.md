# Wheelchair 1.2.13 Release Notes

## Theme

Execution Representation Compression: remove repeated low-entropy Rank-N coordinate decoding without damaging high-entropy sparse kernels.

## Added

- native512 dense Rank-N shift/mask coordinate recognizer;
- persistent coordinate induction carriers;
- coalesced mixed-radix axis carry equivalent to reconstructed nested-loop induction;
- immediate strength reduction of static coordinate progression;
- register-pressure and tiny-period fallbacks;
- hard sparse byte-identity regression gate;
- dense carry-boundary regression at 64/127/128/129/8192 batches.

## Preserved

- strict/no-global-fast-math numerical policy;
- Python-free production path;
- blind release semantics;
- native resource-profile selection;
- causal-mesh width preservation;
- Rank-6 numerical authority;
- native256 correctness and direct realization when compression would consume unavailable persistent registers.

## Measured development result

Dense 128x128 Rank-3 bilinear contraction, 9 points (2048/4096/8192 batches x q1/q2/q4), interleaved 1.2.12 vs 1.2.13:

- geometric mean speedup: approximately 1.230x;
- irregular sparse q1/q2/q4 generated executables: byte-identical to 1.2.12.

These measurements are diagnostic and host-specific, not universal performance promises.
