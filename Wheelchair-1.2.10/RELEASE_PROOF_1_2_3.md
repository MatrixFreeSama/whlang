# Wheelchair 1.2.3 Release Proof Contract

A formal `Wheelchair-1.2.3.zip` may be published only after a real AVX-512F host
runs the monolithic 1.2.3 authority and reports:

```text
WHEELCHAIR_SPARSE_CAUSAL_EXPANSION_1_2_3=PASS
WHEELCHAIR_1_2_3_COMPLETE=PASS
```

The same run must include the inherited Rank-N and technical-peak witnesses from
1.2.2/1.2.1.

The release archive must then satisfy all of the following:

1. `VERSION` is exactly `1.2.3`.
2. The authority log is embedded as `RELEASE_GATES_1_2_3.txt`.
3. No `.exe`, `.dll`, `.so`, `.o`, `.a`, `.pdb`, Python cache, ELF, or PE binary
   is present in the source release tree.
4. `SHA256SUMS` is generated over every release file except itself.
5. The ZIP is re-extracted into a fresh directory.
6. `sha256sum -c SHA256SUMS` passes in the re-extracted tree.
7. The re-extracted authority file still contains both required 1.2.3 gates.
8. An outer SHA-256 sidecar is generated for `Wheelchair-1.2.3.zip`.
9. Only after those checks may the immutable ZIP and sidecar be written to
   `main/dist`.

## Claim discipline

The 1.2.3 release may claim a mature generic compile-time Sparse Causal Expansion
and Causal Separator Signature algebra, WH/WHEX semantic integration, bounded
amplification gates, explicit dense/unproved rejection, and zero runtime metadata
for the current native domain.

It may not claim a finished arbitrary runtime sparse-matrix importer or a fully
native generic Schur solver.
