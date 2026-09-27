# Wheelchair 1.2.1 Newton/Jv benchmark configuration

This file records the configuration of the final Wheelchair 1.2.1 same-host Newton/Jv restoration audit.

## Host

- CPU: Intel Xeon Platinum 8370C @ 2.80 GHz
- Environment: virtualized x86-64 host
- Logical CPUs visible to the audit environment: CPUs 0-4
- Sustained cgroup CPU quota recorded on the same rematch host: 4 CPUs
- Tested executor/core counts: 1, 2, and 4
- CPU affinity: fixed for every contestant

The absolute wall times in this directory belong to this host and must not be mixed with historical Xeon 8573C results.

## Workload

Matrix-free periodic Newton Jacobian-vector product:

```text
u[i]  = 0.25 + ((17*i+3) mod 1024)/1024
v[i]  = -0.5 + ((29*i+7) mod 1024)/1024
jv[i] = (2 + 0.375*u[i]^2)*v[i] - v[i-1] - v[i+1]
```

Boundary condition: periodic.

Numerical contract:

- FP64
- Wheelchair tolerant reduction
- four logical accumulation carriers
- deterministic causal/fixed reduction topology
- chunk extent: 65,536 coordinates

Required bitwise outputs:

```text
N = 10,000,000  -> checksum_bits=0x40a1414a1c4e8000
N = 100,000,000 -> checksum_bits=0x40d591e5093fa000
```

## Measurement protocol

For every N and executor/core count:

1. pin the contestant to the intended CPU set;
2. perform three warm-up runs;
3. perform 21 measured runs for every contestant;
4. shuffle/interleave contestant order;
5. measure whole-process wall time;
6. reject a result if the required bitwise checksum is not returned.

The published result is the median of the 21 measured runs.

## Contestants

### Wheelchair 1.2.1

Source: `mature.whex`.

The WHEX human surface is compile-time only. The release audit separately proves that direct canonical input and normal WHEX compilation produce byte-identical native ELF images for 1, 2, and 4 executors.

### Matched expert C

Source: `Newton_Jv_expert_C_matched.c`.

The audit used a formula-fused expert C control aligned to the mathematical workload and reduction freedom. The adjacent rematch record documents GCC 14.2 with:

```text
-O3 -march=native -mtune=native -flto -ffast-math
```

Audited source identity:

```text
a9a9d3e908d08983e2c74f99c391e57597e37a5a404bafa153c3c140a06979b2
```

The recovered repository file matches this identity exactly.

### Explicit AVX-512 C

Source: `Newton_Jv_expert_C_explicit_AVX512.c`.

This stronger hand-written SIMD C control was admitted as a harder machine-level opponent than ordinary compiler-vectorized C.

Audited source identity:

```text
05e141dff01fcdf04a0821395fe675dc4876dfce1d60115613c18252388701ea
```

The recovered repository file matches this identity exactly.

## Wheelchair 1.2.1 machine-code change

Compared with Wheelchair 1.2.0 on the mature one-executor Newton/Jv image:

```text
VCVTTPD2QQ count:      4 -> 2
VPMULLQ count:         10 -> 6
generated RX payload:  1305 -> 1209 bytes
```

The change comes from generic Interior Periodic Composition Erasure. Proven interior periodic affine coordinates may erase redundant dynamic modulo only after range proof. Boundary regions retain exact periodic semantics.

## Claim boundary

This is one matrix-free Newton/Jv workload on one virtualized host. It is evidence for this workload and compiler transformation, not a universal programming-language ranking.

The 1.2.1 transformation is separately gated as generic structural algebra. It does not dispatch on Newton, Jacobian, heat, stencil, C, Rust, MoonBit, coefficient, or modulus names.
