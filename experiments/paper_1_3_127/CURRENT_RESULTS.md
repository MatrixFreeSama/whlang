# Wheelchair 1.3.127 — current paper evidence

This file records the current evidence set for the frozen 1.3.127 paper snapshot. It is intentionally not a best-case benchmark list. Positive results, negative controls, numerical checks, shape cliffs, and frozen-entry coverage limits are retained together.

## Frozen artifact

- Wheelchair: `1.3.127` paper snapshot
- Archive: `dist/Wheelchair-1.3.127.zip`
- SHA-256: `e4b7090a48f5751748fb0eaf6e072c0874939f5bc76a8b4f4ceb252b1847bfeb`
- No experiment below changes compiler/runtime source or introduces a publication-only route.

## 1. ValueFact / pure-scalar negative control

`scalar_v3_20261005/RESULTS.md`, x86-64-v3/native256, one pinned CPU, 15 interleaved repetitions:

| workload | Wheelchair / C time | result |
|---|---:|---|
| mass3 | 1.1272x | Wheelchair slower |
| chem6 | 1.0167x | near parity, Wheelchair slower |
| rigid7 | 1.2393x | Wheelchair slower |

This is the retained cost side of the architecture: a Wheelchair ValueFact carries more structure than a bare C scalar, so deep-causal regular arithmetic can pay representation/instruction overhead when there is little physical work to eliminate.

## 2. Structural-support positive controls and mechanism ablation

`support_v4_20261005/RESULTS.md`, fixed AVX-512 host profile:

- Localized plasticity, 8M: Wheelchair 1.3.127 `0.863687 ms`, GCC C `7.939911 ms`, **9.193x over natural C**.
- Same source on Wheelchair 1.3.126: `6.430833 ms`; the 1.3.126 -> 1.3.127 comparison is the mechanism ablation.
- Two-region Level-Set, 8M: Wheelchair `0.861022 ms`, GCC C `12.127308 ms`, **14.0848x over natural C**.
- Manual support-bounded C/Fortran implementations remain labeled ceilings, not natural baselines.
- Scaling shows 1.3.127 staying near support/startup cost while natural C and 1.3.126 localized plasticity grow with total background domain.

## 3. Strict real Field miniapps with an independent numerical reference

`field_strict_reference_20261005/RESULTS.md`, x86-64-v3/native256, one pinned CPU, 15 interleaved repetitions. The Wheelchair JSON contract is Strict and C/GFortran use strict floating-point flags. All implementations consume the same WHFLD217 bytes.

| workload | Wheelchair | GCC C | speedup/C | WC error vs f64 ref | C error vs f64 ref |
|---|---:|---:|---:|---:|---:|
| miniAMR 27-point, 256^3 | 75.458362 ms | 116.017901 ms | **1.5375x** | 1.395e-4 | 2.136e-2 |
| miniFE heat21, 256^3 | 60.756158 ms | 75.787965 ms | **1.2474x** | 9.993e-5 | 6.744e-4 |

The f64 oracle preserves each kernel's local `float` arithmetic and changes only the final reduction accumulation to `double`. It is a numerical diagnostic, not a timed competitor. The differing f32 checksums therefore are not treated as an automatic Wheelchair error; on this input the Wheelchair reductions are closer to the f64 accumulation reference.

The earlier `expansion_v1_20261005` Field table mixed tolerant Wheelchair JSON with strict C/Fortran controls and is explicitly marked exploratory/superseded.

## 4. Field size and CPU-set sweep: a retained negative result

`field_scale_multicore_20261005/RESULTS.md` and `field_shape_cliff_20261005/RESULTS.md` expose a real shape-dependent weakness.

At power-of-two 256^3, Strict Wheelchair remains faster than C on both one and four admitted CPUs:

- miniAMR-27: **1.6573x** on 1 CPU, **1.6469x** on 4 CPUs.
- miniFE heat21: **1.2641x** on 1 CPU, **1.3523x** on 4 CPUs.

But the detailed one-CPU sweep shows a strong non-power-of-two cliff. For every tested 160..248 extent, both wide-neighborhood kernels are substantially slower than C; at 192^3 Wheelchair reaches only `0.2685x` C speed on miniAMR-27 and `0.2464x` on miniFE heat21. The point is retained rather than removed from the paper evidence.

Source inspection identifies the physical split: `FRC_finalize_shape` records `g_shape_pow2` when every runtime extent/logical stride is a power of two. The AVX2 generic coordinate path then uses vector `divmod` for coordinate recovery, while the power-of-two path uses shift/mask realization. The source describes these as realizations of one semantic relation, not separate source-language backends, but the current physical cost is not smooth across them.

## 5. Address-path ablation of the shape cliff

`field_address_ablation_20261005/RESULTS.md` narrows the weakness:

- Center-only reduction at 192^3: Wheelchair is still **1.8011x faster than C**.
- Adding one periodic `k+1` neighbor at 192^3: Wheelchair remains approximately at parity, **1.0424x** over C.
- The severe cliff appears with the high-density 21/27-neighbor periodic stencils.

Thus the negative result is not "all non-power-of-two Field is slow". It is specifically the current general non-power-of-two periodic AddressFact realization under dense neighborhood access, where division-heavy coordinate recovery is not sufficiently amortized by the retained Region realization.

## 6. Frozen-entry coverage limits discovered during experiment hardening

Two retained historical benchmark families are not forced into the current native256 paper table:

- the 1.3.102 high-entropy WHEX source is accepted through its historical `whexc` route but not through `topologyc-native256`; the `whexc` product was verified to use AVX-512, so comparing it against x86-64-v3 controls would be invalid;
- the retained 1.3.124 `d23/d40.whex` periodic CoordinateFact sources are likewise rejected by the frozen native256 entry and are reserved for a separate native `whexc` / ISA-matched table.

The compiler is not modified merely to make those sources fit the publication harness.

## Publication status

The current evidence already covers:

1. an explicit architectural cost/negative scalar control;
2. a strong structural-support advantage with an old-version mechanism ablation;
3. two established simulation miniapps under matched Strict contracts;
4. independent numerical-reference checks;
5. size and 1-vs-4-CPU behavior;
6. a newly exposed, reproducible non-power-of-two dense-neighborhood weakness and a minimal ablation that localizes it.

Hosted-runner numbers remain pilot evidence. Final submission tables should be repeated on one fixed documented machine without changing the frozen 1.3.127 compiler artifact.
