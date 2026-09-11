#!/usr/bin/env python3
"""Workload-blind x86 physical vector-shape classification for Wheelchair 1.2.7.

This module mirrors the native compiler's CPUID-derived classification so tests
and wrappers can audit decisions without becoming the native backend authority.
"""
from __future__ import annotations
from dataclasses import dataclass, asdict

PHYS_VEC_UNKNOWN = "unknown"
PHYS_VEC_NATIVE256 = "native256"
PHYS_VEC_SPLIT512X256 = "split512x256"
PHYS_VEC_NATIVE512 = "native512"


@dataclass(frozen=True)
class PhysicalISAProfile:
    vendor: str
    family: int
    model: int
    avx2: bool
    avx512f: bool
    fma: bool
    shape: str
    semantic_vector_bits: int
    physical_datapath_bits: int
    semantic_lanes_f64: int
    physical_vector_uops_per_semantic: int
    profile: str
    profile_status: str
    runtime_selector: bool = False
    workload_dispatch: bool = False
    scalar_fallback: int = 0

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


def classify(*, vendor: str, family: int, model: int, avx2: bool, avx512f: bool, fma: bool) -> PhysicalISAProfile:
    vendor = vendor.strip()
    shape = PHYS_VEC_UNKNOWN
    profile = "generic-cross-vendor-x86_64"
    status = "KNOWN_DEBT"
    semantic_bits = 0
    physical_bits = 0
    lanes = 1
    uops = 1

    if vendor == "AuthenticAMD":
        # Family 19h spans Zen 3 and Zen 4. Architectural AVX-512 presence is
        # the workload-independent discriminator: Zen 3 is AVX2-only, while
        # Zen 4/4c expose AVX-512 over 256-bit physical datapaths.
        if family == 0x19 and avx512f:
            shape = PHYS_VEC_SPLIT512X256
            profile = "amd-zen4-split512x256"
            status = "PROVEN_SHAPE"
            semantic_bits = 512
            physical_bits = 256
            lanes = 8
            uops = 2
        elif family == 0x19 and avx2:
            shape = PHYS_VEC_NATIVE256
            profile = "amd-zen3-native256"
            status = "PROVEN_SHAPE"
            semantic_bits = 256
            physical_bits = 256
            lanes = 4
        elif family >= 0x1A and avx512f:
            # Zen 5/5c introduced full 512-bit datapaths.
            shape = PHYS_VEC_NATIVE512
            profile = "amd-zen5-native512"
            status = "PROVEN_SHAPE"
            semantic_bits = 512
            physical_bits = 512
            lanes = 8
        elif family == 0x17 and avx2:
            shape = PHYS_VEC_NATIVE256
            profile = "amd-zen1-zen2-native256"
            status = "PROVEN_SHAPE"
            semantic_bits = 256
            physical_bits = 256
            lanes = 4
    elif vendor == "GenuineIntel":
        # Intel client parts with fused-off AVX-512 remain first-class AVX2
        # targets. Xeon/server parts exposing AVX-512 use the native-512 class.
        if avx512f:
            shape = PHYS_VEC_NATIVE512
            profile = "intel-avx512-native512"
            status = "PROVEN_ISA_CLASS"
            semantic_bits = 512
            physical_bits = 512
            lanes = 8
        elif avx2:
            shape = PHYS_VEC_NATIVE256
            profile = "intel-avx2-native256"
            status = "PROVEN_ISA_CLASS"
            semantic_bits = 256
            physical_bits = 256
            lanes = 4

    # Unknown vendors remain conservative, but ISA width is still recorded.
    if shape == PHYS_VEC_UNKNOWN:
        if avx512f:
            semantic_bits = 512
            physical_bits = 0
            lanes = 8
        elif avx2:
            semantic_bits = 256
            physical_bits = 256
            lanes = 4

    return PhysicalISAProfile(
        vendor=vendor,
        family=family,
        model=model,
        avx2=bool(avx2),
        avx512f=bool(avx512f),
        fma=bool(fma),
        shape=shape,
        semantic_vector_bits=semantic_bits,
        physical_datapath_bits=physical_bits,
        semantic_lanes_f64=lanes,
        physical_vector_uops_per_semantic=uops,
        profile=profile,
        profile_status=status,
    )
