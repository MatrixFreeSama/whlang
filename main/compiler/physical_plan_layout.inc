# One compiler-only residency record ABI. Architectural cache-line alignment.
.ifndef PPR_SIZE
.equ PPR_SIZE,64
.equ PPR_INVARIANT,48
.endif
