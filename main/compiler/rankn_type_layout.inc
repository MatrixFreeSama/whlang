# Immutable AOT type geometry shared by compiler and generated runtime.
# There is one current trailer layout; no old-layout decoder exists.
.equ RPF_FACT_BYTES,96
.equ RPF_FACT_PREC,0
.equ RPF_FACT_PACKED,8
.equ RPF_FACT_SPAN,16
.equ RPF_FACT_LIMBS,24
.equ RPF_FACT_FOURIER,32

.equ RPF_FACT_TW_FORWARD,64
.equ RPF_FACT_TW_INVERSE,72
.equ RPF_FACT_TW_BYTES,80
.equ RPF_FACT_TW_REQUIRED,88
