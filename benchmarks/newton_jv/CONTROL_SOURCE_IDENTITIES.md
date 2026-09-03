# Newton/Jv external C control identities

The Wheelchair 1.2.1 final Newton/Jv audit used two external C controls.

## Matched expert C

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

## Explicit AVX-512 C

Role: stronger hand-written SIMD control admitted as a machine-level ceiling rather than a deliberately weak baseline.

Audited source SHA-256:

```text
05e141dff01fcdf04a0821395fe675dc4876dfce1d60115613c18252388701ea
```

## Provenance rule

The exact external C source files were not retained in the Wheelchair 1.2.1 release package. The release retained their cryptographic identities instead.

Accordingly, this repository does **not** publish a newly reconstructed C file under either historical hash. Doing so would make the benchmark easier to reproduce superficially while breaking provenance.

A future reconstruction may be added as a new control, but it must be named as a reconstruction and must receive a new source hash and a fresh benchmark run. Historical Wheelchair 1.2.1 timings must remain attached only to the two identities above.

The Wheelchair source used in the audit is retained verbatim as `mature.whex`, and its release-manifest SHA-256 is:

```text
164976d70ebbabd008b71a900e21d602efd5559f30eeb2751a2cb39b28d33dfa
```
