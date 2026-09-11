# Wheelchair 1.2.14 Charter

## Dense Caretaker Completion

1. Rank-N semantic structure and physical loop structure are distinct; the compiler may reconstruct the cheapest proven physical nest.
2. Low-entropy coordinates, affine derivatives of those coordinates, and axis-invariant subexpressions should be represented by recurrence or hoisted state rather than recomputed values.
3. Loop-invariant code motion is determined from axis dependency sets, never workload identity.
4. Finite static inner axes may be unrolled or strip-mined when code-size and alignment proofs admit it.
5. Floating reduction reassociation is permitted only under an explicit tolerance contract; strict programs retain historical reduction order.
6. Boundary dispatch and masked tails must be erased when compile-time proofs show they cannot affect the program.
7. Long-lived Rank-N state has first claim on persistent registers; short-lived expression CSE must not crowd it out.
8. High-entropy sparse/direct addressing remains authoritative when dense caretaker transforms do not prove a benefit.
9. No global fast-math mode is introduced.
10. No JIT, runtime timing selector, benchmark-name selector, work stealing, global ready queue, or release recipient is introduced.

## Compression interpretation

1.2.13 compressed repeated coordinate decoding. 1.2.14 extends the same idea to value lifetime and loop lifetime: repeated affine products, invariant subtrees, per-packet reduction folds, impossible boundary checks, and impossible tails are execution metadata that should disappear when structure proves them redundant.
