.intel_syntax noprefix
.include "runtime/execution_admission_refresh_x86_64.inc"

# Wheelchair 1.3.17 external-silicon causal-region fabric.
#
# The compiler has already fused provably non-branching causal chains. Runtime
# contexts represent ready causal regions only, never workers or future work.
# Readiness materializes outward to Linux; completion exits. Wheelchair owns no
# CPU capacity, credit, affinity width, donor/recipient identity or idle executor.
# One virtual stack arena provides disjoint node slices without precreating tasks.

.equ SYS_mmap, 9
.equ SYS_munmap, 11
.equ SYS_clone, 56
.equ SYS_wait4, 61
.equ SYS_sched_setaffinity, 203
.equ SYS_exit, 60

.equ CLONE_VM_FILES_FS_SIGCHLD, 0x711
.equ CLONE_PARENT, 0x8000
.equ CLONE_OUTWARD_SUCCESSOR, 0x8711
.equ PROT_RW, 3
.equ MAP_PRIVATE_ANON_STACK, 0x20022
.equ MAP_PRIVATE_ANON, 0x22

.equ GR_STACK_BYTES, 65536
.equ GR_REALIZATION_RECONFIGURABLE_FABRIC, 2

.equ ST_NODE_BYTES, 64
.equ ST_NODE_ARRIVED, 0
.equ ST_NODE_DONE, 4
.equ ST_NODE_LOCAL_NEXT, 8
.equ ST_NODE_FRONTIER_TAIL, 12
.equ ST_NODE_FRONTIER_ANCHOR_NEXT, 16
.equ ST_NODE_FRONTIER_ANCHOR, 20
# Every causal node owns one cache line. The state arena is sized from
# gr_node_count at invocation time; trailing invocation metadata holds stack
# base/size plus one shared x86 execution-admission count. The count is not a
# worker pool or idle-resource query: it only prevents materializing more native
# execution contexts than the exact AOT external admission fact.

.section .text
.p2align 6
.global gr_release_base
gr_release_base:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,64

    # A heterogeneous plan is executable only when the target integration has
    # proved a fabric activation bridge.  Missing hardware is not a request to
    # reinterpret fabric Regions through their retained x86 diagnostic bodies.
    cmp dword ptr [rip+gr_fabric_region_count],0
    je .gr_fabric_admission_done
    cmp dword ptr [rip+gr_fabric_activation_bridge_present],1
    jne .gr_fail_no_state
    cmp qword ptr [rip+gr_fabric_activation_entry],0
    je .gr_fail_no_state
.gr_fabric_admission_done:

    # Static silicon placement is locality proof, never authority to escape the
    # invocation domain.  Intersect it with the caller's current affinity just
    # like Tensor/Field, then let invocation admission observe the narrowed set.
    CONSTRAIN_STATIC_PLACEMENT_WITHIN_INVOCATION gr_static_placement_required, gr_static_placement_mask_bytes, gr_static_placement_mask

    mov eax,dword ptr [rip+gr_node_count]
    test eax,eax
    jz .gr_ok_no_state

    # Cache-line state records hold causal arrivals only. They do not represent
    # workers. Size is a direct function of the actual causal graph: one line per
    # node plus 24 bytes of invocation metadata (stack base/size + live x86 count).
    mov rsi,rax
    shl rsi,6
    add rsi,24                   # invocation metadata immediately follows node states
    jc .gr_fail_no_state
    mov qword ptr [rsp+40],rsi
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_RW
    mov r10d,MAP_PRIVATE_ANON
    mov r8d,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .gr_fail_no_state
    mov r15,rax
    mov qword ptr [rsp+48],rax
    call gr_init_state
    test eax,eax
    jnz .gr_state_fail

    # One virtual stack slice per semantic node. No executor is created here.
    mov eax,dword ptr [rip+gr_node_count]
    mov rsi,rax
    shl rsi,16                    # GR_STACK_BYTES == 65536
    test rsi,rsi
    jz .gr_state_fail
    push rsi
    call gr_state_meta_ptr
    pop rsi
    mov qword ptr [rax+8],rsi
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_RW
    mov r10d,MAP_PRIVATE_ANON_STACK
    mov r8d,-1
    xor r9d,r9d
    syscall
    test rax,rax
    js .gr_state_fail
    push rax
    call gr_state_meta_ptr
    mov rdx,rax
    pop rax
    mov qword ptr [rdx],rax

    # All currently-ready x86 roots are one physical frontier, but readiness is
    # not permission to manufacture an OS execution.  The existing shared
    # work-vs-lifecycle price still decides how many *additional* roots can repay
    # outward materialization.  Frontier fusion changes only ownership shape:
    # every admitted execution receives a fixed root chain before launch, so a
    # short early root cannot exit while later ready roots collapse onto the
    # invocation context.  No ready queue, worker, idle-CPU query or post-launch
    # task transfer exists.
    xor ebx,ebx
    xor r14d,r14d                       # x86 root count
    mov dword ptr [rsp+24],0            # total root count, including fabric
    mov dword ptr [rsp+12],-1           # invocation x86 root
    mov dword ptr [rsp+20],0            # extra roots whose work repays lifecycle
    call gr_meta_indegree_ptr
    mov qword ptr [rsp+32],rax
.gr_root_count_scan:
    cmp ebx,dword ptr [rip+gr_node_count]
    jae .gr_root_count_done
    mov rdx,qword ptr [rsp+32]
    cmp dword ptr [rdx+rbx*4],0
    jne .gr_root_count_next
    inc dword ptr [rsp+24]
    call gr_meta_realization_tag_ptr
    cmp dword ptr [rax+rbx*4],GR_REALIZATION_RECONFIGURABLE_FABRIC
    jne .gr_root_count_x86
    mov edi,ebx
    mov esi,CLONE_VM_FILES_FS_SIGCHLD
    call gr_materialize_node
    test eax,eax
    jnz .gr_runtime_fail
    jmp .gr_root_count_next
.gr_root_count_x86:
    inc r14d
    cmp dword ptr [rsp+12],-1
    jne .gr_root_count_cost
    mov dword ptr [rsp+12],ebx           # first x86 root stays in live context
    jmp .gr_root_count_next
.gr_root_count_cost:
    mov edi,ebx
    call gr_should_materialize
    test eax,eax
    jz .gr_root_count_next
    inc dword ptr [rsp+20]
.gr_root_count_next:
    inc ebx
    jmp .gr_root_count_scan
.gr_root_count_done:
    cmp dword ptr [rsp+24],0
    je .gr_runtime_fail
    test r14d,r14d
    jz .gr_enter_reap

    # K is not hardware width by itself.  One live invocation context already
    # exists; every additional bundle must be justified by one root that passed
    # the same Physical Reality lifecycle comparison used before frontier fusion.
    mov edx,dword ptr [rsp+20]
    inc edx                               # local context + profitable outward roots
    cmp edx,r14d
    cmova edx,r14d
    call gr_state_meta_ptr
    mov ecx,dword ptr [rax+20]            # exact invocation affinity multiplicity
    test ecx,ecx
    jnz .gr_root_have_admission
    mov ecx,1
.gr_root_have_admission:
    cmp edx,ecx
    cmova edx,ecx
    mov dword ptr [rsp+16],edx            # cost-gated fixed bundle count K

    # The anchors themselves form the temporary bundle vector inside their
    # existing cache-line state.  This avoids allocating a second root table:
    # every child anchor independently repays one outward lifecycle.
    mov ebx,dword ptr [rsp+12]
    cmp ebx,-1
    je .gr_runtime_fail
    mov rdx,rbx
    shl rdx,6
    mov dword ptr [r15+rdx+ST_NODE_LOCAL_NEXT],-1
    mov dword ptr [r15+rdx+ST_NODE_FRONTIER_TAIL],ebx
    mov dword ptr [r15+rdx+ST_NODE_FRONTIER_ANCHOR_NEXT],-1
    mov dword ptr [r15+rdx+ST_NODE_FRONTIER_ANCHOR],1
    mov dword ptr [rsp+56],ebx            # last anchor

    mov r13d,1                            # number of anchors already formed
    xor ebx,ebx
.gr_root_anchor_scan:
    cmp r13d,dword ptr [rsp+16]
    jae .gr_root_anchor_done
    cmp ebx,dword ptr [rip+gr_node_count]
    jae .gr_runtime_fail                  # cost count and roots disagreed
    mov rdx,qword ptr [rsp+32]
    cmp dword ptr [rdx+rbx*4],0
    jne .gr_root_anchor_next
    cmp ebx,dword ptr [rsp+12]
    je .gr_root_anchor_next
    call gr_meta_realization_tag_ptr
    cmp dword ptr [rax+rbx*4],GR_REALIZATION_RECONFIGURABLE_FABRIC
    je .gr_root_anchor_next
    mov edi,ebx
    call gr_should_materialize
    test eax,eax
    jz .gr_root_anchor_next

    mov eax,dword ptr [rsp+56]
    mov rdx,rax
    shl rdx,6
    mov dword ptr [r15+rdx+ST_NODE_FRONTIER_ANCHOR_NEXT],ebx
    mov rdx,rbx
    shl rdx,6
    mov dword ptr [r15+rdx+ST_NODE_LOCAL_NEXT],-1
    mov dword ptr [r15+rdx+ST_NODE_FRONTIER_TAIL],ebx
    mov dword ptr [r15+rdx+ST_NODE_FRONTIER_ANCHOR_NEXT],-1
    mov dword ptr [r15+rdx+ST_NODE_FRONTIER_ANCHOR],1
    mov dword ptr [rsp+56],ebx
    inc r13d
.gr_root_anchor_next:
    inc ebx
    jmp .gr_root_anchor_scan
.gr_root_anchor_done:

    # Every remaining x86 root joins one of the already-existing fixed bundles.
    # Cyclic assignment is structural and deterministic; it inspects neither CPU
    # identity nor runtime load.  Small roots may ride an execution whose lifecycle
    # is already justified, but they can never create an execution by themselves.
    mov r13d,dword ptr [rsp+12]           # current anchor
    xor ebx,ebx
.gr_root_chain_scan:
    cmp ebx,dword ptr [rip+gr_node_count]
    jae .gr_root_chain_done
    mov rdx,qword ptr [rsp+32]
    cmp dword ptr [rdx+rbx*4],0
    jne .gr_root_chain_next
    call gr_meta_realization_tag_ptr
    cmp dword ptr [rax+rbx*4],GR_REALIZATION_RECONFIGURABLE_FABRIC
    je .gr_root_chain_next
    mov rdx,rbx
    shl rdx,6
    cmp dword ptr [r15+rdx+ST_NODE_FRONTIER_ANCHOR],0
    jne .gr_root_chain_next

    mov rax,r13
    shl rax,6
    mov ecx,dword ptr [r15+rax+ST_NODE_FRONTIER_TAIL]
    mov rsi,rcx
    shl rsi,6
    mov dword ptr [r15+rsi+ST_NODE_LOCAL_NEXT],ebx
    mov dword ptr [r15+rax+ST_NODE_FRONTIER_TAIL],ebx
    mov dword ptr [r15+rdx+ST_NODE_LOCAL_NEXT],-1

    mov eax,dword ptr [r15+rax+ST_NODE_FRONTIER_ANCHOR_NEXT]
    cmp eax,-1
    jne .gr_root_chain_advance
    mov eax,dword ptr [rsp+12]
.gr_root_chain_advance:
    mov r13d,eax
.gr_root_chain_next:
    inc ebx
    jmp .gr_root_chain_scan
.gr_root_chain_done:

    # Materialize only the already-cost-justified child bundles. Clone refusal
    # merges that fixed chain into the invocation bundle; correctness and graph
    # identity therefore never depend on OS willingness to create a context.
    mov ebx,dword ptr [rsp+12]
    mov rax,rbx
    shl rax,6
    mov ebx,dword ptr [r15+rax+ST_NODE_FRONTIER_ANCHOR_NEXT]
.gr_root_launch_children:
    cmp ebx,-1
    je .gr_root_launch_local
    mov rax,rbx
    shl rax,6
    mov r13d,dword ptr [r15+rax+ST_NODE_FRONTIER_ANCHOR_NEXT]
    mov edi,ebx
    mov esi,CLONE_VM_FILES_FS_SIGCHLD
    call gr_materialize_chain
    test eax,eax
    jz .gr_root_launch_next

    # Append a refused child chain to the already-live local chain.  This happens
    # before the invocation begins consuming its bundle and creates no alternate
    # scheduler, recipient or compatibility execution path.
    mov ecx,dword ptr [rsp+12]
    mov rdx,rcx
    shl rdx,6
    mov edi,dword ptr [r15+rdx+ST_NODE_FRONTIER_TAIL]
    mov rsi,rdi
    shl rsi,6
    mov dword ptr [r15+rsi+ST_NODE_LOCAL_NEXT],ebx
    mov rsi,rbx
    shl rsi,6
    mov eax,dword ptr [r15+rsi+ST_NODE_FRONTIER_TAIL]
    mov dword ptr [r15+rdx+ST_NODE_FRONTIER_TAIL],eax
.gr_root_launch_next:
    mov ebx,r13d
    jmp .gr_root_launch_children

.gr_root_launch_local:
    mov edi,dword ptr [rsp+12]
    cmp edi,-1
    je .gr_enter_reap
    mov esi,CLONE_VM_FILES_FS_SIGCHLD
    call gr_node_chain_task
    test eax,eax
    jnz .gr_runtime_fail

    # The invocation context has finished every local continuation. It no longer
    # consumes one execution-admission slot while blocked in wait4, so descendants
    # may still expose the full admitted width. This releases capacity only; it
    # does not transfer work to a recipient.
.gr_enter_reap:
    call gr_release_x86_slot

    # All successfully materialized descendants use CLONE_PARENT, therefore every
    # live executor is a direct child of this invocation. Reap until none remain.
.gr_reap:
    mov dword ptr [rsp+8],0
    mov eax,SYS_wait4
    mov rdi,-1
    lea rsi,[rsp+8]
    xor edx,edx
    xor r10d,r10d
    syscall
    cmp rax,-10                    # -ECHILD: no outward executor remains
    je .gr_runtime_ok
    cmp rax,-4                     # -EINTR
    je .gr_reap
    test rax,rax
    js .gr_runtime_fail
    cmp dword ptr [rsp+8],0
    jne .gr_runtime_fail
    jmp .gr_reap

.gr_runtime_ok:
    xor r14d,r14d
    jmp .gr_release_maps
.gr_runtime_fail:
    mov r14d,1

.gr_release_maps:
    call gr_state_meta_ptr
    mov rdi,qword ptr [rax]
    test rdi,rdi
    jz .gr_unmap_state
    mov rsi,qword ptr [rax+8]
    mov eax,SYS_munmap
    syscall
.gr_unmap_state:
    mov eax,SYS_munmap
    mov rdi,qword ptr [rsp+48]
    mov rsi,qword ptr [rsp+40]
    syscall
    mov eax,r14d
    jmp .gr_done

.gr_state_fail:
    mov eax,SYS_munmap
    mov rdi,qword ptr [rsp+48]
    mov rsi,qword ptr [rsp+40]
    syscall
.gr_fail_no_state:
    mov eax,1
    jmp .gr_done
.gr_ok_no_state:
    xor eax,eax
.gr_done:
    add rsp,64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# gr_materialize_node(edi=node_id, esi=clone_flags) -> eax=0 success, 1 refusal.
# Node id selects a unique stack slice; there is no capacity slot or CPU choice.
gr_materialize_node:
    push r12
    push r13
    mov r12d,edi
    mov r13d,esi

    # Domain dispatch is already closed by AOT Physical Reality. Runtime does not
    # choose a device: it only materializes the realization tag burned for this
    # Region. A fabric Region enters the one activation ABI instead of creating
    # an x86 clone.
    call gr_meta_realization_tag_ptr
    mov eax,dword ptr [rax+r12*4]
    cmp eax,GR_REALIZATION_RECONFIGURABLE_FABRIC
    je .gmn_fabric

    # Native materialization is bounded by the same exact external execution
    # admission used by Tensor/Field. If the bound is already occupied, the
    # caller continues this ready Region locally instead of manufacturing another
    # context. No runtime hardware-capacity query is performed.
    call gr_try_acquire_x86_slot
    test eax,eax
    jnz .gmn_fail

    mov rdx,r12
    shl rdx,16                    # GR_STACK_BYTES == 65536
    call gr_state_meta_ptr
    mov rsi,qword ptr [rax]
    test rsi,rsi
    jz .gmn_release_fail
    add rsi,rdx
    add rsi,GR_STACK_BYTES-16
    mov eax,SYS_clone
    mov edi,r13d
    xor edx,edx
    xor r10d,r10d
    xor r8d,r8d
    syscall
    test rax,rax
    js .gmn_release_fail
    jz .gmn_child
    xor eax,eax
    jmp .gmn_done
.gmn_child:
    mov edi,r12d
    mov esi,CLONE_OUTWARD_SUCCESSOR
    call gr_node_task
    test eax,eax
    jnz .gmn_child_fail
    call gr_release_x86_slot
    xor edi,edi
    mov eax,SYS_exit
    syscall
    ud2
.gmn_child_fail:
    call gr_release_x86_slot
    mov edi,70
    mov eax,SYS_exit
    syscall
    ud2
.gmn_release_fail:
    call gr_release_x86_slot
    jmp .gmn_fail
.gmn_fabric:
    mov edi,r12d
    mov esi,r13d
    call gr_activate_fabric_node
    jmp .gmn_done
.gmn_fail:
    mov eax,1
.gmn_done:
    pop r13
    pop r12
    ret



# gr_materialize_chain(edi=head_node, esi=clone_flags) -> eax=0 success, 1 refusal.
# Root-frontier bundles are fixed before any executor starts. A child owns its
# entire chain and returns to the OS only after that fused physical execution is
# complete. This is not a worker and cannot accept later work.
gr_materialize_chain:
    push r12
    push r13
    mov r12d,edi
    mov r13d,esi
    call gr_try_acquire_x86_slot
    test eax,eax
    jnz .gmc_fail
    mov rdx,r12
    shl rdx,16
    call gr_state_meta_ptr
    mov rsi,qword ptr [rax]
    test rsi,rsi
    jz .gmc_release_fail
    add rsi,rdx
    add rsi,GR_STACK_BYTES-16
    mov eax,SYS_clone
    mov edi,r13d
    xor edx,edx
    xor r10d,r10d
    xor r8d,r8d
    syscall
    test rax,rax
    js .gmc_release_fail
    jz .gmc_child
    xor eax,eax
    jmp .gmc_done
.gmc_child:
    mov edi,r12d
    mov esi,CLONE_OUTWARD_SUCCESSOR
    call gr_node_chain_task
    test eax,eax
    jnz .gmc_child_fail
    call gr_release_x86_slot
    xor edi,edi
    mov eax,SYS_exit
    syscall
    ud2
.gmc_child_fail:
    call gr_release_x86_slot
    mov edi,70
    mov eax,SYS_exit
    syscall
    ud2
.gmc_release_fail:
    call gr_release_x86_slot
.gmc_fail:
    mov eax,1
.gmc_done:
    pop r13
    pop r12
    ret

# gr_node_chain_task(edi=head_node, esi=successor_flags) -> eax=0/1.
# LOCAL_NEXT was frozen by frontier fusion before launch and is consumed only by
# this execution.  No task can be appended after materialization.
gr_node_chain_task:
    push rbx
    push r12
    push r13
    mov ebx,edi
    mov r13d,esi
.gnct_loop:
    cmp ebx,-1
    je .gnct_ok
    mov rax,rbx
    shl rax,6
    mov r12d,dword ptr [r15+rax+ST_NODE_LOCAL_NEXT]
    mov edi,ebx
    mov esi,r13d
    call gr_node_task
    test eax,eax
    jnz .gnct_fail
    mov ebx,r12d
    jmp .gnct_loop
.gnct_ok:
    xor eax,eax
    jmp .gnct_done
.gnct_fail:
    mov eax,1
.gnct_done:
    pop r13
    pop r12
    pop rbx
    ret

# gr_activate_fabric_node(edi=node_id, esi=clone_flags) -> eax=0 accepted, 1 fail.
# ABI v2 passes only already-proved Physical-DAG facts:
#   rdi = 48-byte Region realization descriptor
#   esi = node id
#   rdx = invocation state base
#   ecx = successor materialization flags
#   r8  = external completion entry
# The bridge owns no scheduler or second graph. Acceptance means the physical
# fabric now owns this ready Region until it publishes completion.
gr_activate_fabric_node:
    push rbx
    push r12
    mov ebx,edi
    mov r12d,esi
    cmp dword ptr [rip+gr_fabric_activation_bridge_present],1
    jne .gaf_fail
    mov rax,qword ptr [rip+gr_fabric_activation_entry]
    test rax,rax
    jz .gaf_fail
    mov edi,ebx
    call gr_fabric_descriptor_for_node
    test rax,rax
    jz .gaf_fail
    mov rdi,rax
    mov esi,ebx
    mov rdx,r15
    mov ecx,r12d
    lea r8,[rip+gr_publish_completion_external]
    mov rax,qword ptr [rip+gr_fabric_activation_entry]
    call rax
    test eax,eax
    jnz .gaf_fail
    xor eax,eax
    jmp .gaf_done
.gaf_fail:
    mov eax,1
.gaf_done:
    pop r12
    pop rbx
    ret

# External completion bridge ABI. The fabric bridge supplies the invocation state
# base explicitly, so completion does not depend on an x86 executor retaining R15.
# gr_publish_completion_external(edi=node_id, esi=flags, rdx=state_base).
.global gr_publish_completion_external
gr_publish_completion_external:
    push r15
    mov r15,rdx
    call gr_publish_completion
    pop r15
    ret

# Invocation metadata only; anonymous-zero node pages need no initialization sweep.
gr_init_state:
    call gr_state_meta_ptr
    mov qword ptr [rax],0
    mov qword ptr [rax+8],0
    mov dword ptr [rax+16],1       # invocation root is the first live x86 context
    push rax
    call gr_read_invocation_admission
    mov ecx,eax
    pop rax
    mov dword ptr [rax+20],ecx     # invocation-only multiplicity fact
    xor eax,eax
    ret

# gr_read_invocation_admission() -> eax=count.
# Read current allowed affinity once per invocation. The immutable mask is thrown
# away immediately; no CPU identity, load or idle state survives into execution.
gr_read_invocation_admission:
    mov r10d,RUNTIME_AFFINITY_SEED_BYTES
.gria_probe:
    sub rsp,r10
    mov eax,204
    xor edi,edi
    mov rsi,r10
    mov rdx,rsp
    syscall
    test rax,rax
    jns .gria_have_affinity
    cmp eax,-ERRNO_EINVAL
    jne .gria_fallback_release
    add rsp,r10
    shl r10,1
    jc .gria_fallback_noalloc
    jmp .gria_probe
.gria_have_affinity:
    mov r8,rax
    xor r9d,r9d
    xor ecx,ecx
.gria_byte:
    cmp r9,r8
    jae .gria_done_count
    movzx eax,byte ptr [rsp+r9]
    mov edx,8
.gria_bit:
    shr al,1
    adc ecx,0
    dec edx
    jnz .gria_bit
    inc r9
    jmp .gria_byte
.gria_done_count:
    test ecx,ecx
    jnz .gria_return_release
.gria_fallback_release:
    mov ecx,1
.gria_return_release:
    mov eax,ecx
    add rsp,r10
    ret
.gria_fallback_noalloc:
    mov eax,1
    ret

# Acquire one native x86 execution slot from the invocation external-admission bound.
# This is a multiplicity guard only: no CPU identity, load, idle state, recipient,
# ready queue or worker object exists. eax=0 acquired, eax=1 keep work local.
gr_try_acquire_x86_slot:
    call gr_state_meta_ptr
    mov ecx,dword ptr [rax+20]
    cmp ecx,1
    jbe .gtaxs_fail
    lea r8,[rax+16]
.gtaxs_retry:
    mov eax,dword ptr [r8]
    cmp eax,ecx
    jae .gtaxs_fail
    lea edx,[eax+1]
    lock cmpxchg dword ptr [r8],edx
    jne .gtaxs_retry
    xor eax,eax
    ret
.gtaxs_fail:
    mov eax,1
    ret

# Return one native execution slot. Completion never names or wakes a recipient.
gr_release_x86_slot:
    call gr_state_meta_ptr
    lock sub dword ptr [rax+16],1
    ret

# Node execution never asks Linux which CPU/NUMA node it landed on and never
# migrates causal state after readiness. AOT placement is already burned by the
# compiler; runtime only inherits it. Cache-line state ownership remains sufficient
# for correctness and isolation.

# 1.3.17: future regions have no executor representation. They become physical
# only when a predecessor proves their true causal readiness.

# gr_should_materialize(edi=node_id) -> eax=1 outward, eax=0 continue locally.
# Dynamic/unbounded regions publish 0xffffffff and remain outward candidates.
# Straight-line regions compare their AOT native work price with the same shared
# outward lifecycle price used by Tensor/Field. Equality stays local.
gr_should_materialize:
    cmp edi,dword ptr [rip+gr_node_count]
    jae .gsm_outward
    call gr_meta_work_ticks_ptr
    mov eax,dword ptr [rax+rdi*4]
    cmp eax,-1
    je .gsm_outward
    mov edx,eax
    mov rax,qword ptr [rip+gr_outward_materialization_ticks]
    cmp rdx,rax
    ja .gsm_outward
    xor eax,eax
    ret
.gsm_outward:
    mov eax,1
    ret

# A Region executor exists only after true causal readiness. Execution and causal
# completion are separate physical events: the x86 realization publishes
# completion immediately after its native body returns, while a future fabric
# realization may publish the same event from an asynchronous completion bridge.
# There is one successor law, not a CPU graph plus an FPGA task graph.
gr_node_task:
    push rbx
    push r12
    push r13
    push r14
    mov ebx,edi
    mov r13d,esi                    # clone flags appropriate to this context

    # This executor exists only because the node is already causally ready.
    call gr_meta_entry_offsets_ptr
    mov eax,dword ptr [rax+rbx*4]
    test eax,eax
    jz .gnt_fail
    lea r12,[rip+gr_release_base]
    add r12,rax

    push r15
    push rbx
    push r13
    push r14
    call r12
    pop r14
    pop r13
    pop rbx
    pop r15

    # Native return is an x86 realization event, not the universal definition of
    # causal completion. Route it through the shared publisher used by every
    # physical domain.
    mov edi,ebx
    mov esi,r13d
    # Tail-publication keeps the old x86 return depth: exposing asynchronous
    # completion must not charge every native Region an extra call/ret pair.
    pop r14
    pop r13
    pop r12
    pop rbx
    jmp gr_publish_completion

.gnt_fail:
    mov eax,1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# gr_publish_completion(edi=node_id, esi=clone_flags) -> eax=0/1.
# This is the single causal completion authority. A future FPGA bridge needs only
# to prove the Region complete and enter here; it does not own a scheduler or a
# second successor graph.
.global gr_publish_completion
gr_publish_completion:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    mov ebx,edi
    mov r13d,esi
    mov ebp,-1                         # ready siblings that remain local
    cmp ebx,dword ptr [rip+gr_node_count]
    jae .gpc_fail

    mov rax,rbx
    shl rax,6
    mov byte ptr [r15+rax+ST_NODE_DONE],1

    call gr_meta_first_out_ptr
    mov r14d,dword ptr [rax+rbx*4]
.gpc_edges:
    cmp r14d,-1
    je .gpc_ready_exposed
    cmp r14d,dword ptr [rip+gr_edge_count]
    jae .gpc_fail
    call gr_meta_edge_v_ptr
    mov r12d,dword ptr [rax+r14*4]
    cmp r12d,dword ptr [rip+gr_node_count]
    jae .gpc_fail

    call gr_meta_indegree_ptr
    mov ecx,dword ptr [rax+r12*4]
    test ecx,ecx
    jz .gpc_fail                    # roots are never reached by an edge
    cmp ecx,1
    je .gpc_ready

    # True multi-predecessor join only. lock xadd returns a unique old count, so
    # exactly one predecessor observes the transition to full readiness.
    mov rax,r12
    shl rax,6
    lea rdi,[r15+rax+ST_NODE_ARRIVED]
    mov eax,1
    lock xadd dword ptr [rdi],eax
    inc eax
    cmp eax,ecx
    ja .gpc_fail
    jne .gpc_next

.gpc_ready:
    # Causal readiness does not itself manufacture an OS execution. If this
    # straight-line Region cannot repay one outward lifecycle, keep the already-
    # live silicon context and continue locally. Dynamic/unbounded Regions remain
    # outward candidates. No capacity query, device selector or recipient exists.
    mov edi,r12d
    call gr_should_materialize
    test eax,eax
    jz .gpc_continue_local
    mov edi,r12d
    mov esi,r13d
    call gr_materialize_node
    test eax,eax
    jz .gpc_next
.gpc_continue_local:
    # Do not let one local continuation hide later ready siblings. Link it into
    # this completion's node-local continuation chain, finish exposing the whole
    # ready frontier, then consume the chain with the already-live context.
    # No persistent queue, worker, recipient or work transfer exists.
    mov rax,r12
    shl rax,6
    mov dword ptr [r15+rax+ST_NODE_LOCAL_NEXT],ebp
    mov ebp,r12d

.gpc_next:
    call gr_meta_next_edge_ptr
    mov r14d,dword ptr [rax+r14*4]
    jmp .gpc_edges

.gpc_ready_exposed:
    cmp ebp,-1
    je .gpc_ok
    mov r12d,ebp
    mov rax,r12
    shl rax,6
    mov ebp,dword ptr [r15+rax+ST_NODE_LOCAL_NEXT]
    mov edi,r12d
    mov esi,r13d
    call gr_node_task
    test eax,eax
    jnz .gpc_fail
    jmp .gpc_ready_exposed

.gpc_ok:
    xor eax,eax
    jmp .gpc_done
.gpc_fail:
    mov eax,1
.gpc_done:
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Runtime metadata is appended by the AOT compiler immediately after
# gr_template_end. Layout; graph vectors are dword except edge_transfer_bytes and
# the fixed 48-byte physical descriptors:
#   indegree[N], first_out[N], entry_offsets[N], work_ticks[N],
#   edge_v[E], next_edge[E], edge_transfer_bytes[E:qword], realization_tag[N],
#   fabric_descriptor[N:48].
# A descriptor is a serialization of existing Physical-DAG facts, never a second
# semantic graph. The helpers derive every address from actual N/E.
gr_meta_indegree_ptr:
    lea rax,[rip+gr_template_end]
    ret
gr_meta_first_out_ptr:
    lea rax,[rip+gr_template_end]
    mov ecx,dword ptr [rip+gr_node_count]
    lea rax,[rax+rcx*4]
    ret
gr_meta_entry_offsets_ptr:
    lea rax,[rip+gr_template_end]
    mov ecx,dword ptr [rip+gr_node_count]
    lea rcx,[rcx+rcx]
    lea rax,[rax+rcx*4]
    ret
gr_meta_work_ticks_ptr:
    lea rax,[rip+gr_template_end]
    mov ecx,dword ptr [rip+gr_node_count]
    lea rcx,[rcx+rcx*2]
    lea rax,[rax+rcx*4]
    ret
gr_meta_edge_v_ptr:
    call gr_meta_work_ticks_ptr
    mov ecx,dword ptr [rip+gr_node_count]
    lea rax,[rax+rcx*4]
    ret
gr_meta_next_edge_ptr:
    call gr_meta_edge_v_ptr
    mov ecx,dword ptr [rip+gr_edge_count]
    lea rax,[rax+rcx*4]
    ret
.global gr_meta_edge_transfer_ptr
gr_meta_edge_transfer_ptr:
    call gr_meta_next_edge_ptr
    mov ecx,dword ptr [rip+gr_edge_count]
    lea rax,[rax+rcx*4]
    ret
.global gr_meta_realization_tag_ptr
gr_meta_realization_tag_ptr:
    call gr_meta_edge_transfer_ptr
    mov ecx,dword ptr [rip+gr_edge_count]
    lea rax,[rax+rcx*8]
    ret
.global gr_meta_fabric_descriptor_ptr
gr_meta_fabric_descriptor_ptr:
    call gr_meta_realization_tag_ptr
    mov ecx,dword ptr [rip+gr_node_count]
    lea rax,[rax+rcx*4]
    ret

# gr_fabric_descriptor_for_node(edi=node_id) -> rax=descriptor or 0.
# This is the target-integration ABI boundary. It exposes the one physical plan
# already chosen by the compiler; it does not dispatch or schedule work.
.global gr_fabric_descriptor_for_node
gr_fabric_descriptor_for_node:
    cmp edi,dword ptr [rip+gr_node_count]
    jae .gfdn_none
    mov edx,edi
    call gr_meta_fabric_descriptor_ptr
    imul rdx,rdx,48
    add rax,rdx
    ret
.gfdn_none:
    xor eax,eax
    ret

gr_state_meta_ptr:
    mov eax,dword ptr [rip+gr_node_count]
    shl rax,6
    lea rax,[r15+rax]
    ret

.p2align 4
.global gr_node_count
gr_node_count: .long 0
.global gr_edge_count
gr_edge_count: .long 0
.global gr_fabric_region_count
gr_fabric_region_count: .long 0
.global gr_fabric_activation_bridge_present
gr_fabric_activation_bridge_present: .long 0
.global gr_fabric_activation_abi_version
gr_fabric_activation_abi_version: .long 2
.global gr_fabric_descriptor_bytes
gr_fabric_descriptor_bytes: .long 48
.p2align 3
.global gr_fabric_activation_entry
gr_fabric_activation_entry: .quad 0
.global gr_outward_materialization_ticks
gr_outward_materialization_ticks: .quad 0x7fffffffffffffff
.global gr_execution_admission_capacity
gr_execution_admission_capacity: .long 1
.global gr_static_placement_required
gr_static_placement_required: .long 0
.global gr_static_placement_mask_bytes
gr_static_placement_mask_bytes: .long 0
.p2align 6
.global gr_static_placement_mask
gr_static_placement_mask: .zero 128

.p2align 4
.global gr_template_end
gr_template_end:
