# One IEEE unordered-aware scalar PredicateFact projection. Only AL/AH change.
# UCOMI gives ZF=PF=CF=1 for unordered; NE is true, every other relation false.
.macro PHYSICAL_FP_SETCC cc
    .byte 0x0f,\cc,0xc0
.if \cc == 0x95
    setp ah
    or al,ah
.elseif \cc == 0x94 || \cc == 0x92 || \cc == 0x96
    setnp ah
    and al,ah
.endif
.endm
