# Wheelchair 1.2.13 Charter

## Execution Representation Compression

1. Semantic resolution and physical execution representation are independent.
2. Low-entropy coordinate structure may be compressed into induction state.
3. High-entropy addressing must remain explicit when compression would add state or work.
4. Compression is admitted only from compile-time structural proofs, never from benchmark identity or runtime timing.
5. Dense Rank-N compression must preserve the declared numerical contract.
6. Register pressure is part of compressibility. A transformation that cannot be represented within the proven physical register budget is rejected.
7. Tiny-period axes whose complete lane pattern repeats within one SIMD packet must not be advanced as if they were larger loop axes.
8. No negative structural compression: sparse/direct code must remain unchanged when the dense proof does not apply.
9. No global fast-math mode is introduced.
10. Blind release remains `OWNED -> FREE`; execution compression does not create a scheduler or resource recipient.

## Physical interpretation

Dense execution is a low-entropy stream: base state + recurrence is cheaper than repeated coordinate decoding. Sparse irregular execution is closer to a high-entropy stream: explicit addressing may already be the compressed representation.
