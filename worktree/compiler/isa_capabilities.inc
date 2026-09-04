# Generic ISA capability algebra. These bits describe semantic/native realization
# abilities, never workload names. Multiple instruction sets may contribute the
# same capability; a backend may also synthesize a capability from weaker ones.
.equ ISA_CAP_VEC256_FP,            (1 << 0)
.equ ISA_CAP_VEC256_INT,           (1 << 1)
.equ ISA_CAP_VEC512,               (1 << 2)
.equ ISA_CAP_PREDICATE,            (1 << 3)
.equ ISA_CAP_MASKED_TAIL,          (1 << 4)
.equ ISA_CAP_SCALAR_BROADCAST,     (1 << 5)
.equ ISA_CAP_EMBED_BROADCAST,      (1 << 6)
.equ ISA_CAP_WIDE_REGFILE,         (1 << 7)
.equ ISA_CAP_FMA,                  (1 << 8)
.equ ISA_CAP_GATHER,               (1 << 9)
.equ ISA_CAP_I64_MIN,              (1 << 10)
.equ ISA_CAP_I64_MUL_NATIVE,       (1 << 11)
.equ ISA_CAP_I64_MUL_SYNTH,        (1 << 12)
.equ ISA_CAP_I64_FP_CONVERT,       (1 << 13)
.equ ISA_CAP_BYTE_VECTOR,          (1 << 14)
.equ ISA_CAP_VECTOR_LENGTH,        (1 << 15)
.equ ISA_CAP_MASKED_MEMORY,        (1 << 16)
.equ ISA_CAP_BIT_EXTRACT_DEPOSIT,  (1 << 17)
.equ ISA_CAP_POPCOUNT,             (1 << 18)
.equ ISA_CAP_LZCNT,                (1 << 19)
.equ ISA_CAP_CROSS_VECTOR_STATE,   (1 << 20)
.equ ISA_CAP_REDUCTION_TREE,       (1 << 21)
.equ ISA_CAP_MASK_TO_I64_NATIVE,     (1 << 22)
.equ ISA_CAP_MASK_TO_I64_SYNTH,      (1 << 23)
.equ ISA_CAP_I64_FP_CONVERT_SYNTH,      (1 << 24)
.equ ISA_CAP_NONNEG_F64_U64_TRUNC_SYNTH,   (1 << 25)

# Minimum physical abilities required by the current 8-lane tensor realizer.
# DQ and VL are intentionally absent: DQ-only operations are demanded lazily,
# and VL is not semantically required by a 512-bit episode.
.equ ISA_CAP_TENSOR512_BASE, (ISA_CAP_VEC512 | ISA_CAP_PREDICATE | ISA_CAP_MASKED_TAIL | ISA_CAP_SCALAR_BROADCAST | ISA_CAP_WIDE_REGFILE | ISA_CAP_CROSS_VECTOR_STATE | ISA_CAP_REDUCTION_TREE)
