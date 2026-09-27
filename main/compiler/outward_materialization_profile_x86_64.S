.intel_syntax noprefix

# Wheelchair 1.3.18 deterministic outward-execution target profile.
# Expansion has no work-size magic threshold. The price below is a target
# Physical Reality parameter, analogous to the existing FP-div/load/AGU issue
# prices. It represents execution-context materialization + terminal join in the
# shared 1/12-cycle tick domain. It is chosen by the already-proven silicon
# profile, never by runtime CPU availability, worker count, credits, or load.
#
# 1.3.85 removes the vendor/model route. One Linux/x86-64 execution-lifecycle
# price is consumed by the common Physical Reality algebra. 1.3.92 keeps this
# price independent from both external execution admission and locality identity.
.equ OUTWARD_TICKS_LINUX_X86_64, 750000
.extern schedule_bound_ticks
.extern group_body_factor

.section .text
.global load_outward_materialization_ticks
.type load_outward_materialization_ticks,@function
load_outward_materialization_ticks:
    mov eax,OUTWARD_TICKS_LINUX_X86_64
    mov qword ptr [rip+outward_materialization_ticks],rax
    ret
.size load_outward_materialization_ticks,.-load_outward_materialization_ticks

# derive_tensor_chunk_work_ticks(edi=physical vector lanes) -> rax=ticks/structural quantum
# 1.3.24 Unified Physical Leaf Geometry.  The compiler publishes only the
# smallest mathematically/physically indivisible leaf quantum and its work price.
# Runtime N is not known here, so no fixed chunk is manufactured AOT.  Launch-time
# Physical Reality combines this quantum with exact external execution admission
# and the outward lifecycle price to choose the largest profitable integer width
# without manufacturing a binary executor geometry.
.global derive_tensor_chunk_work_ticks
.type derive_tensor_chunk_work_ticks,@function
derive_tensor_chunk_work_ticks:
    push rbx
    push r12
    push r13
    mov ebx,edi
    test ebx,ebx
    jz .dtcwt_saturate
    mov ecx,dword ptr [rip+group_body_factor]
    test ecx,ecx
    jz .dtcwt_saturate
    imul rbx,rcx                   # natural elements / physical episode
    test rbx,rbx
    jz .dtcwt_saturate
    mov r12d,dword ptr [rip+schedule_bound_ticks]
    test r12d,r12d
    jz .dtcwt_saturate
    # schedule_bound_ticks is measured from the one-body probe.  Grouping may
    # erase control/materialization edges, but it cannot erase the necessary
    # arithmetic of each body.  Price the whole physical episode before leaf
    # geometry is compared with outward-materialization cost.  This prevents a
    # wider Group from masquerading as less work and silently retracting the
    # execution tree.
    mov eax,r12d
    mul rcx
    test rdx,rdx
    jnz .dtcwt_saturate
    mov r12,rax

    # quantum = lcm(natural_episode_elements, proved_alignment_elements).
    mov r13,qword ptr [rip+tensor_leaf_alignment_elements]
    test r13,r13
    jnz .dtcwt_have_alignment
    mov r13,rbx
.dtcwt_have_alignment:
    mov r8,rbx
    mov r9,r13
.dtcwt_gcd:
    test r9,r9
    jz .dtcwt_gcd_done
    mov rax,r8
    xor edx,edx
    div r9
    mov r8,r9
    mov r9,rdx
    jmp .dtcwt_gcd
.dtcwt_gcd_done:
    test r8,r8
    jz .dtcwt_saturate
    mov rax,rbx
    xor edx,edx
    div r8
    mul r13
    test rdx,rdx
    jnz .dtcwt_saturate
    mov r13,rax                    # structural quantum elements
    test r13,r13
    jz .dtcwt_saturate

    # work per quantum = (quantum/natural_episode) * full Group episode ticks.
    xor edx,edx
    div rbx
    test rdx,rdx
    jnz .dtcwt_saturate
    mul r12
    test rdx,rdx
    jnz .dtcwt_saturate
    test rax,rax
    jz .dtcwt_saturate
    mov qword ptr [rip+tensor_chunk_work_ticks],rax
    mov qword ptr [rip+tensor_chunk_elements],r13
    pop r13
    pop r12
    pop rbx
    ret
.dtcwt_saturate:
    mov qword ptr [rip+tensor_chunk_elements],1
    mov rax,0x7fffffffffffffff
    mov qword ptr [rip+tensor_chunk_work_ticks],rax
    pop r13
    pop r12
    pop rbx
    ret
.size derive_tensor_chunk_work_ticks,.-derive_tensor_chunk_work_ticks

.section .bss
.p2align 3
.global outward_materialization_ticks
outward_materialization_ticks: .skip 8
.global tensor_chunk_work_ticks
tensor_chunk_work_ticks: .skip 8
.global tensor_chunk_elements
tensor_chunk_elements: .skip 8
.global tensor_leaf_alignment_elements
tensor_leaf_alignment_elements: .skip 8
