# Opaque SIMD payload transport. Width is a carrier property.
# edi=register, esi=bytes (16/32/64), edx=displacement, ecx=store,
# r8=caller-owned 16-byte encoding buffer. eax=length, zero if unsupported.
.global physical_encode_simd_rsp,physical_encode_simd_slot
physical_encode_simd_rsp:
    xor r9d,r9d
# Same physical slot authority: r9d=0 RSP, 1 R12 residency frame.
physical_encode_simd_slot:
    cmp r9d,1; ja .pesr_bad
    mov r10d,r9d; shl r10d,5
    cmp edi,31; ja .pesr_bad
    cmp ecx,1; ja .pesr_bad
    cmp esi,64; je .pesr_evex
    cmp edi,15; ja .pesr_bad
    cmp esi,16; je .pesr_vex
    cmp esi,32; jne .pesr_bad
.pesr_vex:
    test r10d,r10d; jnz .pesr_vex_long
    cmp edi,7; ja .pesr_vex_long
    mov byte ptr [r8],0xc5
    mov eax,0xf8; cmp esi,16; je 2f
    or eax,4
2:  mov [r8+1],al
    lea eax,[rcx+0x10]; mov [r8+2],al
    mov eax,edi; shl eax,3; or eax,0x84; mov [r8+3],al
    mov byte ptr [r8+4],0x24; mov [r8+5],edx
    mov eax,9; ret
.pesr_vex_long:
    mov byte ptr [r8],0xc4
    mov eax,edi; shr eax,3; xor eax,1; and eax,1; shl eax,7; or eax,0x61
    xor eax,r10d
    mov [r8+1],al
    mov eax,0x78; cmp esi,16; je 1f
    or eax,4
1:  mov [r8+2],al
    lea eax,[rcx+0x10]; mov [r8+3],al
    mov eax,edi; and eax,7; shl eax,3; or eax,0x84; mov [r8+4],al
    mov byte ptr [r8+5],0x24; mov [r8+6],edx
    mov eax,10; ret
.pesr_evex:
    mov byte ptr [r8],0x62
    mov eax,edi; shr eax,3; xor eax,1; and eax,1; shl eax,7; or eax,0x61
    mov r9d,edi; shr r9d,4; xor r9d,1; and r9d,1; shl r9d,4; or eax,r9d
    xor eax,r10d
    mov [r8+1],al; mov byte ptr [r8+2],0x7c; mov byte ptr [r8+3],0x48
    lea eax,[rcx+0x10]; mov [r8+4],al
    mov eax,edi; and eax,7; shl eax,3; or eax,0x84; mov [r8+5],al
    mov byte ptr [r8+6],0x24; mov [r8+7],edx
    mov eax,11; ret
.pesr_bad:
    xor eax,eax; ret
