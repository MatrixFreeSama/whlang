# Physical element geometry is an AOT parameter; coordinate facts remain u31.
.ifndef FIELD_ELEMENT_BITS
.equ FIELD_ELEMENT_BITS,32
.endif
.equ FIELD_ELEMENT_BYTES,FIELD_ELEMENT_BITS/8
.equ FIELD_ELEMENT_SHIFT,FIELD_ELEMENT_BYTES/4+1
.equ FIELD_ELEMENT_TYPE,FIELD_ELEMENT_BYTES/4
.equ FIELD_PACKET_LANES,FIELD_PACKET_BYTES/FIELD_ELEMENT_BYTES
.equ FIELD_TRAFFIC_ELEMENTS,64/FIELD_ELEMENT_BYTES
.macro FRC_MOV_SCALAR dst,src
.if FIELD_ELEMENT_BITS == 64
    movsd \dst,\src
.else
    movss \dst,\src
.endif
.endm
.macro FRC_ADD_SCALAR dst,src
.if FIELD_ELEMENT_BITS == 64
    addsd \dst,\src
.else
    addss \dst,\src
.endif
.endm
.macro FRC_STORE_NT
.if FIELD_PACKET_BYTES == 64
.if FIELD_ELEMENT_BITS == 64
    vmovntpd zmmword ptr [rax],zmm0
.else
    vmovntps zmmword ptr [rax],zmm0
.endif
.else
.if FIELD_ELEMENT_BITS == 64
    vmovntpd ymmword ptr [rax],ymm0
.else
    vmovntps ymmword ptr [rax],ymm0
.endif
.endif
.endm
.macro FRC_STORE_MASK
.if FIELD_PACKET_BYTES == 64
.if FIELD_ELEMENT_BITS == 64
    vmovupd zmmword ptr [rax]{k1},zmm0
.else
    vmovups zmmword ptr [rax]{k1},zmm0
.endif
.else
.if FIELD_ELEMENT_BITS == 64
    vmaskmovpd ymmword ptr [rax],ymm4,ymm0
.else
    vmaskmovps ymmword ptr [rax],ymm4,ymm0
.endif
.endif
.endm
