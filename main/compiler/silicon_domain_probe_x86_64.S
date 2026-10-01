.intel_syntax noprefix

# Wheelchair 1.3.87 shared x86-64 silicon-domain identity + static-placement probe.
#
# This is compile-time target discovery only. It never queries idle capacity,
# schedules program work, chooses a recipient, or creates a worker abstraction.
# The process's externally admitted affinity mask is immutable input. For each
# admitted logical CPU, a temporary single-CPU affinity is used only long enough
# to read that CPU's architectural APIC identity; the original mask is restored
# before returning. Cache sharing widths are supplied by the caller from the
# deterministic cache-topology leaf. The resulting maxima are therefore the
# actual admitted intersections of L1D/L2/L3 domains, not min(count,width)
# approximations and not guessed Linux-CPU-number adjacency.

.equ SYS_read,0
.equ SYS_close,3
.equ SYS_sched_setaffinity,203
.equ SYS_sched_getaffinity,204
.equ SYS_openat,257
.equ SYS_getcpu,309
.equ AT_FDCWD,-100
.equ O_RDONLY,0
.equ SD_STATIC_MASK_BYTES,128
.equ SD_AFFINITY_SEED_BYTES,128
.equ SD_ERRNO_EINVAL,22

.global silicon_domain_probe
.global sd_allowed_cpu_count
.global sd_current_cpu
.global sd_current_numa_node
.global sd_l1d_domain_max
.global sd_l2_domain_max
.global sd_l3_domain_max
.global sd_l1d_domain_count
.global sd_l2_domain_count
.global sd_l3_domain_count
.global sd_execution_admission_capacity
.global sd_cpu_quota_usec
.global sd_cpu_period_usec
.global sd_domain_identity_exact
.global sd_preferred_l3_domain_id
.global sd_preferred_l3_cpu_count
.global sd_preferred_l3_mask_bytes
.global sd_preferred_l3_mask
.global sd_static_placement_exact
.global sd_static_placement_required

.section .text


# Read the cgroup-v2 cpu.max temporal budget exposed to this process namespace.
# The exact quota and period are retained as independent Physical Facts. They are
# not divided into an integer "CPU count" and never cap execution multiplicity.
# max/missing/malformed leaves both values zero. EAX=1 on a finite valid budget.
sd_read_cgroup_cpu_temporal_budget:
    push rbx
    push r12
    push r13
    mov qword ptr [rip+sd_cpu_quota_usec],0
    mov qword ptr [rip+sd_cpu_period_usec],0
    mov eax,SYS_openat
    mov edi,AT_FDCWD
    lea rsi,[rip+sd_cpu_max_path]
    mov edx,O_RDONLY
    xor r10d,r10d
    syscall
    test rax,rax
    js .srcqt_none
    mov ebx,eax
    mov eax,SYS_read
    mov edi,ebx
    lea rsi,[rip+sd_cpu_max_buf]
    mov edx,63
    syscall
    mov r12,rax
    mov eax,SYS_close
    mov edi,ebx
    syscall
    test r12,r12
    jle .srcqt_none

    lea rsi,[rip+sd_cpu_max_buf]
    cmp r12,3
    jb .srcqt_none
    cmp byte ptr [rsi],'m'
    jne .srcqt_parse_quota
    cmp byte ptr [rsi+1],'a'
    jne .srcqt_none
    cmp byte ptr [rsi+2],'x'
    jne .srcqt_none
    jmp .srcqt_none

.srcqt_parse_quota:
    xor r8,r8
    xor r13d,r13d
.srcqt_qdigit:
    movzx eax,byte ptr [rsi]
    cmp al,'0'
    jb .srcqt_qdone
    cmp al,'9'
    ja .srcqt_qdone
    imul r8,r8,10
    sub eax,'0'
    add r8,rax
    inc rsi
    inc r13d
    jmp .srcqt_qdigit
.srcqt_qdone:
    test r13d,r13d
    jz .srcqt_none
.srcqt_space:
    movzx eax,byte ptr [rsi]
    cmp al,' '
    jne .srcqt_period
    inc rsi
    jmp .srcqt_space
.srcqt_period:
    xor r9,r9
    xor r13d,r13d
.srcqt_pdigit:
    movzx eax,byte ptr [rsi]
    cmp al,'0'
    jb .srcqt_pdone
    cmp al,'9'
    ja .srcqt_pdone
    imul r9,r9,10
    sub eax,'0'
    add r9,rax
    inc rsi
    inc r13d
    jmp .srcqt_pdigit
.srcqt_pdone:
    test r13d,r13d
    jz .srcqt_none
    test r8,r8
    jz .srcqt_none
    test r9,r9
    jz .srcqt_none
    mov qword ptr [rip+sd_cpu_quota_usec],r8
    mov qword ptr [rip+sd_cpu_period_usec],r9
    mov eax,1
    jmp .srcqt_done
.srcqt_none:
    xor eax,eax
.srcqt_done:
    pop r13
    pop r12
    pop rbx
    ret

# eax=sharing logical-context count -> eax=ceil(log2(count)).
sd_share_shift:
    cmp eax,1
    jbe .sss_zero
    dec eax
    bsr eax,eax
    inc eax
    ret
.sss_zero:
    xor eax,eax
    ret

# Read architectural APIC identity for the CPU on which this thread currently
# executes. CF=0/eax=id on success, CF=1 when no architectural ID is exposed.
sd_read_apic_id:
    push rbx
    xor eax,eax
    cpuid
    mov r8d,eax
    cmp r8d,0x1f
    jae .srai_1f
    cmp r8d,0x0b
    jae .srai_b
    cmp r8d,1
    jb .srai_fail
    mov eax,1
    cpuid
    mov eax,ebx
    shr eax,24
    pop rbx
    clc
    ret
.srai_1f:
    mov eax,0x1f
    xor ecx,ecx
    cpuid
    mov r9d,ebx
    and r9d,0xffff
    test r9d,r9d
    jz .srai_b
    mov eax,edx
    pop rbx
    clc
    ret
.srai_b:
    mov eax,0x0b
    xor ecx,ecx
    cpuid
    mov r9d,ebx
    and r9d,0xffff
    test r9d,r9d
    jz .srai_leaf1
    mov eax,edx
    pop rbx
    clc
    ret
.srai_leaf1:
    cmp r8d,1
    jb .srai_fail
    mov eax,1
    cpuid
    mov eax,ebx
    shr eax,24
    pop rbx
    clc
    ret
.srai_fail:
    pop rbx
    stc
    ret

# Record one domain identity.
# eax=domain id, rdi=ids[], rsi=counts[], rdx=&domain_count, rcx=&max_count.
sd_record_group:
    mov r9d,dword ptr [rdx]
    xor r8d,r8d
.srg_find:
    cmp r8d,r9d
    jae .srg_new
    cmp dword ptr [rdi+r8*4],eax
    je .srg_hit
    inc r8d
    jmp .srg_find
.srg_hit:
    inc dword ptr [rsi+r8*4]
    mov r10d,dword ptr [rsi+r8*4]
    cmp r10d,dword ptr [rcx]
    jbe .srg_done
    mov dword ptr [rcx],r10d
.srg_done:
    ret
.srg_new:
    mov r8,qword ptr [rip+sd_affinity_bytes]
    shl r8,3
    cmp r9,r8
    jae .srg_done
    mov dword ptr [rdi+r9*4],eax
    mov dword ptr [rsi+r9*4],1
    inc r9d
    mov dword ptr [rdx],r9d
    cmp dword ptr [rcx],1
    jae .srg_done
    mov dword ptr [rcx],1
    ret

# Choose one exact admitted L3 domain and materialize its Linux affinity mask.
# This is target placement, not runtime scheduling: the selected domain is a
# compile-time fact and generated executions only inherit the one baked mask.
# Ties are resolved by architectural domain identity, never Linux CPU number.
sd_choose_preferred_l3_domain:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov dword ptr [rip+sd_preferred_l3_domain_id],-1
    mov dword ptr [rip+sd_preferred_l3_cpu_count],0
    mov dword ptr [rip+sd_static_placement_exact],0
    mov dword ptr [rip+sd_static_placement_required],0
    mov rax,qword ptr [rip+sd_affinity_bytes]
    mov qword ptr [rip+sd_preferred_l3_mask_bytes],rax
    lea rdi,[rip+sd_preferred_l3_mask]
    xor eax,eax
    mov ecx,SD_STATIC_MASK_BYTES/8
    rep stosq

    mov r15d,dword ptr [rip+sd_l3_domain_count]
    test r15d,r15d
    jz .scpl_done
    xor r12d,r12d                         # group index
    xor r13d,r13d                         # best count
    mov r14d,-1                           # best architectural id
.scpl_pick:
    cmp r12d,r15d
    jae .scpl_build
    lea rax,[rip+sd_l3_counts]
    mov ebx,dword ptr [rax+r12*4]
    lea rax,[rip+sd_l3_ids]
    mov edx,dword ptr [rax+r12*4]
    cmp ebx,r13d
    ja .scpl_take
    jb .scpl_next
    cmp edx,r14d
    jae .scpl_next
.scpl_take:
    mov r13d,ebx
    mov r14d,edx
.scpl_next:
    inc r12d
    jmp .scpl_pick

.scpl_build:
    test r13d,r13d
    jz .scpl_done
    mov dword ptr [rip+sd_preferred_l3_cpu_count],r13d
    mov dword ptr [rip+sd_preferred_l3_domain_id],r14d
    xor r12d,r12d                         # Linux CPU id
.scpl_cpu:
    mov rax,qword ptr [rip+sd_affinity_bytes]
    shl rax,3
    cmp r12,rax
    jae .scpl_compare
    mov eax,r12d
    shr eax,3
    mov r13d,eax
    lea rax,[rip+sd_original_mask]
    movzx ebx,byte ptr [rax+r13]
    mov ecx,r12d
    and ecx,7
    bt ebx,ecx
    jnc .scpl_cpu_next
    lea rax,[rip+sd_cpu_l3_domain_ids]
    cmp dword ptr [rax+r12*4],r14d
    jne .scpl_cpu_next
    mov edx,1
    shl edx,cl
    lea rax,[rip+sd_preferred_l3_mask]
    or byte ptr [rax+r13],dl
.scpl_cpu_next:
    inc r12d
    jmp .scpl_cpu

.scpl_compare:
    mov dword ptr [rip+sd_static_placement_exact],1
    xor r12d,r12d
    mov r13,qword ptr [rip+sd_affinity_bytes]
.scpl_cmp_loop:
    cmp r12,r13
    jae .scpl_done
    lea rax,[rip+sd_original_mask]
    mov bl,byte ptr [rax+r12]
    lea rax,[rip+sd_preferred_l3_mask]
    cmp bl,byte ptr [rax+r12]
    jne .scpl_required
    inc r12
    jmp .scpl_cmp_loop
.scpl_required:
    mov dword ptr [rip+sd_static_placement_required],1
.scpl_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Count external invocation CPUs without imposing the static-placement mask width.
# The seed grows only when the kernel reports EINVAL for an undersized cpuset.
# eax=count, with 1 as the conservative syscall-failure fact.
sd_count_external_affinity:
    mov r10d,SD_AFFINITY_SEED_BYTES
.sdcea_probe:
    sub rsp,r10
    mov eax,SYS_sched_getaffinity
    xor edi,edi
    mov rsi,r10
    mov rdx,rsp
    syscall
    test rax,rax
    jns .sdcea_have
    cmp eax,-SD_ERRNO_EINVAL
    jne .sdcea_fallback_release
    add rsp,r10
    shl r10,1
    jc .sdcea_fallback_noalloc
    jmp .sdcea_probe
.sdcea_have:
    mov r8,rax
    xor r9d,r9d
    xor ecx,ecx
.sdcea_byte:
    cmp r9,r8
    jae .sdcea_counted
    movzx eax,byte ptr [rsp+r9]
    mov edx,8
.sdcea_bit:
    shr al,1
    adc ecx,0
    dec edx
    jnz .sdcea_bit
    inc r9
    jmp .sdcea_byte
.sdcea_counted:
    test ecx,ecx
    jnz .sdcea_return_release
.sdcea_fallback_release:
    mov ecx,1
.sdcea_return_release:
    mov eax,ecx
    add rsp,r10
    ret
.sdcea_fallback_noalloc:
    mov eax,1
    ret

# silicon_domain_probe(edi=l1d_share_threads,
#                      esi=l2_share_threads,
#                      edx=l3_share_threads)
#
# Results are exported through sd_* globals. Execution admission and spatial
# locality are deliberately independent: affinity/quota bound multiplicity;
# cache-domain identity prices placement only. Probe failure therefore removes
# locality knowledge without erasing independently executable work.
silicon_domain_probe:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov dword ptr [rip+sd_l1_share],edi
    mov dword ptr [rip+sd_l2_share],esi
    mov dword ptr [rip+sd_l3_share],edx
    mov dword ptr [rip+sd_allowed_cpu_count],0
    mov dword ptr [rip+sd_current_cpu],-1
    mov dword ptr [rip+sd_current_numa_node],-1
    mov dword ptr [rip+sd_l1d_domain_max],0
    mov dword ptr [rip+sd_l2_domain_max],0
    mov dword ptr [rip+sd_l3_domain_max],0
    mov dword ptr [rip+sd_l1d_domain_count],0
    mov dword ptr [rip+sd_l2_domain_count],0
    mov dword ptr [rip+sd_l3_domain_count],0
    mov qword ptr [rip+sd_cpu_quota_usec],0
    mov qword ptr [rip+sd_cpu_period_usec],0
    mov dword ptr [rip+sd_execution_admission_capacity],1
    mov dword ptr [rip+sd_domain_identity_exact],0
    mov dword ptr [rip+sd_preferred_l3_domain_id],-1
    mov dword ptr [rip+sd_preferred_l3_cpu_count],0
    mov qword ptr [rip+sd_preferred_l3_mask_bytes],0
    mov dword ptr [rip+sd_static_placement_exact],0
    mov dword ptr [rip+sd_static_placement_required],0

    # External admission authority is unbounded by the static-placement ABI.
    # A compact baked placement mask remains an optional locality witness only.
    call sd_count_external_affinity
    mov r13d,eax
    mov dword ptr [rip+sd_allowed_cpu_count],r13d

    mov eax,SYS_sched_getaffinity
    xor edi,edi
    mov esi,SD_STATIC_MASK_BYTES
    lea rdx,[rip+sd_original_mask]
    syscall
    test rax,rax
    js .sdp_topology_mask_unavailable
    mov qword ptr [rip+sd_affinity_bytes],rax
    jmp .sdp_admission_ready
.sdp_topology_mask_unavailable:
    mov qword ptr [rip+sd_affinity_bytes],0
.sdp_admission_ready:

    # Spatial multiplicity and temporal budget are independent. The affinity
    # mask proves the admitted execution-context set. cpu.max is retained in its
    # native quota/period form for temporal Physical Reality and cannot erase a
    # context already present in that set.
    call sd_read_cgroup_cpu_temporal_budget
    mov ecx,r13d
    test ecx,ecx
    jnz .sdp_admission_nonzero
    mov ecx,1
.sdp_admission_nonzero:
    mov dword ptr [rip+sd_execution_admission_capacity],ecx

    # Diagnostic/current memory-domain identity. It is not used as a placement
    # choice; exact cache-domain maxima are computed over the whole allowed set.
    mov eax,SYS_getcpu
    lea rdi,[rip+sd_current_cpu]
    lea rsi,[rip+sd_current_numa_node]
    xor edx,edx
    syscall

    # Sharing counts -> APIC identity shifts.
    mov eax,dword ptr [rip+sd_l1_share]
    call sd_share_shift
    mov dword ptr [rip+sd_l1_shift],eax
    mov eax,dword ptr [rip+sd_l2_share]
    call sd_share_shift
    mov dword ptr [rip+sd_l2_shift],eax
    mov eax,dword ptr [rip+sd_l3_share]
    call sd_share_shift
    mov dword ptr [rip+sd_l3_shift],eax

    # A one-context target is already an exact single domain without affinity
    # mutation. Unknown cache leaves remain explicitly unknown (domain_count=0).
    cmp r13d,1
    jne .sdp_scan_prepare
    mov dword ptr [rip+sd_domain_identity_exact],1
    cmp dword ptr [rip+sd_l1_share],0
    je .sdp_one_l2
    mov dword ptr [rip+sd_l1d_domain_max],1
    mov dword ptr [rip+sd_l1d_domain_count],1
.sdp_one_l2:
    cmp dword ptr [rip+sd_l2_share],0
    je .sdp_one_l3
    mov dword ptr [rip+sd_l2_domain_max],1
    mov dword ptr [rip+sd_l2_domain_count],1
.sdp_one_l3:
    cmp dword ptr [rip+sd_l3_share],0
    je .sdp_finalize
    mov dword ptr [rip+sd_l3_domain_max],1
    mov dword ptr [rip+sd_l3_domain_count],1
    mov rax,qword ptr [rip+sd_affinity_bytes]
    mov qword ptr [rip+sd_preferred_l3_mask_bytes],rax
    lea rsi,[rip+sd_original_mask]
    lea rdi,[rip+sd_preferred_l3_mask]
    mov rcx,rax
    rep movsb
    mov dword ptr [rip+sd_preferred_l3_cpu_count],1
    mov dword ptr [rip+sd_static_placement_exact],1
    mov dword ptr [rip+sd_static_placement_required],0
    jmp .sdp_finalize

.sdp_scan_prepare:
    # If affinity discovery itself failed, no exact CPU identity scan is legal.
    cmp qword ptr [rip+sd_affinity_bytes],0
    je .sdp_fallback
    mov dword ptr [rip+sd_probe_failed],0
    xor r12d,r12d                         # Linux CPU id
.sdp_cpu_loop:
        mov eax,r12d
    shr eax,3
    mov r13d,eax                          # byte index
    cmp r13,qword ptr [rip+sd_affinity_bytes]
    jae .sdp_restore
    lea r11,[rip+sd_original_mask]
    movzx eax,byte ptr [r11+r13]
    mov ecx,r12d
    and ecx,7
    bt eax,ecx
    jnc .sdp_cpu_next

    # Build a one-CPU temporary mask. Every byte is otherwise zero because the
    # previously touched byte is cleared immediately after the syscall.
    mov edx,1
    shl edx,cl
    lea r11,[rip+sd_probe_mask]
    mov byte ptr [r11+r13],dl
    mov eax,SYS_sched_setaffinity
    xor edi,edi
    mov esi,SD_STATIC_MASK_BYTES
    lea rdx,[rip+sd_probe_mask]
    syscall
    lea r11,[rip+sd_probe_mask]
    mov byte ptr [r11+r13],0
    test rax,rax
    js .sdp_mark_failed

    call sd_read_apic_id
    jc .sdp_mark_failed
    mov ebx,eax                            # full APIC id

    cmp dword ptr [rip+sd_l1_share],0
    je .sdp_record_l2
    mov eax,ebx
    mov ecx,dword ptr [rip+sd_l1_shift]
    shr eax,cl
    lea rdi,[rip+sd_l1_ids]
    lea rsi,[rip+sd_l1_counts]
    lea rdx,[rip+sd_l1d_domain_count]
    lea rcx,[rip+sd_l1d_domain_max]
    call sd_record_group
.sdp_record_l2:
    cmp dword ptr [rip+sd_l2_share],0
    je .sdp_record_l3
    mov eax,ebx
    mov ecx,dword ptr [rip+sd_l2_shift]
    shr eax,cl
    lea rdi,[rip+sd_l2_ids]
    lea rsi,[rip+sd_l2_counts]
    lea rdx,[rip+sd_l2_domain_count]
    lea rcx,[rip+sd_l2_domain_max]
    call sd_record_group
.sdp_record_l3:
    cmp dword ptr [rip+sd_l3_share],0
    je .sdp_cpu_next
    mov eax,ebx
    mov ecx,dword ptr [rip+sd_l3_shift]
    shr eax,cl
    lea r10,[rip+sd_cpu_l3_domain_ids]
    mov dword ptr [r10+r12*4],eax
    lea rdi,[rip+sd_l3_ids]
    lea rsi,[rip+sd_l3_counts]
    lea rdx,[rip+sd_l3_domain_count]
    lea rcx,[rip+sd_l3_domain_max]
    call sd_record_group
.sdp_cpu_next:
    inc r12d
    jmp .sdp_cpu_loop
.sdp_mark_failed:
    mov dword ptr [rip+sd_probe_failed],1

.sdp_restore:
    mov eax,SYS_sched_setaffinity
    xor edi,edi
    mov esi,SD_STATIC_MASK_BYTES
    lea rdx,[rip+sd_original_mask]
    syscall
    test rax,rax
    js .sdp_fallback
    cmp dword ptr [rip+sd_probe_failed],0
    jne .sdp_fallback
    mov dword ptr [rip+sd_domain_identity_exact],1
    call sd_choose_preferred_l3_domain
    jmp .sdp_finalize

.sdp_fallback:
    # No locality guess survives. If exact topology identity cannot be proved,
    # clear only the placement facts. Exact external execution admission remains
    # valid and is not reinterpreted as cache identity.
    mov dword ptr [rip+sd_l1d_domain_max],0
    mov dword ptr [rip+sd_l2_domain_max],0
    mov dword ptr [rip+sd_l3_domain_max],0
    mov dword ptr [rip+sd_l1d_domain_count],0
    mov dword ptr [rip+sd_l2_domain_count],0
    mov dword ptr [rip+sd_l3_domain_count],0
    mov dword ptr [rip+sd_domain_identity_exact],0
    mov dword ptr [rip+sd_preferred_l3_domain_id],-1
    mov dword ptr [rip+sd_preferred_l3_cpu_count],0
    mov qword ptr [rip+sd_preferred_l3_mask_bytes],0
    mov dword ptr [rip+sd_static_placement_exact],0
    mov dword ptr [rip+sd_static_placement_required],0

.sdp_finalize:
    # Locality identity owns placement only. Execution multiplicity was already
    # closed from external admission and survives an unknown cache topology.
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.section .rodata
sd_cpu_max_path: .asciz "/sys/fs/cgroup/cpu.max"

.section .bss
.p2align 6
sd_cpu_max_buf: .skip 64
.p2align 6
sd_original_mask: .skip SD_STATIC_MASK_BYTES
sd_probe_mask: .skip SD_STATIC_MASK_BYTES
sd_affinity_bytes: .skip 8
sd_allowed_cpu_count: .skip 4
sd_current_cpu: .skip 4
sd_current_numa_node: .skip 4
sd_l1_share: .skip 4
sd_l2_share: .skip 4
sd_l3_share: .skip 4
sd_l1_shift: .skip 4
sd_l2_shift: .skip 4
sd_l3_shift: .skip 4
sd_l1d_domain_max: .skip 4
sd_l2_domain_max: .skip 4
sd_l3_domain_max: .skip 4
sd_l1d_domain_count: .skip 4
sd_l2_domain_count: .skip 4
sd_l3_domain_count: .skip 4
sd_execution_admission_capacity: .skip 4
sd_cpu_quota_usec: .skip 8
sd_cpu_period_usec: .skip 8
sd_domain_identity_exact: .skip 4
sd_preferred_l3_domain_id: .skip 4
sd_preferred_l3_cpu_count: .skip 4
sd_preferred_l3_mask_bytes: .skip 8
sd_static_placement_exact: .skip 4
sd_static_placement_required: .skip 4
sd_probe_failed: .skip 4
.p2align 6
sd_preferred_l3_mask: .skip SD_STATIC_MASK_BYTES
sd_cpu_l3_domain_ids: .skip SD_STATIC_MASK_BYTES*8*4
.p2align 6
sd_l1_ids: .skip SD_STATIC_MASK_BYTES*8*4
sd_l1_counts: .skip SD_STATIC_MASK_BYTES*8*4
sd_l2_ids: .skip SD_STATIC_MASK_BYTES*8*4
sd_l2_counts: .skip SD_STATIC_MASK_BYTES*8*4
sd_l3_ids: .skip SD_STATIC_MASK_BYTES*8*4
sd_l3_counts: .skip SD_STATIC_MASK_BYTES*8*4
