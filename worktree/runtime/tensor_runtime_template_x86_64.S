.intel_syntax noprefix
# Wheelchair 1.0.9 native topology runtime.
# Runtime Erasure: no fixed evaluator arenas, no global partial arrays, no fixed
# child-stack BSS. Serial-Spine Erasure: executor creation/join/reduction form a
# causal binary tree; no root O(P) spawn/wait/reduce sweep exists.

.equ SYS_write, 1
.equ SYS_mmap, 9
.equ SYS_munmap, 11
.equ SYS_exit, 60
.equ SYS_exit_group, 231
.equ SYS_clone, 56
.equ SYS_wait4, 61
.equ SYS_sched_setaffinity, 203
.equ SYS_sched_getaffinity, 204
.equ CLONE_VM_FILES_FS_SIGCHLD, 0x711
.equ PROT_RW, 3
.equ MAP_PRIVATE_ANON_STACK, 0x20022
.equ CHILD_STACK_SIZE, 16384
.equ CHUNK_SHIFT, 16
.equ CHUNK_SIZE, 65536
.equ MAX_CHUNKS, 2048
.equ MAX_EXECUTORS, 4
.equ REDUCE_LEVELS, 12

.section .text
.global _start
_start:
    mov r15, rsp
    mov rax, [r15]
    cmp rax, 2
    jne .bad_args
    mov rdi, [r15+16]
    call parse_u64
    test edx, edx
    jnz .bad_args
    cmp rax, qword ptr [rip+n_min_patch]
    jb .bad_args
    cmp rax, qword ptr [rip+n_max_patch]
    ja .bad_args
    mov [rip+g_n], rax
    add rax, CHUNK_SIZE-1
    shr rax, CHUNK_SHIFT
    cmp rax, MAX_CHUNKS
    ja .bad_args
    mov [rip+g_chunks], rax

    mov eax, dword ptr [rip+executor_count_patch]
    test eax,eax
    jz .bad_args
    cmp eax,MAX_EXECUTORS
    ja .bad_args
    mov [rip+g_exec], eax

    # The complete executor interval is a causal tree.  A node may only wait for
    # the child subtree whose value is a true data dependency of that node.
    xor edi,edi
    mov esi,eax
    call run_tree
    movq rax,xmm0
    call print_checksum
    xor edi,edi
    mov eax,SYS_exit_group
    syscall
    hlt

.bad_args:
    mov edi,2
    mov eax,SYS_exit_group
    syscall
    hlt

# run_tree(edi=executor_lo, esi=executor_hi) -> xmm0
# Every internal node spawns exactly one independent right subtree while this
# executor immediately descends into the left subtree.  This turns root O(P)
# spawn/join/reduction sweeps into an O(log P) dependency-depth fabric.
run_tree:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,32
    mov r12d,edi
    mov r13d,esi
    mov eax,r13d
    sub eax,r12d
    cmp eax,1
    jne .rt_internal
    mov edi,r12d
    call worker
    jmp .rt_return

.rt_internal:
    mov eax,r12d
    add eax,r13d
    shr eax,1
    mov r14d,eax                    # midpoint

    # Allocate a child stack only for an actually reachable causal subtree.
    mov eax,SYS_mmap
    xor edi,edi
    mov esi,CHILD_STACK_SIZE
    mov edx,PROT_RW
    mov r10d,MAP_PRIVATE_ANON_STACK
    mov r8,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .bad_args
    mov [rsp+8],rax                 # child-stack base

    # [rsp+0] is the one-qword return edge from the right subtree.
    pxor xmm0,xmm0
    movsd qword ptr [rsp],xmm0
    mov r15,rsp                     # shared causal-return edge address
    mov ebx,r14d                    # child lo
    lea rsi,[rax+CHILD_STACK_SIZE-16]

    mov eax,SYS_clone
    mov edi,CLONE_VM_FILES_FS_SIGCHLD
    xor edx,edx
    xor r10d,r10d
    xor r8d,r8d
    syscall
    test rax,rax
    js .bad_args
    jz .rt_child
    mov [rsp+16],rax                # direct child pid

    # Parent immediately computes the independent left subtree.
    mov edi,r12d
    mov esi,r14d
    call run_tree
    movsd qword ptr [rsp+24],xmm0

    # Join exactly the child carrying the right dependency.  There is no root
    # wait-all loop and no unrelated executor is serialized by this edge.
    mov eax,SYS_wait4
    mov rdi,[rsp+16]
    xor esi,esi
    xor edx,edx
    xor r10d,r10d
    syscall
    test rax,rax
    js .bad_args

    # Distributed fan-in-two reduction at the same causal tree node.
    movsd xmm0,qword ptr [rsp+24]
    addsd xmm0,qword ptr [rsp]

    # The child is dead; erase its runtime storage immediately.
    movsd qword ptr [rsp+24],xmm0
    mov eax,SYS_munmap
    mov rdi,[rsp+8]
    mov esi,CHILD_STACK_SIZE
    syscall
    movsd xmm0,qword ptr [rsp+24]
    jmp .rt_return

.rt_child:
    # New stack has no caller frame.  Build a normal call frame locally, publish
    # one scalar result to the unique parent edge, then terminate this process.
    mov edi,ebx
    mov esi,r13d
    call run_tree
    movsd qword ptr [r15],xmm0
    xor edi,edi
    mov eax,SYS_exit
    syscall
    hlt

.rt_return:
    add rsp,32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# worker(edi=id) -> xmm0
# Chunk partials are consumed by a stack-local binary-carry frontier.  Twelve
# levels are sufficient for the proven MAX_CHUNKS=2048 bound, so the frontier
# occupies exactly 96 bytes.  No O(chunks) global partial array or per-executor
# summary array exists.
worker:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,96
    mov ebx,edi
    call pin_cpu

    cmp dword ptr [rip+vector_width_patch],8
    jne .w_no_vec_init
    call eval_vec_init
.w_no_vec_init:

    mov r12,[rip+g_chunks]
    mov eax,ebx
    imul rax,r12
    xor edx,edx
    mov ecx,dword ptr [rip+g_exec]
    div rcx
    mov r13,rax                     # begin chunk
    lea eax,[rbx+1]
    imul rax,r12
    xor edx,edx
    div rcx
    mov r14,rax                     # end chunk
    xor r15d,r15d                   # occupied reduction levels

.w_chunk_loop:
    cmp r13,r14
    jae .w_reduce_finish
    mov rdi,[rip+g_n]
    mov rsi,r13
    call eval_chunk                 # xmm0 = new rightmost leaf

    xor ecx,ecx
.w_carry:
    bt r15d,ecx
    jnc .w_carry_store
    movsd xmm1,qword ptr [rsp+rcx*8]
    addsd xmm1,xmm0                 # older left block + newer right block
    movapd xmm0,xmm1
    btr r15d,ecx
    inc ecx
    cmp ecx,REDUCE_LEVELS
    jb .w_carry
    jmp .bad_args
.w_carry_store:
    movsd qword ptr [rsp+rcx*8],xmm0
    bts r15d,ecx
    inc r13
    jmp .w_chunk_loop

.w_reduce_finish:
    # Remaining frontier blocks are ordered from latest/smallest at low levels
    # to earliest/largest at high levels.  Fold low->high as left+right, exactly
    # reproducing the left-to-right pairwise reduction tree for any leaf count.
    xor ecx,ecx
    xor edx,edx                     # have accumulator
    pxor xmm0,xmm0
.w_finish_levels:
    cmp ecx,REDUCE_LEVELS
    jae .w_finish_done
    bt r15d,ecx
    jnc .w_finish_next
    test edx,edx
    jnz .w_finish_merge
    movsd xmm0,qword ptr [rsp+rcx*8]
    mov edx,1
    jmp .w_finish_next
.w_finish_merge:
    movsd xmm1,qword ptr [rsp+rcx*8]
    addsd xmm1,xmm0
    movapd xmm0,xmm1
.w_finish_next:
    inc ecx
    jmp .w_finish_levels

.w_finish_done:
    cmp dword ptr [rip+vector_width_patch],8
    jne .w_no_vec_exit
    vzeroupper
.w_no_vec_exit:
    add rsp,96
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Best-effort affinity using only caller-local stack storage.  No shared
# pinmask/allowedmask BSS exists and concurrent workers cannot race on masks.
pin_cpu:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    sub rsp,256

    lea rdi,[rsp]
    xor eax,eax
    mov ecx,16
    rep stosq
    mov eax,SYS_sched_getaffinity
    xor edi,edi
    mov esi,128
    lea rdx,[rsp]
    syscall
    test rax,rax
    js .pin_done

    mov r8d,ebx
    xor r9d,r9d
.pin_find_allowed:
    cmp r9d,1024
    jae .pin_done
    mov eax,r9d
    mov ecx,eax
    and ecx,63
    shr eax,6
    bt qword ptr [rsp+rax*8],rcx
    jnc .pin_next_cpu
    test r8d,r8d
    jz .pin_found_cpu
    dec r8d
.pin_next_cpu:
    inc r9d
    jmp .pin_find_allowed

.pin_found_cpu:
    lea rdi,[rsp+128]
    xor eax,eax
    mov ecx,16
    rep stosq
    mov eax,r9d
    mov ecx,eax
    and ecx,63
    shr eax,6
    lea rdx,[rsp+128]
    bts qword ptr [rdx+rax*8],rcx
    mov eax,SYS_sched_setaffinity
    xor edi,edi
    mov esi,128
    syscall
.pin_done:
    add rsp,256
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

# eval_chunk(rdi=n, rsi=token) -> xmm0
#
# True-parallel fused episode ABI: runtime enters the generated AVX-512 kernel
# exactly once per chunk.  The generated kernel owns every eight-lane step, the
# masked tail, cross-vector axis recurrence and the local four-carrier reduction.
# No per-vector call boundary and no scalar boundary/tail path exist.
eval_chunk:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,64
    mov r12,rdi                    # n
    mov r13,rsi
    shl r13,CHUNK_SHIFT            # start
    lea r14,[r13+CHUNK_SIZE]
    cmp r14,r12
    cmova r14,r12                  # end
    cmp dword ptr [rip+vector_width_patch],8
    je .ec_fused

    # Independent tensor semantics may not be serialized by the backend.
    mov eax,SYS_exit
    mov edi,125
    syscall
    ud2

.ec_fused:
    # Dynamic exact-mod invariants are episode constants.  Build them once here
    # and keep ZMM14/ZMM15 resident for the complete generated chunk loop.
    vxorpd xmm14,xmm14,xmm14
    vcvtsi2sd xmm14,xmm14,r12
    mov rax,0x3ff0000000000000
    vmovq xmm15,rax
    vdivsd xmm15,xmm15,xmm14
    vbroadcastsd zmm14,xmm14
    vbroadcastsd zmm15,xmm15

    mov rdi,r12
    mov rsi,r13
    mov rdx,r14
    call eval_vec4                 # one call for the entire chunk episode

    add rsp,64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Direct AOT jump stubs. topologyc patches each rel32 displacement to the exact
# code appended in the generated RX segment.  No pointer lookup or interpreter.
.p2align 4
.global eval_slot
eval_slot:
    .byte 0xE9
.global eval_slot_disp_patch
eval_slot_disp_patch: .long 0
.global eval_slot_end
eval_slot_end:

.p2align 4
.global eval_vec4
eval_vec4:
    .byte 0xE9
.global eval_vec4_disp_patch
eval_vec4_disp_patch: .long 0
.global eval_vec4_end
eval_vec4_end:

.p2align 4
.global eval_vec_init
eval_vec_init:
    .byte 0xE9
.global eval_vec_init_disp_patch
eval_vec_init_disp_patch: .long 0
.global eval_vec_init_end
eval_vec_init_end:

parse_u64:
    xor eax,eax
    xor edx,edx
    xor ecx,ecx
.pu_loop:
    movzx r8d,byte ptr [rdi]
    test r8b,r8b
    jz .pu_done
    cmp r8b,'0'
    jb .pu_bad
    cmp r8b,'9'
    ja .pu_bad
    sub r8d,'0'
    imul rax,rax,10
    add rax,r8
    inc rdi
    inc ecx
    jmp .pu_loop
.pu_done:
    test ecx,ecx
    jz .pu_bad
    xor edx,edx
    ret
.pu_bad:
    mov edx,1
    ret

# rax=bits, writes checksum line
print_checksum:
    lea rdi,[rip+checksum_line+16]
    mov ecx,16
.hex_loop:
    mov rdx,rax
    shr rdx,60
    and edx,15
    cmp edx,9
    jbe .digit
    add edx,'a'-10
    jmp .store
.digit:
    add edx,'0'
.store:
    mov byte ptr [rdi],dl
    inc rdi
    shl rax,4
    dec ecx
    jnz .hex_loop
    mov eax,SYS_write
    mov edi,1
    lea rsi,[rip+checksum_line]
    mov edx,33
    syscall
    ret

.section .data
.p2align 3
.global executor_count_patch
executor_count_patch: .long 1
.global vector_width_patch
vector_width_patch: .long 1
.global reduction_carriers_patch
reduction_carriers_patch: .long 4
.global unroll_count_patch
unroll_count_patch: .long 1
.global communication_elimination_patch
communication_elimination_patch: .long 0
.global n_min_patch
n_min_patch: .quad 4
.global n_max_patch
n_max_patch: .quad 100000000
checksum_line: .ascii "checksum_bits=0x0000000000000000\n"

.section .bss
.p2align 3
g_n: .skip 8
g_chunks: .skip 8
g_exec: .skip 4
