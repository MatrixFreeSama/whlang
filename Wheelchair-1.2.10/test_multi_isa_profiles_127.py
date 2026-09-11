#!/usr/bin/env python3
from surface.physical_isa_profile import classify

cases = [
    (dict(vendor="GenuineIntel", family=6, model=151, avx2=True, avx512f=False, fma=True), "native256", "intel-avx2-native256"),
    (dict(vendor="GenuineIntel", family=6, model=143, avx2=True, avx512f=True, fma=True), "native512", "intel-avx512-native512"),
    (dict(vendor="AuthenticAMD", family=0x19, model=1, avx2=True, avx512f=False, fma=True), "native256", "amd-zen3-native256"),
    (dict(vendor="AuthenticAMD", family=0x19, model=0x11, avx2=True, avx512f=True, fma=True), "split512x256", "amd-zen4-split512x256"),
    (dict(vendor="AuthenticAMD", family=0x1A, model=2, avx2=True, avx512f=True, fma=True), "native512", "amd-zen5-native512"),
    (dict(vendor="AuthenticAMD", family=0x17, model=0x31, avx2=True, avx512f=False, fma=True), "native256", "amd-zen1-zen2-native256"),
    (dict(vendor="UnknownVendor", family=7, model=1, avx2=True, avx512f=True, fma=True), "unknown", "generic-cross-vendor-x86_64"),
]
for kwargs, shape, profile in cases:
    p = classify(**kwargs)
    assert p.shape == shape, (kwargs, p)
    assert p.profile == profile, (kwargs, p)
    assert p.runtime_selector is False
    assert p.workload_dispatch is False
    assert p.scalar_fallback == 0

z3 = classify(vendor="AuthenticAMD", family=0x19, model=1, avx2=True, avx512f=False, fma=True)
z4 = classify(vendor="AuthenticAMD", family=0x19, model=0x11, avx2=True, avx512f=True, fma=True)
z5 = classify(vendor="AuthenticAMD", family=0x1A, model=2, avx2=True, avx512f=True, fma=True)
assert (z3.semantic_vector_bits, z3.physical_datapath_bits, z3.physical_vector_uops_per_semantic) == (256, 256, 1)
assert (z4.semantic_vector_bits, z4.physical_datapath_bits, z4.physical_vector_uops_per_semantic) == (512, 256, 2)
assert (z5.semantic_vector_bits, z5.physical_datapath_bits, z5.physical_vector_uops_per_semantic) == (512, 512, 1)

print("MULTI_ISA_SYNTHETIC_PROFILE_MATRIX=PASS")
print("INTEL_AVX2_NATIVE256=PASS")
print("INTEL_AVX512_NATIVE512=PASS")
print("AMD_ZEN3_NATIVE256=PASS")
print("AMD_ZEN4_SPLIT512X256=PASS")
print("AMD_ZEN5_NATIVE512=PASS")
print("MULTI_ISA_WORKLOAD_DISPATCH=0")
print("MULTI_ISA_RUNTIME_SELECTOR=0")
