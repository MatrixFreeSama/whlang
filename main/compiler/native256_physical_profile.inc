# Wheelchair native256 physical profile.
# One architecture fact for every AVX2/YMM backend: the architectural SIMD bank
# is exactly YMM0..YMM15.  Subsystems may assign semantic roles inside this bank,
# but may not synthesize a second high-register ownership domain.
.equ N256_SIMD_REG_COUNT,16
.equ N256_SIMD_REG_LAST,15
.equ N256_HAS_HIGH_SIMD_BANK,0

# Materialized-field native256 carrier roles.  These are physical ABI facts,
# not workload choices.  The common Field lowerer consumes this table only when
# FIELD_LANES==8; native512 keeps its mature mapping unchanged.
.equ FF256_V0_REG,1
.equ FF256_V1_REG,2
.equ FF256_V2_REG,3
.equ FF256_V3_REG,12
.equ FF256_TAIL_MASK_REG,4
.equ FF256_REDUCE_REG,5
.equ FF256_I0_REG,13
.equ FF256_I1_REG,14
.equ FF256_PHASE_SCRATCH_REG,15
