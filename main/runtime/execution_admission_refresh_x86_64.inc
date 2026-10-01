# Wheelchair invocation-bound execution admission.
#
# External affinity is a launch fact, not a compiler-host lifetime fact. The
# kernel-owned cpuset width is discovered by retrying sched_getaffinity on
# EINVAL; 128 bytes is only the first stack probe, never a machine ceiling.
.equ RUNTIME_AFFINITY_SEED_BYTES,128
.equ ERRNO_EINVAL,22

# Optional AOT locality may narrow the invocation domain, never widen it.
# Intersect the current external affinity with the proved static-placement mask.
# Empty intersection means "keep the invocation domain" rather than escaping it.
.macro CONSTRAIN_STATIC_PLACEMENT_WITHIN_INVOCATION required, mask_bytes, mask
    cmp dword ptr [rip+\required],0
    je .csp_done\@
    mov r8d,dword ptr [rip+\mask_bytes]     # materialized placement-mask bytes
    test r8d,r8d
    jz .csp_done\@
    mov r10,r8
    mov eax,RUNTIME_AFFINITY_SEED_BYTES
    cmp r10,rax
    cmovb r10,rax
.csp_probe\@:
    sub rsp,r10
    mov eax,204                             # sched_getaffinity
    xor edi,edi
    mov rsi,r10
    mov rdx,rsp
    syscall
    test rax,rax
    jns .csp_have_affinity\@
    cmp eax,-ERRNO_EINVAL
    jne .csp_release\@
    add rsp,r10
    shl r10,1
    jc .csp_done\@
    jmp .csp_probe\@
.csp_have_affinity\@:
    mov r9,rax
    cmp r9,r8
    cmova r9,r8
    lea rdx,[rip+\mask]
    xor ecx,ecx
    xor r11d,r11d                           # nonzero intersection witness
.csp_and\@:
    cmp rcx,r9
    jae .csp_and_done\@
    mov al,byte ptr [rsp+rcx]
    and al,byte ptr [rdx+rcx]
    mov byte ptr [rsp+rcx],al
    or r11b,al
    inc rcx
    jmp .csp_and\@
.csp_and_done\@:
    # sched_setaffinity receives the discovered kernel width. Erase every byte
    # outside the proved placement span so no stale bit can escape invocation.
.csp_zero_tail\@:
    cmp rcx,r10
    jae .csp_maybe_set\@
    mov byte ptr [rsp+rcx],0
    inc rcx
    jmp .csp_zero_tail\@
.csp_maybe_set\@:
    test r11d,r11d
    jz .csp_release\@
    mov eax,203                             # sched_setaffinity
    xor edi,edi
    mov rsi,r10
    mov rdx,rsp
    syscall
.csp_release\@:
    add rsp,r10
.csp_done\@:
.endm

.macro REFRESH_EXECUTION_ADMISSION target
    mov r10d,RUNTIME_AFFINITY_SEED_BYTES
.rea_probe\@:
    sub rsp,r10
    mov eax,204                             # sched_getaffinity
    xor edi,edi                             # current process
    mov rsi,r10
    mov rdx,rsp
    syscall
    test rax,rax
    jns .rea_have_affinity\@
    cmp eax,-ERRNO_EINVAL
    jne .rea_fallback_release\@
    add rsp,r10
    shl r10,1
    jc .rea_fallback_noalloc\@
    jmp .rea_probe\@
.rea_have_affinity\@:
    mov r8,rax
    xor r9d,r9d                             # byte index
    xor ecx,ecx                             # admitted CPU count
.rea_byte\@:
    cmp r9,r8
    jae .rea_count_done\@
    movzx eax,byte ptr [rsp+r9]
    mov edx,8
.rea_bit\@:
    shr al,1
    adc ecx,0
    dec edx
    jnz .rea_bit\@
    inc r9
    jmp .rea_byte\@
.rea_count_done\@:
    test ecx,ecx
    jnz .rea_store_release\@
.rea_fallback_release\@:
    mov ecx,1
.rea_store_release\@:
    mov dword ptr [rip+\target],ecx
    add rsp,r10
    jmp .rea_done\@
.rea_fallback_noalloc\@:
    mov dword ptr [rip+\target],1
.rea_done\@:
.endm
