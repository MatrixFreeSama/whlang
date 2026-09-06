# Generic physical vector-shape classes for AOT microarchitecture mapping.
# These are physical execution properties, never workload identities.
.equ PHYS_VEC_UNKNOWN,          0
.equ PHYS_VEC_NATIVE256,        1
.equ PHYS_VEC_SPLIT512X256,     2
.equ PHYS_VEC_NATIVE512,        3

# Stable profile IDs used only for silicon audit/reporting.
.equ SILICON_PROFILE_GENERIC,              0
.equ SILICON_PROFILE_AMD_ZEN4_SPLIT512,    1
.equ SILICON_PROFILE_AMD_ZEN3_NATIVE256,   2
.equ SILICON_PROFILE_AMD_ZEN5_NATIVE512,   3
.equ SILICON_PROFILE_INTEL_NATIVE256,      4
.equ SILICON_PROFILE_INTEL_NATIVE512,      5
.equ SILICON_PROFILE_AMD_PREZEN4_NATIVE256,6
