# Newton/Jv external C control identities

The Wheelchair 1.2.1 final Newton/Jv audit used two external C controls. Both original source files have now been recovered and are published in this directory. Their SHA-256 identities match the hashes frozen by the 1.2.1 audit.

## Matched expert C

Source:

```text
Newton_Jv_expert_C_matched.c
```

Role: formula-fused expert implementation aligned to the same mathematical workload, chunking and tolerant reduction freedom.

Documented compiler configuration on the rematch host:

```text
GCC 14.2
-O3 -march=native -mtune=native -flto -ffast-math
```

Audited source SHA-256:

```text
a9a9d3e908d08983e2c74f99c391e57597e37a5a404bafa153c3c140a06979b2
```

The recovered file matches this identity exactly.

## Explicit AVX-512 C

Source:

```text
Newton_Jv_expert_C_explicit_AVX512.c
```

Role: stronger hand-written SIMD control admitted as a machine-level ceiling rather than a deliberately weak baseline.

Audited source SHA-256:

```text
05e141dff01fcdf04a0821395fe675dc4876dfce1d60115613c18252388701ea
```

The recovered file matches this identity exactly.

## Provenance rule

These files are not reconstructions. They are the original audited controls recovered after the 1.2.1 release archive was assembled, and their byte identities are independently anchored by the SHA-256 values already recorded in the release audit.

A later modification to either C source must receive a new source hash and a fresh benchmark run. Historical Wheelchair 1.2.1 timings remain attached only to the exact hashes above.

The Wheelchair source used in the audit is retained verbatim as `mature.whex`, with release-manifest SHA-256:

```text
164976d70ebbabd008b71a900e21d602efd5559f30eeb2751a2cb39b28d33dfa
```
