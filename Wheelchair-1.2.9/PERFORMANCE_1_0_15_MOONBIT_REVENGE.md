# Wheelchair 1.0.15 MoonBit Revenge Performance Audit

## Claim boundary first

The current execution image does **not** contain a usable official MoonBit native toolchain. Therefore this report does not publish or invent an actual MoonBit-native timing.

Instead, it intentionally gives the opponent increasingly aggressive native proxies for the same mathematical kernel:

1. an expert-fused C implementation compiled with `-O2 -fwrapv -fno-strict-aliasing`;
2. the same implementation compiled with `-O3 -march=native -mtune=native -fwrapv -fno-strict-aliasing`;
3. a stronger hand-written AVX-512 C/FFI ceiling using explicit ZMM intrinsics and four vector accumulators.

The third contestant is deliberately stronger than a normal safe-language comparison. It represents the kind of native/FFI escape hatch an expert could use to chase the hardware directly. It is not pure MoonBit and should not be presented as an actual MoonBit-native result.

## Host and workload

- Host observed: Intel Xeon Platinum 8272CL @ 2.60 GHz, five visible logical CPUs.
- CPU affinity: contestant pinned to CPU0.
- Workload: the existing periodic heat/diffusion WHEX topology.
- Extent: `N = 16,777,216`.
- Arithmetic: FP64 tolerant reduction.
- Parallelism: one Wheelchair executor / one host thread for controls.
- Required output: `checksum_bits=0x4167fc0000000000`.
- Method: six warmups followed by 51 shuffled/interleaved measurements per contestant.

All four final contestants returned the required checksum.

## Final four-way result

| contestant | median | min | mean | IQR (p25..p75) | time / WHEX |
|---|---:|---:|---:|---:|---:|
| **WHEX 1.0.15** | **18.798046 ms** | 16.887877 ms | 19.260570 ms | 18.078762..19.978345 | 1.000x |
| expert native proxy, `-O2` | 53.884020 ms | 49.275591 ms | 54.516965 ms | 52.352585..55.866580 | 2.866x |
| aggressive native proxy, `-O3 -march=native` | 52.295844 ms | 48.967861 ms | 53.288284 ms | 50.775499..54.192116 | 2.782x |
| **hand-written AVX-512 C/FFI ceiling** | **23.561594 ms** | 22.169390 ms | 24.209991 ms | 23.078501..24.332195 | **1.253x** |

Against the strongest hand-written AVX-512 ceiling, Wheelchair uses about:

```text
20.22% less median wall time
```

because `1 - 18.798046 / 23.561594 ~= 0.2022`.

## 1.0.14 -> 1.0.15 same-host A/B

A separate 51-run interleaved set including the previous release measured:

```text
Wheelchair 1.0.14 median:       29.508096 ms
Wheelchair 1.0.15 median:       18.470061 ms
hand-written AVX-512 ceiling:   23.881419 ms
1.0.14 -> 1.0.15 speedup:       ~1.598x
```

This run is reported separately from the final four-way table because its sample population differs.

## Why 1.0.15 crosses the ceiling

Disassembly of 1.0.14 showed that global boundary `select` expressions obscured affine relations for neighbor coordinates. The hot vector loop therefore repeated boundary compares/mask materialization and repeated coefficient multiplication even when almost every vector block lay strictly inside the domain.

1.0.15 does not special-case heat. It creates generic mutually exclusive vector regions:

```text
first/final/tail vector block -> exact boundary vector body
proven interior vector block  -> predicate-erased interior vector body
```

In the measured generated interior region, the release gate observes zero `vpcmpeqq`, zero `vpmovm2q`, and zero repeated `vpmullq` for the proven affine relation. The boundary region retains the required predicate machinery. Both remain vector code.

The hand-written AVX-512 ceiling instead handles global boundaries and leftovers with scalar code. Wheelchair 1.0.15 crosses that timing while preserving its no-scalar-boundary contract.

## Memory and artifact-size boundary

This host's `/usr/bin/time` reports all four small native programs at the same 512 KiB maximum-RSS floor, so the current native-proxy run cannot support a defensible RSS ranking.

Generated artifact sizes in this run were:

```text
WHEX 1.0.15 static direct ELF:          9,153 bytes
expert C proxy -O2 executable:         16,032 bytes
expert C proxy -O3 native executable:  16,032 bytes
AVX-512 C/FFI ceiling executable:      16,096 bytes
```

The C controls are normal dynamically linked host executables, while the WHEX output is a direct static ELF, so raw file size is descriptive rather than a universal deployment comparison.

## Safety boundary

This performance result is not a universal language-safety ranking.

- Pure MoonBit retains stronger general-purpose automatic memory-safety/runtime ownership guarantees than the current Wheelchair language.
- Wheelchair 1.0.15 has strong structural, range, topology, parallelism, and differential proof gates but does not yet claim complete general-language memory safety.
- The fastest opponent here is explicitly a hand-written C/AVX-512 FFI ceiling. Using that style moves the hot kernel outside the pure-language safety envelope and places memory/alignment/ISA obligations on the native boundary.
- Wheelchair beats that ceiling here without introducing scalar tensor boundaries or tails.

## Defensible conclusion

For this exact one-core periodic heat kernel on this host, the current Wheelchair 1.0.15 generated code is faster than all three deliberately favorable native C proxies, including a hand-written AVX-512 FFI ceiling. This is strong machine-code evidence for this kernel, not a claim that an unmeasured official MoonBit-native build has been universally defeated.
