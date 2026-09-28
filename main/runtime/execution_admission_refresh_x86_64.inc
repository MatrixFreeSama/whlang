# Wheelchair 1.3.102 invocation-bound execution admission.
#
# External affinity is a launch fact, not a compiler-host lifetime fact.  Read it
# once after any proved static placement has been inherited, count the admitted
# CPU set, then forget the mask.  This is not an idle-resource query: no load,
# availability, recipient, worker or CPU choice is observed.
.equ RUNTIME_AFFINITY_MASK_BYTES,128

# Optional AOT locality may narrow the invocation domain, never widen it.
# Intersect the current external affinity with the proved static-placement mask.
# Empty intersection means "keep the invocation domain" rather than escaping it.
.macro CONSTRAIN_STATIC_PLACEMENT_WITHIN_INVOCATION required, mask_bytes, mask
    cmp dword ptr [rip+\required],0
    je .csp_done\@
    mov r10d,dword ptr [rip+\mask_bytes]
    test r10d,r10d
    jz .csp_done\@
    cmp r10d,RUNTIME_AFFINITY_MASK_BYTES
    jbe .csp_size_ok\@
    mov r10d,RUNTIME_AFFINITY_MASK_BYTES
.csp_size_ok\@:
    sub rsp,RUNTIME_AFFINITY_MASK_BYTES
    mov eax,204                         # sched_getaffinity
    xor edi,edi
    mov esi,RUNTIME_AFFINITY_MASK_BYTES
    mov rdx,rsp
    syscall
    test rax,rax
    js .csp_release\@
    mov r8,rax
    cmp r8,r10
    jbe .csp_have_span\@
    mov r8,r10
.csp_have_span\@:
    lea rdx,[rip+\mask]
    xor r9d,r9d
    xor r11d,r11d                       # nonzero intersection witness
.csp_and\@:
    cmp r9,r8
    jae .csp_and_done\@
    mov al,byte ptr [rsp+r9]
    and al,byte ptr [rdx+r9]
    mov byte ptr [rsp+r9],al
    or r11b,al
    inc r9
    jmp .csp_and\@
.csp_and_done\@:
    # The syscall accepts the full local buffer; erase every byte outside the
    # proved intersection span so no stale stack bit can escape the invocation.
.csp_zero_tail\@:
    cmp r9,RUNTIME_AFFINITY_MASK_BYTES
    jae .csp_maybe_set\@
    mov byte ptr [rsp+r9],0
    inc r9
    jmp .csp_zero_tail\@
.csp_maybe_set\@:
    test r11d,r11d
    jz .csp_release\@
    mov eax,203                         # sched_setaffinity
    xor edi,edi
    mov esi,RUNTIME_AFFINITY_MASK_BYTES
    mov rdx,rsp
    syscall
.csp_release\@:
    add rsp,RUNTIME_AFFINITY_MASK_BYTES
.csp_done\@:
.endm

.macro REFRESH_EXECUTION_ADMISSION target
    sub rsp,RUNTIME_AFFINITY_MASK_BYTES
    mov eax,204                         # sched_getaffinity
    xor edi,edi                         # current process
    mov esi,RUNTIME_AFFINITY_MASK_BYTES
    mov rdx,rsp
    syscall
    test rax,rax
    js .rea_fallback\@
    mov r8,rax
    xor r9d,r9d                         # byte index
    xor ecx,ecx                         # admitted CPU count
.rea_byte\@:
    cmp r9,r8
    jae .rea_count_done\@
    movzx r10d,byte ptr [rsp+r9]
    mov r11d,8
.rea_bit\@:
    shr r10b,1
    adc ecx,0
    dec r11d
    jnz .rea_bit\@
    inc r9
    jmp .rea_byte\@
.rea_count_done\@:
    test ecx,ecx
    jnz .rea_store\@
.rea_fallback\@:
    # Failure may not resurrect compile-host width as runtime authority.
    mov ecx,1
.rea_store\@:
    mov dword ptr [rip+\target],ecx
    add rsp,RUNTIME_AFFINITY_MASK_BYTES
.endm
