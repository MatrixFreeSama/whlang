.intel_syntax noprefix
.include "compiler/isa_capabilities.inc"
.include "compiler/physical_cost_ticks.inc"
.include "compiler/groupfact.inc"
.include "compiler/silicon_reality.inc"

# Topology Parallel Compiler - handwritten x86-64 assembly bootstrap core.
# Linux x86-64, no libc, no C runtime, no pthread, no Python at runtime.
# GNU as is used only to create the first bootstrap executable.
#
# Supported sovereign seed slice:
#   {"format":"wheelchair.scalar/1", "exit_code": N}
# where 0 <= N <= 255.
# The compiler parses the source itself and emits a standalone ELF64 image
# directly with syscalls.  This is intentionally a strict seed, not a hidden
# dispatch to the previous Python implementation.

.equ SYS_read,       0
.equ SYS_write,      1
.equ SYS_close,      3
.equ SYS_openat,   257
.equ SYS_fchmod,    91
.equ SYS_exit,      60
.equ SYS_exit_group,231
.equ SYS_madvise,    28
.equ SYS_mbind,     237
.equ SYS_lseek,      8
.equ SYS_mmap,       9
.equ SYS_munmap,    11
.equ SYS_clone,      56
.equ SYS_wait4,      61
.equ CLONE_VM_FILES_FS_SIGCHLD, 0x711
.equ AT_FDCWD,     -100
.equ O_RDONLY,       0
.equ O_WRONLY,       1
.equ O_CREAT,       64
.equ O_TRUNC,      512
.equ OUT_FLAGS,    577
.equ STATIC_SOURCE_CAP, 65536
.equ HUGE_THRESHOLD, 2097152
.equ MADV_HUGEPAGE, 14
.equ MPOL_BIND, 2
.equ PROT_RW, 3
.equ MAP_PRIVATE_ANON, 0x22
.equ SEEK_SET, 0
.equ SEEK_END, 2

.section .text
.global _start
.global source_ptr
.global feature_bits
.global isa_cap_bits
.global source_length
.global execution_admission_capacity
.global synthesize_resource_schedule
.global synthesize_group_fact
.global group_logical_rank
.global group_relation_mask
.global group_lane_factor
.global group_rank
.global group_form
.global group_body_factor
.global group_carrier_factor
.global group_cardinality_exact
.global group_cardinality
.global schedule_counts
.global group_body_cap
.global group_body_cost_ops
.global group_body_cost_bytes
.global group_carrier_cap
.global schedule_bound_ticks
.global schedule_issue_bound_ticks
.extern compile_tensor_source
.extern compile_general_source
.extern surface_lower_to_json
.extern load_outward_materialization_ticks
.extern outward_materialization_ticks
.extern human_shell_report_success
.extern human_shell_report_error
.extern silicon_domain_probe
.extern sd_allowed_cpu_count
.extern sd_current_cpu
.extern sd_current_numa_node
.extern sd_l1d_domain_max
.extern sd_l2_domain_max
.extern sd_l3_domain_max
.extern sd_l1d_domain_count
.extern sd_l2_domain_count
.extern sd_l3_domain_count
.extern sd_execution_admission_capacity
.extern sd_cpu_quota_usec
.extern sd_cpu_period_usec
.extern sd_domain_identity_exact
.extern sd_preferred_l3_cpu_count
.extern sd_preferred_l3_mask_bytes
.extern sd_static_placement_exact
.extern sd_static_placement_required
.extern fabric_target_facts_proved
.extern ft_present
.extern ft_logic_units
.extern ft_register_units
.extern ft_dsp_units
.extern ft_local_storage_bytes
.extern ft_routing_domains
.extern ft_clock_regions
.extern ft_compute_ticks_num
.extern ft_compute_ticks_den
.extern ft_activation_ticks
.extern ft_transport_fixed_ticks
.extern ft_transport_ticks_per_byte
.type _start,@function
_start:
    # Stack: argc, argv[]
    mov r15, rsp
    mov r14, [r15]                 # argc
    lea r13, [r15+8]               # argv

    call detect_auxv
    call detect_cpu
    call detect_cache_topology
    call detect_cpu_topology
    # Locality closure remains exact when architectural cache identity is exposed.
    # Execution admission is closed independently from external affinity/quota,
    # so virtualization hiding cache leaves cannot collapse multiplicity to one.
    mov edi,dword ptr [rip+l1d_share_threads]
    mov esi,dword ptr [rip+l2_share_threads]
    mov edx,dword ptr [rip+l3_share_threads]
    call silicon_domain_probe
    mov eax,dword ptr [rip+sd_allowed_cpu_count]
    mov dword ptr [rip+allowed_cpu_count],eax
    mov eax,dword ptr [rip+sd_current_cpu]
    mov dword ptr [rip+current_cpu],eax
    mov eax,dword ptr [rip+sd_current_numa_node]
    mov dword ptr [rip+current_numa_node],eax
    mov eax,dword ptr [rip+sd_execution_admission_capacity]
    test eax,eax
    jnz .target_width_store
    mov eax,1
.target_width_store:
    mov dword ptr [rip+execution_admission_capacity],eax
    call select_silicon_profile
    call load_outward_materialization_ticks

    cmp r14, 2
    jl usage_error

    mov rdi, [r13+8]               # argv[1]
    lea rsi, [rip+opt_probe]
    call streq
    test eax, eax
    jnz mode_probe

    mov rdi, [r13+8]
    lea rsi, [rip+opt_isa_capabilities]
    call streq
    test eax, eax
    jnz mode_isa_capabilities

    mov rdi, [r13+8]
    lea rsi, [rip+opt_silicon_audit]
    call streq
    test eax, eax
    jnz mode_silicon_audit

    mov rdi, [r13+8]
    lea rsi, [rip+opt_silicon_contract]
    call streq
    test eax, eax
    jnz mode_silicon_contract

    mov rdi, [r13+8]
    lea rsi, [rip+opt_strict_silicon]
    call streq
    test eax, eax
    jnz mode_strict_silicon

    mov rdi, [r13+8]
    lea rsi, [rip+opt_schedule]
    call streq
    test eax, eax
    jnz mode_resource_schedule

    cmp r14, 4
    jl usage_error

    # topologyc input.wh -o output [--isa-limit native|avx512f|avx512dq|avx2]
    mov rdi, [r13+16]
    lea rsi, [rip+opt_o]
    call streq
    test eax, eax
    jz usage_error
    # Target parallel width was proven once from the immutable affinity mask.
    # Compilation never accepts a user worker-count override.
    mov dword ptr [rip+isa_limit_mode], 0
    mov ebx,4                       # optional argv index
.compile_opt_loop:
    cmp rbx,r14
    jae .compile_args_done
    lea rax,[rbx+1]
    cmp rax,r14
    jae usage_error
    mov rdi,[r13+rbx*8]
    lea rsi,[rip+opt_isa_limit]
    call streq
    test eax,eax
    jz usage_error
    mov rdi,[r13+rbx*8+8]
    call parse_isa_limit_cstr
    test edx,edx
    jnz usage_error
    mov dword ptr [rip+isa_limit_mode],eax
    add rbx,2
    jmp .compile_opt_loop
.compile_args_done:
    call apply_isa_limit
    mov r12, [r13+8]               # input path
    mov r14, [r13+24]              # output path
    mov dword ptr [rip+last_scan_path], 0

    # Open input.
    mov eax, SYS_openat
    mov edi, AT_FDCWD
    mov rsi, r12
    xor edx, edx
    xor r10d, r10d
    syscall
    test rax, rax
    js input_error
    mov r10, rax                    # input fd
    mov [rip+input_fd], r10

    # Discover regular-file length before the first source page is touched.
    mov eax, SYS_lseek
    mov rdi, r10
    xor esi, esi
    mov edx, SEEK_END
    syscall
    test rax, rax
    js input_error_close
    mov [rip+source_length], rax
    mov eax, SYS_lseek
    mov rdi, r10
    xor esi, esi
    mov edx, SEEK_SET
    syscall
    test rax, rax
    js input_error_close

    # Memory topology is chosen before read/first-touch.
    call prepare_source_memory
    test eax, eax
    jnz input_error_close
    mov r10, [rip+input_fd]

    # Read the exact source length; short reads are not silently accepted.
    mov rdi, r10
    mov rsi, [rip+source_ptr]
    mov rdx, [rip+source_length]
    call read_full
    test eax, eax
    jnz input_error_close

    mov r9, [rip+source_length]
    mov r8, [rip+source_ptr]
    mov byte ptr [r8+r9], 0

    mov eax, SYS_close
    mov rdi, r10
    syscall

    # Human WH/WHEX is lowered inside this same handwritten assembly process.
    # Canonical JSON enters the established sovereign frontends unchanged.
    mov r8,[rip+source_ptr]
    mov r9,[rip+source_length]
    xor ecx,ecx
.surface_probe_ws:
    cmp rcx,r9
    jae structured_compile_error
    mov al,[r8+rcx]
    cmp al,' '; je .surface_probe_next
    cmp al,9; je .surface_probe_next
    cmp al,10; je .surface_probe_next
    cmp al,13; je .surface_probe_next
    cmp al,'{'
    je .surface_canonical_ready
    mov rdi,r12
    call surface_lower_to_json
    test eax,eax
    jnz structured_compile_error
    jmp .surface_canonical_ready
.surface_probe_next:
    inc rcx
    jmp .surface_probe_ws
.surface_canonical_ready:

    # Compile-lane authority is explicit before lowering.  Unrecovered .wh
    # programs carry a transport-only wheelchair.general/1 marker and enter the
    # sovereign general frontend exactly once.  GTR/WHEX topology graphs carry
    # no such marker and a wheelchair.tensor/1 graph enters the tensor frontend
    # exactly once.  There is no failure-driven cross-lane fallback.
    mov rdi, [rip+source_ptr]
    mov rsi, [rip+source_length]
    lea rdx, [rip+general_lane_marker]
    mov ecx, general_lane_marker_end-general_lane_marker
    call memfind_scalar
    test rax,rax
    jnz .route_general_direct
    jmp .route_tensor_format

.route_general_direct:
    mov rdi,r14
    call compile_general_source
    test eax,eax
    jz .general_compile_ok
    cmp eax,3
    je general_executor_width_error
    jmp structured_compile_error

.route_tensor_format:
    mov rdi, [rip+source_ptr]
    mov rsi, [rip+source_length]
    lea rdx, [rip+tensor_fmt_marker]
    mov ecx, tensor_fmt_marker_end-tensor_fmt_marker
    call memfind_scalar
    test rax, rax
    jz .seed_scalar_path

    mov rdi,r14
    call compile_tensor_source
    test eax,eax
    jz .tensor_compile_ok
    jmp structured_compile_error
.tensor_compile_ok:
    call human_shell_report_success
    test eax,eax
    jnz .compile_success_exit
    lea rdi, [rip+msg_tensor_ok]
    mov esi, msg_tensor_ok_end-msg_tensor_ok
    call print_stdout
.compile_success_exit:
    xor edi, edi
    jmp exit_group
.general_compile_ok:
    call human_shell_report_success
    test eax,eax
    jnz .compile_success_exit
    lea rdi,[rip+msg_general_ok]
    mov esi,msg_general_ok_end-msg_general_ok
    call print_stdout
    jmp .compile_success_exit
.seed_scalar_path:
    call find_seed_fields
    mov rax, [rip+fmt_result]
    test rax, rax
    jz format_error
    mov rax, [rip+exit_result]
    test rax, rax
    jz parse_error

    # rax points to first byte after token.
    mov rdi, rax
    mov r8, [rip+source_ptr]
    mov r9, [rip+source_length]
    lea rsi, [r8+r9]
    call parse_colon_u8
    test edx, edx                   # error flag
    jnz parse_error
    mov ebx, eax                    # requested exit code

    # Copy the fixed minimal ELF image into output_buffer.
    lea rsi, [rip+elf_template]
    lea rdi, [rip+output_buffer]
    mov ecx, elf_template_end-elf_template
    rep movsb

    # Patch imm32 of "mov edi, imm32".
    lea rax, [rip+output_buffer]
    mov dword ptr [rax+ELF_CODE_OFF+1], ebx

    # Open output with 0755.
    mov eax, SYS_openat
    mov edi, AT_FDCWD
    mov rsi, r14
    mov edx, OUT_FLAGS
    mov r10d, 0755
    syscall
    test rax, rax
    js output_error
    mov r10, rax

    mov eax, SYS_write
    mov rdi, r10
    lea rsi, [rip+output_buffer]
    mov edx, elf_template_end-elf_template
    syscall
    cmp rax, elf_template_end-elf_template
    jne output_error_close

    mov eax, SYS_fchmod
    mov rdi, r10
    mov esi, 0755
    syscall

    mov eax, SYS_close
    mov rdi, r10
    syscall

    lea rdi, [rip+msg_ok]
    mov esi, msg_ok_end-msg_ok
    call print_stdout
    call print_scan_mode
    call print_compile_topology
    call print_source_memory_policy
    xor edi, edi
    jmp exit_group

mode_probe:
    lea rdi, [rip+probe_prefix]
    mov esi, probe_prefix_end-probe_prefix
    call print_stdout
    lea rdi, [rip+vendor_string]
    mov esi, 12
    call print_stdout
    lea rdi, [rip+newline]
    mov esi, 1
    call print_stdout

    # Print coarse feature classes using only baseline code.
    mov eax, dword ptr [rip+feature_bits]
    bt eax, 0                       # AVX usable
    jnc 1f
    lea rdi, [rip+msg_avx]
    mov esi, msg_avx_end-msg_avx
    call print_stdout
1:
    mov eax, dword ptr [rip+feature_bits]
    bt eax, 1                       # AVX2
    jnc 2f
    lea rdi, [rip+msg_avx2]
    mov esi, msg_avx2_end-msg_avx2
    call print_stdout
2:
    mov eax, dword ptr [rip+feature_bits]
    bt eax, 2                       # FMA
    jnc 3f
    lea rdi, [rip+msg_fma]
    mov esi, msg_fma_end-msg_fma
    call print_stdout
3:
    mov eax, dword ptr [rip+feature_bits]
    bt eax, 3                       # AVX-512 state+F
    jnc 4f
    lea rdi, [rip+msg_avx512]
    mov esi, msg_avx512_end-msg_avx512
    call print_stdout
    mov eax, dword ptr [rip+feature_bits]
    bt eax, 4
    jnc 4f
    lea rdi, [rip+msg_avx512bw]
    mov esi, msg_avx512bw_end-msg_avx512bw
    call print_stdout
4:
    xor edi, edi
    jmp exit_group



mode_isa_capabilities:
    lea rdi,[rip+msg_isa_caps_header]
    mov esi,msg_isa_caps_header_end-msg_isa_caps_header
    call print_stdout
    mov ebx,dword ptr [rip+isa_cap_bits]
    bt ebx,0; jnc .mic_no_256fp
    lea rdi,[rip+msg_cap_vec256fp]; mov esi,msg_cap_vec256fp_end-msg_cap_vec256fp; call print_stdout
.mic_no_256fp:
    bt ebx,1; jnc .mic_no_256int
    lea rdi,[rip+msg_cap_vec256int]; mov esi,msg_cap_vec256int_end-msg_cap_vec256int; call print_stdout
.mic_no_256int:
    bt ebx,2; jnc .mic_no_512
    lea rdi,[rip+msg_cap_vec512]; mov esi,msg_cap_vec512_end-msg_cap_vec512; call print_stdout
.mic_no_512:
    bt ebx,3; jnc .mic_no_pred
    lea rdi,[rip+msg_cap_predicate]; mov esi,msg_cap_predicate_end-msg_cap_predicate; call print_stdout
.mic_no_pred:
    bt ebx,4; jnc .mic_no_tail
    lea rdi,[rip+msg_cap_masktail]; mov esi,msg_cap_masktail_end-msg_cap_masktail; call print_stdout
.mic_no_tail:
    bt ebx,6; jnc .mic_no_bcast
    lea rdi,[rip+msg_cap_embcast]; mov esi,msg_cap_embcast_end-msg_cap_embcast; call print_stdout
.mic_no_bcast:
    bt ebx,9; jnc .mic_no_gather
    lea rdi,[rip+msg_cap_gather]; mov esi,msg_cap_gather_end-msg_cap_gather; call print_stdout
.mic_no_gather:
    bt ebx,11; jnc .mic_no_mul_native
    lea rdi,[rip+msg_cap_i64mul_native]; mov esi,msg_cap_i64mul_native_end-msg_cap_i64mul_native; call print_stdout
.mic_no_mul_native:
    bt ebx,12; jnc .mic_no_mul_synth
    lea rdi,[rip+msg_cap_i64mul_synth]; mov esi,msg_cap_i64mul_synth_end-msg_cap_i64mul_synth; call print_stdout
.mic_no_mul_synth:
    bt ebx,13; jnc .mic_no_i64fp_native
    lea rdi,[rip+msg_cap_i64fp]; mov esi,msg_cap_i64fp_end-msg_cap_i64fp; call print_stdout
.mic_no_i64fp_native:
    bt ebx,24; jnc .mic_no_i64fp_synth
    lea rdi,[rip+msg_cap_i64fp_synth]; mov esi,msg_cap_i64fp_synth_end-msg_cap_i64fp_synth; call print_stdout
.mic_no_i64fp_synth:
    bt ebx,25; jnc .mic_no_trunc_synth
    lea rdi,[rip+msg_cap_trunc_synth]; mov esi,msg_cap_trunc_synth_end-msg_cap_trunc_synth; call print_stdout
.mic_no_trunc_synth:
    bt ebx,22; jnc .mic_no_mask_native
    lea rdi,[rip+msg_cap_maski64_native]; mov esi,msg_cap_maski64_native_end-msg_cap_maski64_native; call print_stdout
.mic_no_mask_native:
    bt ebx,23; jnc .mic_no_mask_synth
    lea rdi,[rip+msg_cap_maski64_synth]; mov esi,msg_cap_maski64_synth_end-msg_cap_maski64_synth; call print_stdout
.mic_no_mask_synth:
    bt ebx,15; jnc .mic_no_vl
    lea rdi,[rip+msg_cap_vl]; mov esi,msg_cap_vl_end-msg_cap_vl; call print_stdout
.mic_no_vl:
    bt ebx,17; jnc .mic_no_bmi2
    lea rdi,[rip+msg_cap_bmi2]; mov esi,msg_cap_bmi2_end-msg_cap_bmi2; call print_stdout
.mic_no_bmi2:
    bt ebx,20; jnc .mic_no_cross
    lea rdi,[rip+msg_cap_crossstate]; mov esi,msg_cap_crossstate_end-msg_cap_crossstate; call print_stdout
.mic_no_cross:
    bt ebx,21; jnc .mic_done
    lea rdi,[rip+msg_cap_reduce]; mov esi,msg_cap_reduce_end-msg_cap_reduce; call print_stdout
.mic_done:
    xor edi,edi
    jmp exit_group

mode_resource_schedule:
    # topologyc --schedule FPADD FPMUL FPDIV FPCONV INTALU INTMUL INTDIV LOAD AGU BRANCH
    cmp r14, 12
    jne usage_error
    cmp dword ptr [rip+profile_status], 1
    jne strict_profile_error
    lea rbx, [rip+schedule_counts]
    mov r12d, 0
.mrs_parse:
    cmp r12d, 10
    jae .mrs_run
    mov rdi, [r13+16+r12*8]
    call parse_u32_cstr
    test edx, edx
    jnz parse_error
    mov dword ptr [rbx+r12*4], eax
    inc r12d
    jmp .mrs_parse
.mrs_run:
    call synthesize_resource_schedule
    call synthesize_group_fact
    call print_resource_schedule_json
    xor edi, edi
    jmp exit_group

mode_strict_silicon:
    cmp dword ptr [rip+profile_status], 1
    jne strict_profile_error
    lea rdi, [rip+msg_strict_ok]
    mov esi, msg_strict_ok_end-msg_strict_ok
    call print_stdout
    xor edi, edi
    jmp exit_group
strict_profile_error:
    lea rdi, [rip+msg_strict_reject]
    mov esi, msg_strict_reject_end-msg_strict_reject
    call print_stderr
    mov edi, 78
    jmp exit_group

mode_silicon_audit:
    call print_silicon_audit_json
    xor edi, edi
    jmp exit_group

mode_silicon_contract:
    call print_silicon_contract_json
    xor edi, edi
    jmp exit_group

usage_error:
    lea rdi, [rip+msg_usage]
    mov esi, msg_usage_end-msg_usage
    call print_stderr
    mov edi, 64
    jmp exit_group
source_too_large_close:
    mov eax, SYS_close
    mov rdi, [rip+input_fd]
    syscall
    lea rdi, [rip+msg_source_large]
    mov esi, msg_source_large_end-msg_source_large
    call print_stderr
    mov edi, 65
    jmp exit_group
input_error_close:
    mov eax, SYS_close
    mov rdi, [rip+input_fd]
    syscall
input_error:
    lea rdi, [rip+msg_input]
    mov esi, msg_input_end-msg_input
    call print_stderr
    mov edi, 66
    jmp exit_group
format_error:
    lea rdi, [rip+msg_format]
    mov esi, msg_format_end-msg_format
    call print_stderr
    mov edi, 65
    jmp exit_group
structured_compile_error:
    call human_shell_report_error
    test eax,eax
    jnz .structured_compile_error_exit
    lea rdi, [rip+msg_tensor_error]
    mov esi, msg_tensor_error_end-msg_tensor_error
    call print_stderr
.structured_compile_error_exit:
    mov edi, 65
    jmp exit_group
general_executor_width_error:
    call human_shell_report_error
    test eax,eax
    jnz .general_executor_width_error_exit
    lea rdi,[rip+msg_general_executor_error]
    mov esi,msg_general_executor_error_end-msg_general_executor_error
    call print_stderr
.general_executor_width_error_exit:
    mov edi,65
    jmp exit_group

parse_error:
    lea rdi, [rip+msg_parse]
    mov esi, msg_parse_end-msg_parse
    call print_stderr
    mov edi, 65
    jmp exit_group
output_error_close:
    mov eax, SYS_close
    mov rdi, r10
    syscall
output_error:
    lea rdi, [rip+msg_output]
    mov esi, msg_output_end-msg_output
    call print_stderr
    mov edi, 73
    jmp exit_group


# ---------------------------------------------------------------------------
# Initial process / physical-fabric discovery used by the compiler itself.
# ---------------------------------------------------------------------------
detect_auxv:
    # r15 points to initial stack. Walk argv, envp, then auxv to AT_PAGESZ=6.
    mov rax, [r15]
    lea rdx, [r15+16+rax*8]         # envp[0] (argc + argv[] + NULL)
.da_env:
    mov rcx, [rdx]
    add rdx, 8
    test rcx, rcx
    jne .da_env
.da_aux:
    mov rcx, [rdx]                  # a_type
    mov rax, [rdx+8]                # a_val
    add rdx, 16
    test rcx, rcx
    je .da_done
    cmp rcx, 6                      # AT_PAGESZ
    jne .da_aux
    mov [rip+page_size], rax
.da_done:
    ret

# Architectural silicon-domain hierarchy.  CPUID topology describes sharing
# domains, not geometric die coordinates; no unexposed adjacency is invented.
detect_cpu_topology:
    push rbx
    mov dword ptr [rip+topology_leaf],0
    mov dword ptr [rip+threads_per_core],1
    mov dword ptr [rip+logical_per_package],1
    mov dword ptr [rip+cores_per_package],1
    mov dword ptr [rip+x2apic_id],0
    mov r11d,0
    cmp dword ptr [rip+max_cpuid],0x1f
    jb .dctopo_try_b
    mov r11d,0x1f
    jmp .dctopo_have_leaf
.dctopo_try_b:
    cmp dword ptr [rip+max_cpuid],0x0b
    jb .dctopo_fallback
    mov r11d,0x0b
.dctopo_have_leaf:
    mov dword ptr [rip+topology_leaf],r11d
    xor r9d,r9d
.dctopo_loop:
    mov eax,r11d
    mov ecx,r9d
    cpuid
    mov dword ptr [rip+x2apic_id],edx
    mov r8d,ebx
    and r8d,0xffff
    test r8d,r8d
    jz .dctopo_finish
    mov r10d,ecx
    shr r10d,8
    and r10d,0xff
    cmp r10d,1
    jne .dctopo_core
    mov dword ptr [rip+threads_per_core],r8d
    jmp .dctopo_next
.dctopo_core:
    cmp r10d,2
    jne .dctopo_next
    mov dword ptr [rip+logical_per_package],r8d
.dctopo_next:
    inc r9d
    cmp r9d,8
    jb .dctopo_loop
    jmp .dctopo_finish
.dctopo_fallback:
    mov eax,1
    cpuid
    mov eax,ebx
    shr eax,16
    and eax,0xff
    test eax,eax
    jz .dctopo_finish
    mov dword ptr [rip+logical_per_package],eax
.dctopo_finish:
    mov eax,dword ptr [rip+logical_per_package]
    mov ecx,dword ptr [rip+threads_per_core]
    test ecx,ecx
    jnz .dctopo_div
    mov ecx,1
.dctopo_div:
    xor edx,edx
    div ecx
    test eax,eax
    jnz .dctopo_store_cores
    mov eax,1
.dctopo_store_cores:
    mov dword ptr [rip+cores_per_package],eax
    pop rbx
    ret

find_seed_fields:
    mov qword ptr [rip+fmt_result], 0
    mov qword ptr [rip+exit_result], 0
    mov r9, [rip+source_length]
    cmp r9, 128
    jb .fs_scalar
    mov eax, dword ptr [rip+feature_bits]
    cmp r9, 256
    jb .fs_try_avx2
    bt eax, 4
    jc find_seed_fields_avx512
.fs_try_avx2:
    bt eax, 1
    jc find_seed_fields_avx2
.fs_scalar:
    # Tiny input: startup/setup dominates, so keep the minimal scalar path.
    mov rdi, [rip+source_ptr]
    mov rsi, [rip+source_length]
    lea rdx, [rip+fmt_marker]
    mov ecx, fmt_marker_end-fmt_marker
    call memfind_scalar
    mov [rip+fmt_result], rax
    mov rdi, [rip+source_ptr]
    mov rsi, [rip+source_length]
    lea rdx, [rip+exit_key]
    mov ecx, exit_key_end-exit_key
    call memfind_scalar
    mov [rip+exit_result], rax
    mov dword ptr [rip+last_scan_path], 0
    ret

# bytes_equal(rdi=ptr, rsi=needle, edx=len) -> eax=1/0
bytes_equal:
    xor ecx, ecx
.be_loop:
    cmp ecx, edx
    je .be_yes
    mov al, byte ptr [rdi+rcx]
    cmp al, byte ptr [rsi+rcx]
    jne .be_no
    inc ecx
    jmp .be_loop
.be_yes:
    mov eax, 1
    ret
.be_no:
    xor eax, eax
    ret


find_seed_fields_avx512:
    mov dword ptr [rip+last_scan_path], 2
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r8, [rip+source_ptr]
    mov r9, [rip+source_length]
    mov r12, r9
    sub r12, fmt_marker_end-fmt_marker
    mov r15, r9
    sub r15, exit_key_end-exit_key
    xor ebx, ebx
    vpbroadcastb zmm0, byte ptr [rip+fmt_marker]
    vpbroadcastb zmm1, byte ptr [rip+exit_key]
    .p2align 6
.global silicon_hot_fused_scan_avx512
silicon_hot_fused_scan_avx512:
.f5_loop:
    lea rax, [rbx+64]
    cmp rax, r9
    ja .f5_tail
    vmovdqu8 zmm2, zmmword ptr [r8+rbx]
    cmp qword ptr [rip+fmt_result], 0
    jne .f5_after_fmt
    vpcmpeqb k1, zmm0, zmm2
    kmovq r13, k1
    test r13, r13
    jnz .f5_fmt_cold
.f5_after_fmt:
    cmp qword ptr [rip+exit_result], 0
    jne .f5_after_exit
    vpcmpeqb k2, zmm1, zmm2
    kmovq r13, k2
    test r13, r13
    jnz .f5_exit_cold
.f5_after_exit:
    cmp qword ptr [rip+fmt_result], 0
    je .f5_next
    cmp qword ptr [rip+exit_result], 0
    jne .f5_done
.f5_next:
    add rbx, 64
    cmp rbx, r9
    jb .f5_loop
    jmp .f5_done
.global silicon_hot_fused_scan_avx512_end
silicon_hot_fused_scan_avx512_end:

.f5_tail:
    mov r14, r12
    cmp r15, r14
    cmova r14, r15
.f5_tail_loop:
    cmp rbx, r14
    ja .f5_done
    cmp qword ptr [rip+fmt_result], 0
    jne .f5_tail_exit
    cmp rbx, r12
    ja .f5_tail_exit
    mov al, byte ptr [r8+rbx]
    cmp al, byte ptr [rip+fmt_marker]
    jne .f5_tail_exit
    lea rdi, [r8+rbx]
    lea rsi, [rip+fmt_marker]
    mov edx, fmt_marker_end-fmt_marker
    call bytes_equal
    test eax, eax
    jz .f5_tail_exit
    lea rax, [r8+rbx+fmt_marker_end-fmt_marker]
    mov [rip+fmt_result], rax
.f5_tail_exit:
    cmp qword ptr [rip+exit_result], 0
    jne .f5_tail_next
    cmp rbx, r15
    ja .f5_tail_next
    mov al, byte ptr [r8+rbx]
    cmp al, byte ptr [rip+exit_key]
    jne .f5_tail_next
    lea rdi, [r8+rbx]
    lea rsi, [rip+exit_key]
    mov edx, exit_key_end-exit_key
    call bytes_equal
    test eax, eax
    jz .f5_tail_next
    lea rax, [r8+rbx+exit_key_end-exit_key]
    mov [rip+exit_result], rax
.f5_tail_next:
    inc rbx
    jmp .f5_tail_loop
.f5_done:
    vzeroupper
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

    # Cold candidate verification is intentionally out of the fetch-critical loop.
.f5_fmt_cold:
.f5_fmt_candidates:
    test r13, r13
    jz .f5_after_fmt
    bsf rcx, r13
    btr r13, rcx
    lea r14, [rbx+rcx]
    cmp r14, r12
    ja .f5_fmt_candidates
    lea rdi, [r8+r14]
    lea rsi, [rip+fmt_marker]
    mov edx, fmt_marker_end-fmt_marker
    call bytes_equal
    test eax, eax
    jz .f5_fmt_candidates
    lea rax, [r8+r14+fmt_marker_end-fmt_marker]
    mov [rip+fmt_result], rax
    jmp .f5_after_fmt
.f5_exit_cold:
.f5_exit_candidates:
    test r13, r13
    jz .f5_after_exit
    bsf rcx, r13
    btr r13, rcx
    lea r14, [rbx+rcx]
    cmp r14, r15
    ja .f5_exit_candidates
    lea rdi, [r8+r14]
    lea rsi, [rip+exit_key]
    mov edx, exit_key_end-exit_key
    call bytes_equal
    test eax, eax
    jz .f5_exit_candidates
    lea rax, [r8+r14+exit_key_end-exit_key]
    mov [rip+exit_result], rax
    jmp .f5_after_exit

find_seed_fields_avx2:
    mov dword ptr [rip+last_scan_path], 1
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r8, [rip+source_ptr]
    mov r9, [rip+source_length]
    mov r12, r9
    sub r12, fmt_marker_end-fmt_marker
    mov r15, r9
    sub r15, exit_key_end-exit_key
    xor ebx, ebx
    vpbroadcastb ymm0, byte ptr [rip+fmt_marker]
    vpbroadcastb ymm1, byte ptr [rip+exit_key]
    .p2align 5
.global silicon_hot_fused_scan_avx2
silicon_hot_fused_scan_avx2:
.f2_loop:
    lea rax, [rbx+32]
    cmp rax, r9
    ja .f2_tail
    vmovdqu ymm2, ymmword ptr [r8+rbx]
    cmp qword ptr [rip+fmt_result], 0
    jne .f2_after_fmt
    vpcmpeqb ymm3, ymm0, ymm2
    vpmovmskb r13d, ymm3
    test r13d, r13d
    jnz .f2_fmt_cold
.f2_after_fmt:
    cmp qword ptr [rip+exit_result], 0
    jne .f2_after_exit
    vpcmpeqb ymm3, ymm1, ymm2
    vpmovmskb r13d, ymm3
    test r13d, r13d
    jnz .f2_exit_cold
.f2_after_exit:
    cmp qword ptr [rip+fmt_result], 0
    je .f2_next
    cmp qword ptr [rip+exit_result], 0
    jne .f2_done
.f2_next:
    add rbx, 32
    cmp rbx, r9
    jb .f2_loop
    jmp .f2_done
.global silicon_hot_fused_scan_avx2_end
silicon_hot_fused_scan_avx2_end:

.f2_tail:
    mov r14, r12
    cmp r15, r14
    cmova r14, r15
.f2_tail_loop:
    cmp rbx, r14
    ja .f2_done
    cmp qword ptr [rip+fmt_result], 0
    jne .f2_tail_exit
    cmp rbx, r12
    ja .f2_tail_exit
    mov al, byte ptr [r8+rbx]
    cmp al, byte ptr [rip+fmt_marker]
    jne .f2_tail_exit
    lea rdi, [r8+rbx]
    lea rsi, [rip+fmt_marker]
    mov edx, fmt_marker_end-fmt_marker
    call bytes_equal
    test eax, eax
    jz .f2_tail_exit
    lea rax, [r8+rbx+fmt_marker_end-fmt_marker]
    mov [rip+fmt_result], rax
.f2_tail_exit:
    cmp qword ptr [rip+exit_result], 0
    jne .f2_tail_next
    cmp rbx, r15
    ja .f2_tail_next
    mov al, byte ptr [r8+rbx]
    cmp al, byte ptr [rip+exit_key]
    jne .f2_tail_next
    lea rdi, [r8+rbx]
    lea rsi, [rip+exit_key]
    mov edx, exit_key_end-exit_key
    call bytes_equal
    test eax, eax
    jz .f2_tail_next
    lea rax, [r8+rbx+exit_key_end-exit_key]
    mov [rip+exit_result], rax
.f2_tail_next:
    inc rbx
    jmp .f2_tail_loop
.f2_done:
    vzeroupper
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.f2_fmt_cold:
.f2_fmt_candidates:
    test r13d, r13d
    jz .f2_after_fmt
    bsf ecx, r13d
    btr r13d, ecx
    lea r14, [rbx+rcx]
    cmp r14, r12
    ja .f2_fmt_candidates
    lea rdi, [r8+r14]
    lea rsi, [rip+fmt_marker]
    mov edx, fmt_marker_end-fmt_marker
    call bytes_equal
    test eax, eax
    jz .f2_fmt_candidates
    lea rax, [r8+r14+fmt_marker_end-fmt_marker]
    mov [rip+fmt_result], rax
    jmp .f2_after_fmt
.f2_exit_cold:
.f2_exit_candidates:
    test r13d, r13d
    jz .f2_after_exit
    bsf ecx, r13d
    btr r13d, ecx
    lea r14, [rbx+rcx]
    cmp r14, r15
    ja .f2_exit_candidates
    lea rdi, [r8+r14]
    lea rsi, [rip+exit_key]
    mov edx, exit_key_end-exit_key
    call bytes_equal
    test eax, eax
    jz .f2_exit_candidates
    lea rax, [r8+r14+exit_key_end-exit_key]
    mov [rip+exit_result], rax
    jmp .f2_after_exit


select_silicon_profile:
    # 1.3.85: one fact-derived x86-64 realization profile.  CPU vendor/family/model
    # are diagnostics only; they no longer select compiler behavior.  The profile
    # is synthesized from exposed ISA width, cache geometry and the actual fused
    # scan footprint already present in this compiler image.
    mov dword ptr [rip+profile_status], 0
    mov dword ptr [rip+hot_loop_alignment], 1
    mov dword ptr [rip+reduction_carriers], 1
    mov dword ptr [rip+fp_add_latency_ticks], PRC_FP_ADD_LATENCY_TICKS
    mov dword ptr [rip+front_end_budget], 1
    mov dword ptr [rip+simd_scan_width], 1
    mov dword ptr [rip+scan_loop_bytes], 0
    mov dword ptr [rip+scan_loads_per_block], 0
    mov dword ptr [rip+scan_vector_compares_per_block], 0
    mov dword ptr [rip+scan_vector_registers], 0
    mov dword ptr [rip+scan_mask_registers], 0
    mov dword ptr [rip+architectural_vector_registers], 1

    mov eax,dword ptr [rip+feature_bits]
    bt eax,4
    jnc .ssp_avx2
    mov dword ptr [rip+simd_scan_width],64
    mov dword ptr [rip+hot_loop_alignment],64
    mov dword ptr [rip+front_end_budget],64
    mov dword ptr [rip+architectural_vector_registers],32
    mov dword ptr [rip+scan_loop_bytes],silicon_hot_fused_scan_avx512_end-silicon_hot_fused_scan_avx512
    mov dword ptr [rip+scan_loads_per_block],1
    mov dword ptr [rip+scan_vector_compares_per_block],2
    mov dword ptr [rip+scan_vector_registers],3
    mov dword ptr [rip+scan_mask_registers],2
    jmp .ssp_derive
.ssp_avx2:
    bt eax,1
    jnc .ssp_scalar
    mov dword ptr [rip+simd_scan_width],32
    mov dword ptr [rip+hot_loop_alignment],32
    mov dword ptr [rip+front_end_budget],32
    mov dword ptr [rip+architectural_vector_registers],16
    mov dword ptr [rip+scan_loop_bytes],silicon_hot_fused_scan_avx2_end-silicon_hot_fused_scan_avx2
    mov dword ptr [rip+scan_loads_per_block],1
    mov dword ptr [rip+scan_vector_compares_per_block],2
    mov dword ptr [rip+scan_vector_registers],4
    mov dword ptr [rip+scan_mask_registers],0
    jmp .ssp_derive
.ssp_scalar:
    mov eax,dword ptr [rip+cache_line_bytes]
    test eax,eax
    jz .ssp_done
    mov dword ptr [rip+hot_loop_alignment],eax
.ssp_derive:
    # Recurrence-carrier capacity is derived from the architectural carrier bank
    # and the already-measured live hot-scan state.  This preserves the mature
    # 6-carrier AVX-512 and 4-carrier AVX2 realization on the release host without
    # a vendor/model table.  The value is a target fact, not a workload route.
    mov ecx,dword ptr [rip+scan_vector_registers]
    add ecx,dword ptr [rip+scan_mask_registers]
    test ecx,ecx
    jz .ssp_profile_ready
    mov eax,dword ptr [rip+architectural_vector_registers]
    xor edx,edx
    div ecx
    test eax,eax
    jnz .ssp_store_carriers
    mov eax,1
.ssp_store_carriers:
    mov dword ptr [rip+reduction_carriers],eax
.ssp_profile_ready:
    mov eax,dword ptr [rip+cache_line_bytes]
    test eax,eax
    jz .ssp_done
    mov eax,dword ptr [rip+simd_scan_width]
    test eax,eax
    jz .ssp_done
    mov dword ptr [rip+profile_status],1
.ssp_done:
    ret


prepare_source_memory:
    mov dword ptr [rip+numa_bind_ok], 0
    mov dword ptr [rip+hugepage_advice_ok], 0
    mov dword ptr [rip+source_dynamic], 0
    mov qword ptr [rip+source_alloc_size], STATIC_SOURCE_CAP
    mov rax, [rip+source_length]
    inc rax
    cmp rax, STATIC_SOURCE_CAP
    ja .psm_dynamic
    lea rcx, [rip+source_buffer]
    mov [rip+source_ptr], rcx
    jmp .psm_bind

.psm_dynamic:
    # Round allocation. Large source regions use 2 MiB geometry to make THP
    # physically possible; medium sources use the actual kernel page size.
    mov r8, [rip+page_size]
    test r8, r8
    jnz .psm_have_page
    mov r8, 4096
.psm_have_page:
    mov r9, r8
    cmp rax, HUGE_THRESHOLD
    jb .psm_round
    mov r9, 2097152
.psm_round:
    lea rdx, [rax+r9-1]
    mov rax, r9
    dec rax
    not rax
    and rdx, rax
    mov [rip+source_alloc_size], rdx

    mov eax, SYS_mmap
    xor edi, edi
    mov rsi, rdx
    mov edx, PROT_RW
    mov r10d, MAP_PRIVATE_ANON
    mov r8d, -1
    xor r9d, r9d
    syscall
    test rax, rax
    js .psm_fail
    mov [rip+source_ptr], rax
    mov dword ptr [rip+source_dynamic], 1

    cmp qword ptr [rip+source_length], HUGE_THRESHOLD
    jb .psm_bind
    mov rdi, rax
    mov rsi, [rip+source_alloc_size]
    mov eax, SYS_madvise
    mov edx, MADV_HUGEPAGE
    syscall
    test rax, rax
    js .psm_bind
    mov dword ptr [rip+hugepage_advice_ok], 1

.psm_bind:
    # Bind before read so the read syscall's first touches obey the chosen node
    # when Linux permits mbind. Otherwise first-touch locality remains the safe
    # fallback and is reported as such.
    mov eax, dword ptr [rip+current_numa_node]
    cmp eax, 63
    ja .psm_done
    mov ecx, eax
    mov rax, 1
    shl rax, cl
    mov [rip+numa_nodemask], rax
    mov eax, SYS_mbind
    mov rdi, [rip+source_ptr]
    mov rsi, [rip+source_alloc_size]
    mov edx, MPOL_BIND
    lea r10, [rip+numa_nodemask]
    mov r8d, 64
    xor r9d, r9d
    syscall
    test rax, rax
    js .psm_done
    mov dword ptr [rip+numa_bind_ok], 1
.psm_done:
    xor eax, eax
    ret
.psm_fail:
    mov eax, 1
    ret

read_full:
    # rdi=fd, rsi=buffer, rdx=exact byte count. eax=0 success, 1 failure.
    mov r8, rdi
    mov r9, rsi
    mov r10, rdx
.rf_loop:
    test r10, r10
    jz .rf_ok
    mov eax, SYS_read
    mov rdi, r8
    mov rsi, r9
    mov rdx, r10
    syscall
    test rax, rax
    jle .rf_bad
    add r9, rax
    sub r10, rax
    jmp .rf_loop
.rf_ok:
    xor eax, eax
    ret
.rf_bad:
    mov eax, 1
    ret

print_source_memory_policy:
    cmp dword ptr [rip+source_dynamic], 0
    je .psmp_static
    cmp dword ptr [rip+hugepage_advice_ok], 0
    je .psmp_dynamic_base
    lea rdi, [rip+msg_mem_dynamic_huge]
    mov esi, msg_mem_dynamic_huge_end-msg_mem_dynamic_huge
    call print_stdout
    jmp .psmp_numa
.psmp_dynamic_base:
    lea rdi, [rip+msg_mem_dynamic_base]
    mov esi, msg_mem_dynamic_base_end-msg_mem_dynamic_base
    call print_stdout
    jmp .psmp_numa
.psmp_static:
    lea rdi, [rip+msg_mem_static]
    mov esi, msg_mem_static_end-msg_mem_static
    call print_stdout
.psmp_numa:
    cmp dword ptr [rip+numa_bind_ok], 0
    je .psmp_firsttouch
    lea rdi, [rip+msg_mem_numa_bind]
    mov esi, msg_mem_numa_bind_end-msg_mem_numa_bind
    jmp print_stdout
.psmp_firsttouch:
    lea rdi, [rip+msg_mem_firsttouch]
    mov esi, msg_mem_firsttouch_end-msg_mem_firsttouch
    jmp print_stdout


print_scan_mode:
    mov eax, dword ptr [rip+last_scan_path]
    cmp eax, 2
    je .psm_a5
    cmp eax, 1
    je .psm_a2
    lea rdi, [rip+msg_scan_scalar]
    mov esi, msg_scan_scalar_end-msg_scan_scalar
    jmp print_stdout
.psm_a2:
    lea rdi, [rip+msg_scan_avx2]
    mov esi, msg_scan_avx2_end-msg_scan_avx2
    jmp print_stdout
.psm_a5:
    lea rdi, [rip+msg_scan_avx512]
    mov esi, msg_scan_avx512_end-msg_scan_avx512
    jmp print_stdout


print_compile_topology:
    lea rdi, [rip+msg_compile_single]
    mov esi, msg_compile_single_end-msg_compile_single
    jmp print_stdout

# print unsigned 64-bit integer in rdi to stdout.
print_u64_stdout:
    sub rsp, 40
    lea r8, [rsp+39]
    mov byte ptr [r8], 0
    mov rax, rdi
    mov r9, 10
    xor ecx, ecx
    test rax, rax
    jne .pu_loop
    dec r8
    mov byte ptr [r8], '0'
    mov ecx, 1
    jmp .pu_emit
.pu_loop:
    xor edx, edx
    div r9
    add dl, '0'
    dec r8
    mov byte ptr [r8], dl
    inc ecx
    test rax, rax
    jne .pu_loop
.pu_emit:
    mov eax, SYS_write
    mov edi, 1
    mov rsi, r8
    mov edx, ecx
    syscall
    add rsp, 40
    ret

print_json_num_field:
    # rdi=prefix ptr, esi=prefix len, rdx=value
    push rdx
    call print_stdout
    pop rdi
    call print_u64_stdout
    ret

print_silicon_audit_json:
    lea rdi, [rip+audit_head]
    mov esi, audit_head_end-audit_head
    call print_stdout
    lea rdi, [rip+vendor_string]
    mov esi, 12
    call print_stdout

    lea rdi, [rip+audit_family]
    mov esi, audit_family_end-audit_family
    mov edx, dword ptr [rip+cpu_family]
    call print_json_num_field
    lea rdi, [rip+audit_model]
    mov esi, audit_model_end-audit_model
    mov edx, dword ptr [rip+cpu_model]
    call print_json_num_field
    lea rdi, [rip+audit_stepping]
    mov esi, audit_stepping_end-audit_stepping
    mov edx, dword ptr [rip+cpu_stepping]
    call print_json_num_field
    lea rdi, [rip+audit_allowed]
    mov esi, audit_allowed_end-audit_allowed
    mov edx, dword ptr [rip+allowed_cpu_count]
    call print_json_num_field
    lea rdi,[rip+audit_cpu_quota_usec]
    mov esi,audit_cpu_quota_usec_end-audit_cpu_quota_usec
    mov rdx,qword ptr [rip+sd_cpu_quota_usec]
    call print_json_num_field
    lea rdi,[rip+audit_cpu_period_usec]
    mov esi,audit_cpu_period_usec_end-audit_cpu_period_usec
    mov rdx,qword ptr [rip+sd_cpu_period_usec]
    call print_json_num_field
    lea rdi,[rip+audit_execution_admission]
    mov esi,audit_execution_admission_end-audit_execution_admission
    mov edx,dword ptr [rip+execution_admission_capacity]
    call print_json_num_field
    lea rdi, [rip+audit_current_cpu]
    mov esi, audit_current_cpu_end-audit_current_cpu
    mov edx, dword ptr [rip+current_cpu]
    call print_json_num_field
    lea rdi, [rip+audit_numa]
    mov esi, audit_numa_end-audit_numa
    mov edx, dword ptr [rip+current_numa_node]
    call print_json_num_field
    lea rdi, [rip+audit_page]
    mov esi, audit_page_end-audit_page
    mov rdx, [rip+page_size]
    call print_json_num_field
    lea rdi, [rip+audit_cacheline]
    mov esi, audit_cacheline_end-audit_cacheline
    mov edx, dword ptr [rip+cache_line_bytes]
    call print_json_num_field
    lea rdi, [rip+audit_l1d]
    mov esi, audit_l1d_end-audit_l1d
    mov rdx, [rip+l1d_bytes]
    call print_json_num_field
    lea rdi, [rip+audit_l1i]
    mov esi, audit_l1i_end-audit_l1i
    mov rdx, [rip+l1i_bytes]
    call print_json_num_field
    lea rdi, [rip+audit_l2]
    mov esi, audit_l2_end-audit_l2
    mov rdx, [rip+l2_bytes]
    call print_json_num_field
    lea rdi, [rip+audit_l3]
    mov esi, audit_l3_end-audit_l3
    mov rdx, [rip+l3_bytes]
    call print_json_num_field
    lea rdi,[rip+audit_threads_per_core]
    mov esi,audit_threads_per_core_end-audit_threads_per_core
    mov edx,dword ptr [rip+threads_per_core]
    call print_json_num_field
    lea rdi,[rip+audit_cores_per_package]
    mov esi,audit_cores_per_package_end-audit_cores_per_package
    mov edx,dword ptr [rip+cores_per_package]
    call print_json_num_field
    lea rdi,[rip+audit_logical_per_package]
    mov esi,audit_logical_per_package_end-audit_logical_per_package
    mov edx,dword ptr [rip+logical_per_package]
    call print_json_num_field
    lea rdi,[rip+audit_l1d_share]
    mov esi,audit_l1d_share_end-audit_l1d_share
    mov edx,dword ptr [rip+l1d_share_threads]
    call print_json_num_field
    lea rdi,[rip+audit_l2_share]
    mov esi,audit_l2_share_end-audit_l2_share
    mov edx,dword ptr [rip+l2_share_threads]
    call print_json_num_field
    lea rdi,[rip+audit_l3_share]
    mov esi,audit_l3_share_end-audit_l3_share
    mov edx,dword ptr [rip+l3_share_threads]
    call print_json_num_field
    lea rdi,[rip+audit_domain_identity_exact]
    mov esi,audit_domain_identity_exact_end-audit_domain_identity_exact
    mov edx,dword ptr [rip+sd_domain_identity_exact]
    call print_json_num_field
    lea rdi,[rip+audit_l1d_domain_count]
    mov esi,audit_l1d_domain_count_end-audit_l1d_domain_count
    mov edx,dword ptr [rip+sd_l1d_domain_count]
    call print_json_num_field
    lea rdi,[rip+audit_l1d_domain_max]
    mov esi,audit_l1d_domain_max_end-audit_l1d_domain_max
    mov edx,dword ptr [rip+sd_l1d_domain_max]
    call print_json_num_field
    lea rdi,[rip+audit_l2_domain_count]
    mov esi,audit_l2_domain_count_end-audit_l2_domain_count
    mov edx,dword ptr [rip+sd_l2_domain_count]
    call print_json_num_field
    lea rdi,[rip+audit_l2_domain_max]
    mov esi,audit_l2_domain_max_end-audit_l2_domain_max
    mov edx,dword ptr [rip+sd_l2_domain_max]
    call print_json_num_field
    lea rdi,[rip+audit_l3_domain_count]
    mov esi,audit_l3_domain_count_end-audit_l3_domain_count
    mov edx,dword ptr [rip+sd_l3_domain_count]
    call print_json_num_field
    lea rdi,[rip+audit_l3_domain_max]
    mov esi,audit_l3_domain_max_end-audit_l3_domain_max
    mov edx,dword ptr [rip+sd_l3_domain_max]
    call print_json_num_field
    lea rdi,[rip+audit_static_placement_exact]
    mov esi,audit_static_placement_exact_end-audit_static_placement_exact
    mov edx,dword ptr [rip+sd_static_placement_exact]
    call print_json_num_field
    lea rdi,[rip+audit_static_placement_required]
    mov esi,audit_static_placement_required_end-audit_static_placement_required
    mov edx,dword ptr [rip+sd_static_placement_required]
    call print_json_num_field
    lea rdi,[rip+audit_preferred_l3_contexts]
    mov esi,audit_preferred_l3_contexts_end-audit_preferred_l3_contexts
    mov edx,dword ptr [rip+sd_preferred_l3_cpu_count]
    call print_json_num_field

    call fabric_target_facts_proved
    mov edx,eax
    lea rdi,[rip+audit_fabric_proved]
    mov esi,audit_fabric_proved_end-audit_fabric_proved
    call print_json_num_field
    lea rdi,[rip+audit_fabric_logic]
    mov esi,audit_fabric_logic_end-audit_fabric_logic
    mov rdx,qword ptr [rip+ft_logic_units]
    call print_json_num_field
    lea rdi,[rip+audit_fabric_registers]
    mov esi,audit_fabric_registers_end-audit_fabric_registers
    mov rdx,qword ptr [rip+ft_register_units]
    call print_json_num_field
    lea rdi,[rip+audit_fabric_dsp]
    mov esi,audit_fabric_dsp_end-audit_fabric_dsp
    mov rdx,qword ptr [rip+ft_dsp_units]
    call print_json_num_field
    lea rdi,[rip+audit_fabric_storage]
    mov esi,audit_fabric_storage_end-audit_fabric_storage
    mov rdx,qword ptr [rip+ft_local_storage_bytes]
    call print_json_num_field
    lea rdi,[rip+audit_fabric_routes]
    mov esi,audit_fabric_routes_end-audit_fabric_routes
    mov edx,dword ptr [rip+ft_routing_domains]
    call print_json_num_field
    lea rdi,[rip+audit_fabric_clocks]
    mov esi,audit_fabric_clocks_end-audit_fabric_clocks
    mov edx,dword ptr [rip+ft_clock_regions]
    call print_json_num_field
    lea rdi, [rip+audit_simd]
    mov esi, audit_simd_end-audit_simd
    mov edx, dword ptr [rip+simd_scan_width]
    call print_json_num_field
    lea rdi, [rip+audit_align]
    mov esi, audit_align_end-audit_align
    mov edx, dword ptr [rip+hot_loop_alignment]
    call print_json_num_field
    lea rdi, [rip+audit_carriers]
    mov esi, audit_carriers_end-audit_carriers
    mov edx, dword ptr [rip+reduction_carriers]
    call print_json_num_field
    lea rdi, [rip+audit_scan_loop]
    mov esi, audit_scan_loop_end-audit_scan_loop
    mov edx, dword ptr [rip+scan_loop_bytes]
    call print_json_num_field
    lea rdi, [rip+audit_scan_loads]
    mov esi, audit_scan_loads_end-audit_scan_loads
    mov edx, dword ptr [rip+scan_loads_per_block]
    call print_json_num_field
    lea rdi, [rip+audit_scan_cmps]
    mov esi, audit_scan_cmps_end-audit_scan_cmps
    mov edx, dword ptr [rip+scan_vector_compares_per_block]
    call print_json_num_field
    lea rdi, [rip+audit_scan_vregs]
    mov esi, audit_scan_vregs_end-audit_scan_vregs
    mov edx, dword ptr [rip+scan_vector_registers]
    call print_json_num_field
    lea rdi, [rip+audit_scan_kregs]
    mov esi, audit_scan_kregs_end-audit_scan_kregs
    mov edx, dword ptr [rip+scan_mask_registers]
    call print_json_num_field

    lea rdi, [rip+audit_profile_prefix]
    mov esi, audit_profile_prefix_end-audit_profile_prefix
    call print_stdout
    lea rdi,[rip+profile_fact_derived]
    mov esi,profile_fact_derived_end-profile_fact_derived
    call print_stdout
    lea rdi, [rip+audit_profile_status]
    mov esi, audit_profile_status_end-audit_profile_status
    call print_stdout
    cmp dword ptr [rip+profile_status], 1
    jne .psa_debt
    lea rdi, [rip+status_clean]
    mov esi, status_clean_end-status_clean
    call print_stdout
    jmp .psa_tail
.psa_debt:
    lea rdi, [rip+status_debt]
    mov esi, status_debt_end-status_debt
    call print_stdout
.psa_tail:
    lea rdi, [rip+audit_tail]
    mov esi, audit_tail_end-audit_tail
    call print_stdout
    ret


# Machine-readable target contract for the same Physical Reality authority.
# This is deliberately not a program IR: it contains target facts and structural
# laws only, so no second program graph can diverge from the compiler.
print_silicon_contract_json:
    lea rdi,[rip+contract_head]
    mov esi,contract_head_end-contract_head
    call print_stdout
    lea rdi,[rip+vendor_string]
    mov esi,12
    call print_stdout
    lea rdi,[rip+contract_family]
    mov esi,contract_family_end-contract_family
    mov edx,dword ptr [rip+cpu_family]
    call print_json_num_field
    lea rdi,[rip+contract_model]
    mov esi,contract_model_end-contract_model
    mov edx,dword ptr [rip+cpu_model]
    call print_json_num_field
    lea rdi,[rip+contract_allowed]
    mov esi,contract_allowed_end-contract_allowed
    mov edx,dword ptr [rip+allowed_cpu_count]
    call print_json_num_field
    lea rdi,[rip+contract_cpu_quota_usec]
    mov esi,contract_cpu_quota_usec_end-contract_cpu_quota_usec
    mov rdx,qword ptr [rip+sd_cpu_quota_usec]
    call print_json_num_field
    lea rdi,[rip+contract_cpu_period_usec]
    mov esi,contract_cpu_period_usec_end-contract_cpu_period_usec
    mov rdx,qword ptr [rip+sd_cpu_period_usec]
    call print_json_num_field
    lea rdi,[rip+contract_execution_admission]
    mov esi,contract_execution_admission_end-contract_execution_admission
    mov edx,dword ptr [rip+execution_admission_capacity]
    call print_json_num_field
    lea rdi,[rip+contract_cacheline]
    mov esi,contract_cacheline_end-contract_cacheline
    mov edx,dword ptr [rip+cache_line_bytes]
    call print_json_num_field
    lea rdi,[rip+contract_l1d]
    mov esi,contract_l1d_end-contract_l1d
    mov rdx,[rip+l1d_bytes]
    call print_json_num_field
    lea rdi,[rip+contract_l2]
    mov esi,contract_l2_end-contract_l2
    mov rdx,[rip+l2_bytes]
    call print_json_num_field
    lea rdi,[rip+contract_l3]
    mov esi,contract_l3_end-contract_l3
    mov rdx,[rip+l3_bytes]
    call print_json_num_field
    lea rdi,[rip+contract_threads_per_core]
    mov esi,contract_threads_per_core_end-contract_threads_per_core
    mov edx,dword ptr [rip+threads_per_core]
    call print_json_num_field
    lea rdi,[rip+contract_cores_per_package]
    mov esi,contract_cores_per_package_end-contract_cores_per_package
    mov edx,dword ptr [rip+cores_per_package]
    call print_json_num_field
    lea rdi,[rip+contract_logical_per_package]
    mov esi,contract_logical_per_package_end-contract_logical_per_package
    mov edx,dword ptr [rip+logical_per_package]
    call print_json_num_field
    lea rdi,[rip+contract_l1d_share]
    mov esi,contract_l1d_share_end-contract_l1d_share
    mov edx,dword ptr [rip+l1d_share_threads]
    call print_json_num_field
    lea rdi,[rip+contract_l2_share]
    mov esi,contract_l2_share_end-contract_l2_share
    mov edx,dword ptr [rip+l2_share_threads]
    call print_json_num_field
    lea rdi,[rip+contract_l3_share]
    mov esi,contract_l3_share_end-contract_l3_share
    mov edx,dword ptr [rip+l3_share_threads]
    call print_json_num_field
    lea rdi,[rip+contract_domain_identity_exact]
    mov esi,contract_domain_identity_exact_end-contract_domain_identity_exact
    mov edx,dword ptr [rip+sd_domain_identity_exact]
    call print_json_num_field
    lea rdi,[rip+contract_l1d_domain_count]
    mov esi,contract_l1d_domain_count_end-contract_l1d_domain_count
    mov edx,dword ptr [rip+sd_l1d_domain_count]
    call print_json_num_field
    lea rdi,[rip+contract_l1d_domain_max]
    mov esi,contract_l1d_domain_max_end-contract_l1d_domain_max
    mov edx,dword ptr [rip+sd_l1d_domain_max]
    call print_json_num_field
    lea rdi,[rip+contract_l2_domain_count]
    mov esi,contract_l2_domain_count_end-contract_l2_domain_count
    mov edx,dword ptr [rip+sd_l2_domain_count]
    call print_json_num_field
    lea rdi,[rip+contract_l2_domain_max]
    mov esi,contract_l2_domain_max_end-contract_l2_domain_max
    mov edx,dword ptr [rip+sd_l2_domain_max]
    call print_json_num_field
    lea rdi,[rip+contract_l3_domain_count]
    mov esi,contract_l3_domain_count_end-contract_l3_domain_count
    mov edx,dword ptr [rip+sd_l3_domain_count]
    call print_json_num_field
    lea rdi,[rip+contract_l3_domain_max]
    mov esi,contract_l3_domain_max_end-contract_l3_domain_max
    mov edx,dword ptr [rip+sd_l3_domain_max]
    call print_json_num_field
    lea rdi,[rip+contract_static_placement_exact]
    mov esi,contract_static_placement_exact_end-contract_static_placement_exact
    mov edx,dword ptr [rip+sd_static_placement_exact]
    call print_json_num_field
    lea rdi,[rip+contract_static_placement_required]
    mov esi,contract_static_placement_required_end-contract_static_placement_required
    mov edx,dword ptr [rip+sd_static_placement_required]
    call print_json_num_field
    lea rdi,[rip+contract_preferred_l3_contexts]
    mov esi,contract_preferred_l3_contexts_end-contract_preferred_l3_contexts
    mov edx,dword ptr [rip+sd_preferred_l3_cpu_count]
    call print_json_num_field

    call fabric_target_facts_proved
    mov edx,eax
    lea rdi,[rip+contract_fabric_proved]
    mov esi,contract_fabric_proved_end-contract_fabric_proved
    call print_json_num_field
    lea rdi,[rip+contract_fabric_logic]
    mov esi,contract_fabric_logic_end-contract_fabric_logic
    mov rdx,qword ptr [rip+ft_logic_units]
    call print_json_num_field
    lea rdi,[rip+contract_fabric_registers]
    mov esi,contract_fabric_registers_end-contract_fabric_registers
    mov rdx,qword ptr [rip+ft_register_units]
    call print_json_num_field
    lea rdi,[rip+contract_fabric_dsp]
    mov esi,contract_fabric_dsp_end-contract_fabric_dsp
    mov rdx,qword ptr [rip+ft_dsp_units]
    call print_json_num_field
    lea rdi,[rip+contract_fabric_storage]
    mov esi,contract_fabric_storage_end-contract_fabric_storage
    mov rdx,qword ptr [rip+ft_local_storage_bytes]
    call print_json_num_field
    lea rdi,[rip+contract_fabric_routes]
    mov esi,contract_fabric_routes_end-contract_fabric_routes
    mov edx,dword ptr [rip+ft_routing_domains]
    call print_json_num_field
    lea rdi,[rip+contract_fabric_clocks]
    mov esi,contract_fabric_clocks_end-contract_fabric_clocks
    mov edx,dword ptr [rip+ft_clock_regions]
    call print_json_num_field
    lea rdi,[rip+contract_fabric_compute_num]
    mov esi,contract_fabric_compute_num_end-contract_fabric_compute_num
    mov rdx,qword ptr [rip+ft_compute_ticks_num]
    call print_json_num_field
    lea rdi,[rip+contract_fabric_compute_den]
    mov esi,contract_fabric_compute_den_end-contract_fabric_compute_den
    mov rdx,qword ptr [rip+ft_compute_ticks_den]
    call print_json_num_field
    lea rdi,[rip+contract_fabric_activation]
    mov esi,contract_fabric_activation_end-contract_fabric_activation
    mov rdx,qword ptr [rip+ft_activation_ticks]
    call print_json_num_field
    lea rdi,[rip+contract_fabric_transport_fixed]
    mov esi,contract_fabric_transport_fixed_end-contract_fabric_transport_fixed
    mov rdx,qword ptr [rip+ft_transport_fixed_ticks]
    call print_json_num_field
    lea rdi,[rip+contract_fabric_transport_byte]
    mov esi,contract_fabric_transport_byte_end-contract_fabric_transport_byte
    mov rdx,qword ptr [rip+ft_transport_ticks_per_byte]
    call print_json_num_field
    lea rdi,[rip+contract_tail]
    mov esi,contract_tail_end-contract_tail
    call print_stdout
    ret


# Deterministic cache hierarchy. Exact replacement/prefetch policy is still
# microarchitectural and not claimed from these architectural sizes.
detect_cache_topology:
    mov qword ptr [rip+l1d_bytes], 0
    mov qword ptr [rip+l1i_bytes], 0
    mov qword ptr [rip+l2_bytes], 0
    mov qword ptr [rip+l3_bytes], 0
    mov dword ptr [rip+l1d_share_threads], 0
    mov dword ptr [rip+l2_share_threads], 0
    mov dword ptr [rip+l3_share_threads], 0
    mov r11d, 4
    cmp dword ptr [rip+max_extended_cpuid], 0x8000001d
    jb .dct_basic
    mov r11d, 0x8000001d
    jmp .dct_have_leaf
.dct_basic:
    cmp dword ptr [rip+max_cpuid], 4
    jb .dct_done
.dct_have_leaf:
    push rbx
    xor r9d, r9d                    # subleaf
.dct_loop:
    mov eax, r11d
    mov ecx, r9d
    cpuid
    mov esi,eax
    shr esi,14
    and esi,0xfff
    inc esi                         # logical processors sharing this cache
    mov r8d, eax
    and r8d, 0x1f                   # cache type
    test r8d, r8d
    jz .dct_pop
    mov r10d, eax
    shr r10d, 5
    and r10d, 7                     # level

    # size=(ways+1)*(partitions+1)*(line+1)*(sets+1)
    mov rax, rbx
    and eax, 0xfff
    inc rax                         # line
    mov rdx, rbx
    shr rdx, 12
    and edx, 0x3ff
    inc rdx                         # partitions
    imul rax, rdx
    mov rdx, rbx
    shr rdx, 22
    and edx, 0x3ff
    inc rdx                         # ways
    imul rax, rdx
    mov edx, ecx
    inc rdx                         # sets
    imul rax, rdx

    cmp r10d, 1
    jne .dct_l2
    cmp r8d, 1                      # data cache
    jne .dct_l1i
    mov [rip+l1d_bytes], rax
    mov dword ptr [rip+l1d_share_threads],esi
    jmp .dct_next
.dct_l1i:
    cmp r8d, 2                      # instruction cache
    jne .dct_next
    mov [rip+l1i_bytes], rax
    jmp .dct_next
.dct_l2:
    cmp r10d, 2
    jne .dct_l3
    mov [rip+l2_bytes], rax
    mov dword ptr [rip+l2_share_threads],esi
    jmp .dct_next
.dct_l3:
    cmp r10d, 3
    jne .dct_next
    mov [rip+l3_bytes], rax
    mov dword ptr [rip+l3_share_threads],esi
.dct_next:
    inc r9d
    cmp r9d, 32
    jb .dct_loop
.dct_pop:
    pop rbx
.dct_done:
    ret

# ---------------------------------------------------------------------------
# CPU detection. The compiler executable itself stays baseline x86-64.
# feature_bits:
# bit0 AVX usable by CPU+OS, bit1 AVX2, bit2 FMA, bit3 AVX512F+OS state,
# bit4 AVX512BW, bit5 AVX512DQ, bit6 AVX512VL, bit7 BMI1, bit8 BMI2,
# bit9 POPCNT, bit10 LZCNT, bit11 SSE4.1, bit12 SSE4.2.
# ---------------------------------------------------------------------------
detect_cpu:
    push rbx
    xor eax, eax
    cpuid
    mov dword ptr [rip+max_cpuid], eax
    mov dword ptr [rip+vendor_string+0], ebx
    mov dword ptr [rip+vendor_string+4], edx
    mov dword ptr [rip+vendor_string+8], ecx

    mov eax, 0x80000000
    cpuid
    mov dword ptr [rip+max_extended_cpuid], eax

    xor r12d, r12d                 # local feature bits
    mov eax, 1
    cpuid
    mov r11d, eax
    mov r8d, ecx
    # CLFLUSH line-size field is in 8-byte units.
    mov eax, ebx
    shr eax, 8
    and eax, 0xff
    shl eax, 3
    mov dword ptr [rip+cache_line_bytes], eax
    # Effective family/model/stepping. CPUID rules use the *base* family
    # to decide whether extended family/model fields participate.
    mov eax, r11d
    and eax, 0xf
    mov dword ptr [rip+cpu_stepping], eax
    mov eax, r11d
    shr eax, 8
    and eax, 0xf
    mov r9d, eax                    # base family
    mov eax, r11d
    shr eax, 4
    and eax, 0xf
    mov r10d, eax                   # base model
    cmp r9d, 6
    je 82f
    cmp r9d, 0xf
    jne 83f
82:
    mov eax, r11d
    shr eax, 16
    and eax, 0xf
    shl eax, 4
    or r10d, eax
83:
    mov eax, r9d
    cmp r9d, 0xf
    jne 84f
    mov ecx, r11d
    shr ecx, 20
    and ecx, 0xff
    add eax, ecx
84:
    mov dword ptr [rip+cpu_family], eax
    mov dword ptr [rip+cpu_model], r10d
    # AVX needs AVX + OSXSAVE and XCR0 XMM/YMM state.
    bt r8d, 28                     # AVX
    jnc .no_avx_state
    bt r8d, 27                     # OSXSAVE
    jnc .no_avx_state
    xor ecx, ecx
    xgetbv
    and eax, 0x6
    cmp eax, 0x6
    jne .no_avx_state
    or r12d, 1
    bt r8d, 12                     # FMA
    jnc .after_fma
    or r12d, 4
.after_fma:
    cmp dword ptr [rip+max_cpuid], 7
    jb .no_avx_state
    mov eax, 7
    xor ecx, ecx
    cpuid
    bt ebx, 5                      # AVX2
    jnc .after_avx2
    or r12d, 2
.after_avx2:
    # AVX-512 requires CPUID.7:EBX[16] + XCR0 bits 1,2,5,6,7.
    bt ebx, 16
    jnc .no_avx_state
    xor ecx, ecx
    xgetbv
    and eax, 0xE6
    cmp eax, 0xE6
    jne .no_avx_state
    or r12d, 8
    bt ebx, 30                     # AVX512BW
    jnc .after_avx512bw
    or r12d, 16
.after_avx512bw:
    bt ebx, 17                     # AVX512DQ
    jnc .after_avx512dq
    or r12d, 32
.after_avx512dq:
    bt ebx, 31                     # AVX512VL
    jnc .after_avx512vl
    or r12d, 64
.after_avx512vl:
    bt ebx, 3                      # BMI1
    jnc .after_bmi1
    or r12d, 128
.after_bmi1:
    bt ebx, 8                      # BMI2
    jnc .after_bmi2
    or r12d, 256
.after_bmi2:
.no_avx_state:
    # Features from CPUID.1 that are useful to generic capability promotion.
    # They are recorded independently from SIMD width.
    mov eax,1
    cpuid
    bt ecx,23                      # POPCNT
    jnc .after_popcnt
    or r12d,512
.after_popcnt:
    bt ecx,19                      # SSE4.1
    jnc .after_sse41
    or r12d,2048
.after_sse41:
    bt ecx,20                      # SSE4.2
    jnc .after_sse42
    or r12d,4096
.after_sse42:
    # ABM/LZCNT is CPUID.80000001H:ECX[5].
    cmp dword ptr [rip+max_extended_cpuid],0x80000001
    jb .after_lzcnt
    mov eax,0x80000001
    cpuid
    bt ecx,5
    jnc .after_lzcnt
    or r12d,1024
.after_lzcnt:
    mov dword ptr [rip+feature_bits], r12d
    call derive_isa_capabilities
    pop rbx
    ret


# Derive semantic/native realization capabilities from raw CPUID classes.
# Capability bits are deliberately many-to-one: AVX2 and AVX-512 may contribute
# the same semantic ability, while a synthesized recipe can promote a missing
# single instruction without lying about the underlying CPUID feature.
derive_isa_capabilities:
    push rbx
    xor ebx,ebx
    mov eax,dword ptr [rip+feature_bits]
    bt eax,0                       # AVX
    jnc .dic_no_avx
    or ebx,ISA_CAP_VEC256_FP
.dic_no_avx:
    bt eax,1                       # AVX2
    jnc .dic_no_avx2
    or ebx,ISA_CAP_VEC256_INT | ISA_CAP_GATHER | ISA_CAP_MASKED_MEMORY | ISA_CAP_I64_MUL_SYNTH
.dic_no_avx2:
    bt eax,2                       # FMA3
    jnc .dic_no_fma
    or ebx,ISA_CAP_FMA
.dic_no_fma:
    bt eax,3                       # AVX512F
    jnc .dic_no_512f
    or ebx,ISA_CAP_VEC512 | ISA_CAP_PREDICATE | ISA_CAP_MASKED_TAIL
    or ebx,ISA_CAP_SCALAR_BROADCAST | ISA_CAP_EMBED_BROADCAST | ISA_CAP_WIDE_REGFILE
    or ebx,ISA_CAP_GATHER | ISA_CAP_I64_MIN | ISA_CAP_I64_MUL_SYNTH | ISA_CAP_MASK_TO_I64_SYNTH
    or ebx,ISA_CAP_I64_FP_CONVERT_SYNTH | ISA_CAP_NONNEG_F64_U64_TRUNC_SYNTH
    or ebx,ISA_CAP_CROSS_VECTOR_STATE | ISA_CAP_REDUCTION_TREE | ISA_CAP_FMA
.dic_no_512f:
    bt eax,4                       # AVX512BW
    jnc .dic_no_bw
    or ebx,ISA_CAP_BYTE_VECTOR
.dic_no_bw:
    bt eax,5                       # AVX512DQ
    jnc .dic_no_dq
    or ebx,ISA_CAP_I64_MUL_NATIVE | ISA_CAP_I64_FP_CONVERT | ISA_CAP_MASK_TO_I64_NATIVE
.dic_no_dq:
    bt eax,6                       # AVX512VL
    jnc .dic_no_vl
    or ebx,ISA_CAP_VECTOR_LENGTH
.dic_no_vl:
    bt eax,8                       # BMI2
    jnc .dic_no_bmi2
    or ebx,ISA_CAP_BIT_EXTRACT_DEPOSIT
.dic_no_bmi2:
    bt eax,9                       # POPCNT
    jnc .dic_no_pop
    or ebx,ISA_CAP_POPCOUNT
.dic_no_pop:
    bt eax,10                      # LZCNT
    jnc .dic_done
    or ebx,ISA_CAP_LZCNT
.dic_done:
    mov dword ptr [rip+isa_cap_bits],ebx
    pop rbx
    ret

# parse_isa_limit_cstr(rdi=name) -> eax mode, edx 0 success / 1 fail.
# 0=native, 1=AVX512F foundation only, 2=AVX512F+DQ (no VL/BW), 3=AVX2 ceiling.
parse_isa_limit_cstr:
    push rbx
    mov rbx,rdi
    lea rsi,[rip+isa_name_native]; call streq; test eax,eax; jz 1f
    xor eax,eax; xor edx,edx; pop rbx; ret
1:  mov rdi,rbx; lea rsi,[rip+isa_name_avx512f]; call streq; test eax,eax; jz 2f
    mov eax,1; xor edx,edx; pop rbx; ret
2:  mov rdi,rbx; lea rsi,[rip+isa_name_avx512dq]; call streq; test eax,eax; jz 3f
    mov eax,2; xor edx,edx; pop rbx; ret
3:  mov rdi,rbx; lea rsi,[rip+isa_name_avx2]; call streq; test eax,eax; jz .pil_bad
    mov eax,3; xor edx,edx; pop rbx; ret
.pil_bad:
    xor eax,eax; mov edx,1; pop rbx; ret

# Apply a target ceiling to semantic capabilities only. Compiler self-scanning
# continues to use the actual host ISA. This is a backend-audit/testing control,
# not a semantic fallback selector.
apply_isa_limit:
    mov eax,dword ptr [rip+isa_limit_mode]
    test eax,eax
    jz .ail_done
    mov ecx,dword ptr [rip+isa_cap_bits]
    cmp eax,1
    jne .ail_dq
    # Foundation target: remove extension-only capabilities. Generic i64 multiply
    # remains available through its synthesized AVX512F recipe.
    mov edx,ISA_CAP_I64_MUL_NATIVE | ISA_CAP_I64_FP_CONVERT | ISA_CAP_MASK_TO_I64_NATIVE | ISA_CAP_VECTOR_LENGTH | ISA_CAP_BYTE_VECTOR
    not edx
    and ecx,edx
    jmp .ail_store
.ail_dq:
    cmp eax,2
    jne .ail_avx2
    mov edx,ISA_CAP_VECTOR_LENGTH | ISA_CAP_BYTE_VECTOR
    not edx
    and ecx,edx
    jmp .ail_store
.ail_avx2:
    # Keep only capabilities realizable by the AVX/AVX2 family. The current
    # tensor512 physical realizer will explicitly reject because VEC512 and
    # native predication are absent; no scalar fallback is permitted.
    mov edx,ISA_CAP_VEC256_FP | ISA_CAP_VEC256_INT | ISA_CAP_FMA | ISA_CAP_GATHER | ISA_CAP_I64_MUL_SYNTH | ISA_CAP_MASKED_MEMORY | ISA_CAP_BIT_EXTRACT_DEPOSIT | ISA_CAP_POPCOUNT | ISA_CAP_LZCNT
    and ecx,edx
.ail_store:
    mov dword ptr [rip+isa_cap_bits],ecx
.ail_done:
    ret

# parse_u32_cstr(rdi=cstr) -> eax value, edx=0 success; edx=1 fail.
parse_u32_cstr:
    xor eax, eax
    xor edx, edx
    xor r8d, r8d
.pu32_loop:
    movzx ecx, byte ptr [rdi]
    test ecx, ecx
    jz .pu32_done
    cmp ecx, '0'
    jb .pu32_bad
    cmp ecx, '9'
    ja .pu32_bad
    sub ecx, '0'
    cmp eax, 429496729
    ja .pu32_bad
    imul eax, eax, 10
    add eax, ecx
    inc r8d
    inc rdi
    jmp .pu32_loop
.pu32_done:
    test r8d, r8d
    jz .pu32_bad
    xor edx, edx
    ret
.pu32_bad:
    xor eax, eax
    mov edx, 1
    ret

# update_schedule_bound_ticks(eax=bound in 1/12-cycle ticks, edx=id)
update_schedule_bound_ticks:
    cmp eax, dword ptr [rip+schedule_bound_ticks]
    jbe .usbt_done
    mov dword ptr [rip+schedule_bound_ticks], eax
    mov dword ptr [rip+schedule_bottleneck_id], edx
.usbt_done:
    ret

synthesize_resource_schedule:
    # Resource counts order: fp_add, fp_mul, fp_div, fp_convert, int_alu,
    # int_mul, int_div, load, agu, branch.  Bounds use 1/12-cycle ticks so
    # 2/c, 3/c and 4/c issue rates remain exact without floating point.
    mov dword ptr [rip+schedule_bound_ticks], 0
    mov dword ptr [rip+schedule_bound_cycles], 0
    mov dword ptr [rip+schedule_bottleneck_id], 0
    lea r8, [rip+schedule_counts]

    # fp add 2/c => 6 ticks/op
    mov eax, dword ptr [r8+0]
    imul eax, eax, PRC_FP_ADD_TICKS
    mov edx, 1
    call update_schedule_bound_ticks
    # fp mul 2/c
    mov eax, dword ptr [r8+4]
    imul eax, eax, PRC_FP_MUL_TICKS
    mov edx, 2
    call update_schedule_bound_ticks
    # fp div conservative 14 cycles/op => 168 ticks/op
    mov eax, dword ptr [r8+8]
    imul eax, eax, PRC_FP_DIV_TICKS
    mov edx, 3
    call update_schedule_bound_ticks
    # fp convert conservative 1/c
    mov eax, dword ptr [r8+12]
    imul eax, eax, PRC_FP_CONV_TICKS
    mov edx, 4
    call update_schedule_bound_ticks
    # int ALU 4/c => 3 ticks/op
    mov eax, dword ptr [r8+16]
    imul eax, eax, PRC_INT_ALU_TICKS
    mov edx, 5
    call update_schedule_bound_ticks
    # int mul 2/c
    mov eax, dword ptr [r8+20]
    imul eax, eax, PRC_INT_MUL_TICKS
    mov edx, 6
    call update_schedule_bound_ticks
    # int div 10 cycles/op
    mov eax, dword ptr [r8+24]
    imul eax, eax, PRC_INT_DIV_TICKS
    mov edx, 7
    call update_schedule_bound_ticks
    # load 2/c
    mov eax, dword ptr [r8+28]
    imul eax, eax, PRC_LOAD_TICKS
    mov edx, 8
    call update_schedule_bound_ticks
    # AGU 3/c
    mov eax, dword ptr [r8+32]
    imul eax, eax, PRC_AGU_TICKS
    mov edx, 9
    call update_schedule_bound_ticks
    # branch 1/c
    mov eax, dword ptr [r8+36]
    imul eax, eax, PRC_BRANCH_TICKS
    mov edx, 10
    call update_schedule_bound_ticks
    # 1.3.93 physical-axis closure.  Port/issue pressure and transport are
    # orthogonal Physical Facts.  Preserve the complete issue bound before
    # Traffic Reality joins the total physical cost.  Reduction recurrence and
    # Group carrier width consume only this issue/dependency fact; transport
    # continues to price outward materialization, placement and the reported
    # whole schedule.  A costly wire/cache-line movement therefore cannot erase
    # independent arithmetic recurrences.
    mov eax, dword ptr [rip+schedule_bound_ticks]
    mov dword ptr [rip+schedule_issue_bound_ticks], eax

    # Traffic Reality remains the eleventh total physical resource.
    mov eax, dword ptr [r8+28]
    imul eax, eax, PRC_TRAFFIC_LINE_TICKS
    mov edx, 11
    call update_schedule_bound_ticks

    # Human-facing conservative ceil(cycles) from total physical bound.
    mov eax, dword ptr [rip+schedule_bound_ticks]
    add eax, 11
    xor edx, edx
    mov ecx, 12
    div ecx
    mov dword ptr [rip+schedule_bound_cycles], eax

    # Reduction recurrence width is an analytical Physical-Reality fact, not
    # a candidate-set choice.  The recurrence latency and issue floor are
    # profile facts; target backends later cap the result by what their probe
    # pass actually realized.  There is no divider, memory, workload, or
    # 1/2/4 admission branch here.
    mov ecx, dword ptr [rip+schedule_issue_bound_ticks]
    cmp ecx, 6                      # fp-add issue floor: 0.5 cycle
    jae .srs_target_ready
    mov ecx, 6
.srs_target_ready:
    mov eax, dword ptr [rip+fp_add_latency_ticks]
    lea edx, [rcx-1]
    add eax, edx
    xor edx, edx
    div ecx                         # ceil(add_latency / target_ticks)
    test eax, eax
    jnz .srs_carrier_nonzero
    mov eax, 1
.srs_carrier_nonzero:
    # Standalone schedule mode has no backend probe cap.  In that case the
    # silicon profile's physically supportable recurrence width is authority.
    mov ecx, dword ptr [rip+group_carrier_cap]
    test ecx, ecx
    jnz .srs_have_carrier_cap
    mov ecx, dword ptr [rip+reduction_carriers]
.srs_have_carrier_cap:
    test ecx, ecx
    jz .srs_store_carriers
    cmp eax, ecx
    jbe .srs_store_carriers
    mov eax, ecx
.srs_store_carriers:
    mov dword ptr [rip+group_carrier_factor], eax

    # Group-body replication is a higher-level physical episode. Its structural
    # maximum is independent of SIMD width, while profitable simultaneous bodies
    # remain bounded by the target's proved recurrence/front-end capacity.
    # The semantic frontend provides only a structural maximum (for example,
    # the number of complete SIMD packets in one proven dense axis).  Physical
    # Reality derives the realized body count from the actual expression cost
    # and the discovered L1I capacity.  No 2/4/32 packet candidate set exists.
    xor eax, eax
    xor ecx, ecx
.srs_group_sum:
    cmp ecx, 10
    jae .srs_group_sum_done
    add eax, dword ptr [r8+rcx*4]
    inc ecx
    jmp .srs_group_sum
.srs_group_sum_done:
    mov dword ptr [rip+schedule_total_ops], eax
    test eax,eax
    jnz .srs_group_have_ops
    mov eax,1
.srs_group_have_ops:
    # Hot Group replication has its own measured probe footprint.  Whole-kernel
    # schedule totals include mutually-exclusive boundary and setup paths and
    # therefore must not price one duplicated Group body.
    mov r9d,dword ptr [rip+group_body_cost_bytes]
    test r9d,r9d
    jnz .srs_group_have_body_bytes
    mov r9d,eax
    shl r9d,2                       # fallback for non-Group callers only
    jnz .srs_group_have_body_bytes
    mov r9d,1
.srs_group_have_body_bytes:

    # Zero structural cap means the relation is an unbounded independent stream
    # (for example rank-1).  It is not a request to inherit recurrence width.
    # A nonzero cap means a finite ShapeFact domain and is used only as a proof
    # that the emitted group partitions that domain exactly.
    mov ecx,dword ptr [rip+group_body_cap]

    mov rax,qword ptr [rip+l1i_bytes]
    test rax,rax
    jz .srs_group_no_i_cache_fact
    xor edx,edx
    mov r10d,r9d
    div r10                         # complete bodies physically fitting L1I
    test rax,rax
    jnz .srs_group_have_i_cache_fit
    mov eax,1
.srs_group_have_i_cache_fit:
    test ecx,ecx
    jz .srs_group_fit_ready
    cmp rax,rcx
    jbe .srs_group_fit_ready
    mov eax,ecx
.srs_group_fit_ready:
    # Group-body replication and reduction recurrence are orthogonal physical
    # facts.  A one-body probe may legitimately realize one accumulator while
    # the surrounding dense relation can still profitably contain several SIMD
    # bodies.  Therefore the recurrence-carrier witness must never cap Group
    # body width.  Bound the episode instead by the target front-end budget and
    # the measured single-body resource footprint.  The budget belongs to the
    # silicon profile; it is not a source-shape or workload threshold.
    mov edx,dword ptr [rip+front_end_budget]
    test edx,edx
    jz .srs_group_fit_frontend_ready
    push rax
    mov eax,edx
    xor edx,edx
    mov r10d,dword ptr [rip+group_body_cost_ops]
    test r10d,r10d
    jnz .srs_group_frontend_have_ops
    mov r10d,dword ptr [rip+schedule_total_ops]
    test r10d,r10d
    jnz .srs_group_frontend_have_ops
    mov r10d,1
.srs_group_frontend_have_ops:
    div r10d                        # complete bodies within target front-end budget
    test eax,eax
    jnz .srs_group_frontend_nonzero
    mov eax,1
.srs_group_frontend_nonzero:
    mov r10d,eax
    pop rax
    cmp eax,r10d
    jbe .srs_group_fit_frontend_ready
    mov eax,r10d
.srs_group_fit_frontend_ready:
    # Unbounded streams have no finite ShapeFact carry to erase, but a true
    # reduction recurrence may still expose several independent carrier chains.
    # Realize at most that proved recurrence width and only while the measured
    # front-end/L1I fit can hold it.  This absorbs the mature Vector episode into
    # GroupFact without turning arbitrary code replication into a policy.
    test ecx,ecx
    jnz .srs_group_finite_domain
    mov edx,dword ptr [rip+group_carrier_factor]
    test edx,edx
    jnz .srs_group_stream_have_carrier
    mov edx,1
.srs_group_stream_have_carrier:
    cmp eax,edx
    jbe .srs_group_store_body
    mov eax,edx
    jmp .srs_group_store_body
.srs_group_finite_domain:
    mov r11d,eax
.srs_group_divisor_probe:
    cmp r11d,1
    jbe .srs_group_divisor_one
    mov eax,ecx
    xor edx,edx
    div r11d
    test edx,edx
    jz .srs_group_divisor_ready
    dec r11d
    jmp .srs_group_divisor_probe
.srs_group_divisor_one:
    mov r11d,1
.srs_group_divisor_ready:
    mov eax,r11d
    jmp .srs_group_store_body
.srs_group_no_i_cache_fact:
    # Unknown instruction-cache geometry must not invent width.
    mov eax,1
.srs_group_store_body:
    # A body axis is a real Group dimension only when the semantic relation has
    # structure beyond a rank-1 independent reduction.  In the latter case SIMD
    # already represents the complete recovered group, so retaining a replicated
    # body axis would only duplicate Vector code.  This is a relation closure,
    # not a workload/size threshold: higher logical rank or an Operator relation
    # keeps the body axis eligible and Physical Reality still chooses its extent.
    mov edx,dword ptr [rip+group_logical_rank]
    cmp edx,1
    ja .srs_group_relation_keeps_body
    mov edx,dword ptr [rip+group_relation_mask]
    test edx,GF_REL_OPERATOR
    jnz .srs_group_relation_keeps_body
    # Degenerate Group keeps the already-proven Vector episode factor.  The
    # recurrence/front-end schedule is the mature Vector physicalization floor;
    # automatic grouping may widen it, but must never destroy it merely because
    # no higher-order relation survived.
    mov eax,dword ptr [rip+group_carrier_factor]
    test eax,eax
    jnz .srs_group_relation_keeps_body
    mov eax,1
.srs_group_relation_keeps_body:
    test eax,eax
    jnz .srs_group_body_nonzero
    mov eax,1
.srs_group_body_nonzero:
    mov dword ptr [rip+group_body_factor],eax
    imul eax,r9d
    mov dword ptr [rip+schedule_estimated_code_bytes],eax

.srs_done:
    # Backend capability closure. Zero means unconstrained (standalone schedule
    # mode); nonzero caps are supplied before canonical code generation.
    mov ecx,dword ptr [rip+group_carrier_cap]
    test ecx,ecx
    jz .srs_cap_body
    cmp dword ptr [rip+group_carrier_factor],ecx
    jbe .srs_cap_body
    mov dword ptr [rip+group_carrier_factor],ecx
.srs_cap_body:
    mov ecx,dword ptr [rip+group_body_cap]
    test ecx,ecx
    jz .srs_caps_done
    cmp dword ptr [rip+group_body_factor],ecx
    jbe .srs_caps_done
    mov dword ptr [rip+group_body_factor],ecx
.srs_caps_done:
    # Resource proof writes directly into GroupFact body/carrier factors. The
    # frontend/backend may tighten those same facts with exact allocator proof
    # before GroupFact rank/form closure. No legacy width handoff exists.
    ret

synthesize_group_fact:
    # Inputs are sparse facts only: logical rank and relation mask from the
    # semantic frontend, lane factor from the target physicalizer, and the
    # already-proven resource replication/carrier factors.  No fixed rank or
    # group-size candidate set exists.
    mov eax,dword ptr [rip+group_body_factor]
    test eax,eax
    jnz .sgf_body_ready
    mov eax,1
.sgf_body_ready:
    mov dword ptr [rip+group_body_factor],eax
    mov eax,dword ptr [rip+group_carrier_factor]
    test eax,eax
    jnz .sgf_carrier_ready
    mov eax,1
.sgf_carrier_ready:
    mov dword ptr [rip+group_carrier_factor],eax

    # Realization closure: a carrier witness cannot exceed the body episode that
    # physically feeds it.  Resource scheduling has already priced recurrence
    # demand against the same front-end/L1I fit, so closure only contracts stale
    # carrier demand; it never widens the body after the cost proof.
    mov edx,dword ptr [rip+group_relation_mask]
    test edx,GF_REL_REDUCTION
    jz .sgf_reduction_closed
    mov eax,dword ptr [rip+group_carrier_factor]
    mov ecx,dword ptr [rip+group_body_factor]
    cmp eax,ecx
    jbe .sgf_reduction_closed
    mov dword ptr [rip+group_carrier_factor],ecx
.sgf_reduction_closed:

    mov eax,dword ptr [rip+group_lane_factor]
    test eax,eax
    jnz .sgf_lane_ready
    mov eax,1
    mov dword ptr [rip+group_lane_factor],eax
.sgf_lane_ready:

    # Rank is derived, never stored as a capacity. ShapeFact-N retains logical
    # axis identity. Operation-affine replication and an independent reduction
    # carrier each contribute an additional nontrivial group axis.
    mov ecx,dword ptr [rip+group_logical_rank]
    test ecx,ecx
    jnz .sgf_have_logical_rank
    cmp eax,1
    jbe .sgf_have_logical_rank
    mov ecx,1
.sgf_have_logical_rank:
    cmp dword ptr [rip+group_body_factor],1
    jbe .sgf_no_body_axis
    inc ecx
.sgf_no_body_axis:
    mov edx,dword ptr [rip+group_relation_mask]
    test edx,GF_REL_REDUCTION
    jz .sgf_no_carrier_axis
    cmp dword ptr [rip+group_carrier_factor],1
    jbe .sgf_no_carrier_axis
    inc ecx
.sgf_no_carrier_axis:
    mov dword ptr [rip+group_rank],ecx

    # Scalar and Vector are not sibling optimizers. They are the rank-0/rank-1
    # degradations of the recovered group.
    mov eax,GF_FORM_SCALAR
    test ecx,ecx
    jz .sgf_form_ready
    mov eax,GF_FORM_VECTOR
    cmp ecx,1
    je .sgf_form_ready
    mov eax,GF_FORM_GROUP
.sgf_form_ready:
    mov dword ptr [rip+group_form],eax

    # Cardinality is diagnostic only. Overflow means unknown/unbounded at AOT,
    # never rejection or a hidden admission threshold.
    mov dword ptr [rip+group_cardinality_exact],1
    mov eax,dword ptr [rip+group_lane_factor]
    mov ecx,dword ptr [rip+group_body_factor]
    mul rcx
    test rdx,rdx
    jnz .sgf_card_unknown
    mov ecx,dword ptr [rip+group_carrier_factor]
    mul rcx
    test rdx,rdx
    jnz .sgf_card_unknown
    mov qword ptr [rip+group_cardinality],rax
    ret
.sgf_card_unknown:
    mov qword ptr [rip+group_cardinality],0
    mov dword ptr [rip+group_cardinality_exact],0
    ret

print_resource_schedule_json:
    lea rdi, [rip+sched_head]
    mov esi, sched_head_end-sched_head
    call print_stdout
    lea rdi, [rip+sched_bound]
    mov esi, sched_bound_end-sched_bound
    mov edx, dword ptr [rip+schedule_bound_cycles]
    call print_json_num_field
    lea rdi, [rip+sched_simd]
    mov esi, sched_simd_end-sched_simd
    mov edx, dword ptr [rip+simd_scan_width]
    call print_json_num_field
    lea rdi, [rip+sched_group_form]
    mov esi, sched_group_form_end-sched_group_form
    mov edx, dword ptr [rip+group_form]
    call print_json_num_field
    lea rdi, [rip+sched_group_rank]
    mov esi, sched_group_rank_end-sched_group_rank
    mov edx, dword ptr [rip+group_rank]
    call print_json_num_field
    lea rdi, [rip+sched_group_lane]
    mov esi, sched_group_lane_end-sched_group_lane
    mov edx, dword ptr [rip+group_lane_factor]
    call print_json_num_field
    lea rdi, [rip+sched_group_body]
    mov esi, sched_group_body_end-sched_group_body
    mov edx, dword ptr [rip+group_body_factor]
    call print_json_num_field
    lea rdi, [rip+sched_group_carrier]
    mov esi, sched_group_carrier_end-sched_group_carrier
    mov edx, dword ptr [rip+group_carrier_factor]
    call print_json_num_field
    lea rdi, [rip+sched_code]
    mov esi, sched_code_end-sched_code
    mov edx, dword ptr [rip+schedule_estimated_code_bytes]
    call print_json_num_field
    lea rdi, [rip+sched_bneck]
    mov esi, sched_bneck_end-sched_bneck
    call print_stdout
    mov eax, dword ptr [rip+schedule_bottleneck_id]
    cmp eax, 1
    jb .prsj_none
    cmp eax, 11
    ja .prsj_none
    dec eax
    lea rdx, [rip+bottleneck_ptrs]
    mov rdi, [rdx+rax*8]
    # length table is u32
    lea rdx, [rip+bottleneck_lens]
    mov esi, dword ptr [rdx+rax*4]
    call print_stdout
    jmp .prsj_tail
.prsj_none:
    lea rdi, [rip+bottleneck_none]
    mov esi, bottleneck_none_end-bottleneck_none
    call print_stdout
.prsj_tail:
    lea rdi, [rip+sched_tail]
    mov esi, sched_tail_end-sched_tail
    call print_stdout
    ret

# streq(rdi=a, rsi=b) -> eax=1 equal, 0 otherwise
streq:
.loop:
    mov al, byte ptr [rdi]
    mov dl, byte ptr [rsi]
    cmp al, dl
    jne .no
    test al, al
    je .yes
    inc rdi
    inc rsi
    jmp .loop
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

# memfind(rdi=buf, rsi=len, rdx=needle, ecx=nlen)
# returns rax = address immediately after needle, or 0.
# The compiler's own source scan is feature-dispatched: AVX-512BW -> AVX2 -> scalar.
memfind:
    # Tiny needles/files stay scalar: vector setup is removable work there.
    cmp rsi, 128
    jb memfind_scalar
    mov eax, dword ptr [rip+feature_bits]
    cmp rsi, 256
    jb 71f
    bt eax, 4
    jc memfind_avx512bw
71:
    bt eax, 1
    jc memfind_avx2
    jmp memfind_scalar

# Common scalar fallback and tail.
memfind_scalar:
    mov dword ptr [rip+last_scan_path], 0
    push rbx
    push r12
    mov r8, rdi
    mov r9, rsi
    mov r10, rdx
    mov r11d, ecx
    cmp r9, r11
    jb .s_notfound
    mov r12, r9
    sub r12, r11
    xor ebx, ebx
.p2align 4
.s_outer:
    cmp rbx, r12
    ja .s_notfound
    xor ecx, ecx
.s_inner:
    cmp ecx, r11d
    je .s_found
    lea rax, [r8+rbx]
    mov al, byte ptr [rax+rcx]
    cmp al, byte ptr [r10+rcx]
    jne .s_next
    inc ecx
    jmp .s_inner
.s_next:
    inc rbx
    jmp .s_outer
.s_found:
    lea rax, [r8+rbx]
    add rax, r11
    pop r12
    pop rbx
    ret
.s_notfound:
    xor eax, eax
    pop r12
    pop rbx
    ret

# AVX2 first-byte candidate scan, scalar full-needle verification.
memfind_avx2:
    mov dword ptr [rip+last_scan_path], 1
    push rbx
    push r12
    push r13
    push r14
    mov r8, rdi
    mov r9, rsi
    mov r10, rdx
    mov r11d, ecx
    cmp r9, r11
    jb .a2_notfound
    mov r12, r9
    sub r12, r11                  # max legal start
    xor ebx, ebx
    vpbroadcastb ymm0, byte ptr [r10]
.p2align 5
.global silicon_hot_scan_avx2
silicon_hot_scan_avx2:
.a2_vec_loop:
    # Need 32 readable source bytes. Buffer has a trailing zero, but do not overread page end.
    lea rax, [rbx+32]
    cmp rax, r9
    ja .a2_tail
    vpcmpeqb ymm1, ymm0, ymmword ptr [r8+rbx]
    vpmovmskb r13d, ymm1
.a2_candidates:
    test r13d, r13d
    jz .a2_next_vec
    bsf ecx, r13d
    btr r13d, ecx
    lea r14, [rbx+rcx]
    cmp r14, r12
    ja .a2_candidates
    xor ecx, ecx
.a2_verify:
    cmp ecx, r11d
    je .a2_found
    lea rax, [r8+r14]
    mov al, byte ptr [rax+rcx]
    cmp al, byte ptr [r10+rcx]
    jne .a2_candidates
    inc ecx
    jmp .a2_verify
.a2_next_vec:
    add rbx, 32
    cmp rbx, r12
    jbe .a2_vec_loop
    jmp .a2_notfound
.a2_tail:
    cmp rbx, r12
    ja .a2_notfound
.a2_tail_outer:
    xor ecx, ecx
.a2_tail_verify:
    cmp ecx, r11d
    je .a2_found_tail
    lea rax, [r8+rbx]
    mov al, byte ptr [rax+rcx]
    cmp al, byte ptr [r10+rcx]
    jne .a2_tail_next
    inc ecx
    jmp .a2_tail_verify
.a2_tail_next:
    inc rbx
    cmp rbx, r12
    jbe .a2_tail_outer
    jmp .a2_notfound
.a2_found:
    lea rax, [r8+r14]
    add rax, r11
    vzeroupper
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.a2_found_tail:
    lea rax, [r8+rbx]
    add rax, r11
    vzeroupper
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.a2_notfound:
    xor eax, eax
    vzeroupper
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# AVX-512BW first-byte scan. This path is entered only after CPUID+XGETBV proof.
memfind_avx512bw:
    mov dword ptr [rip+last_scan_path], 2
    push rbx
    push r12
    push r13
    push r14
    mov r8, rdi
    mov r9, rsi
    mov r10, rdx
    mov r11d, ecx
    cmp r9, r11
    jb .a5_notfound
    mov r12, r9
    sub r12, r11
    xor ebx, ebx
    vpbroadcastb zmm0, byte ptr [r10]
.p2align 6
.global silicon_hot_scan_avx512
silicon_hot_scan_avx512:
.a5_vec_loop:
    lea rax, [rbx+64]
    cmp rax, r9
    ja .a5_tail
    vpcmpeqb k1, zmm0, zmmword ptr [r8+rbx]
    kmovq r13, k1
.a5_candidates:
    test r13, r13
    jz .a5_next_vec
    bsf rcx, r13
    btr r13, rcx
    lea r14, [rbx+rcx]
    cmp r14, r12
    ja .a5_candidates
    xor ecx, ecx
.a5_verify:
    cmp ecx, r11d
    je .a5_found
    lea rax, [r8+r14]
    mov al, byte ptr [rax+rcx]
    cmp al, byte ptr [r10+rcx]
    jne .a5_candidates
    inc ecx
    jmp .a5_verify
.a5_next_vec:
    add rbx, 64
    cmp rbx, r12
    jbe .a5_vec_loop
    jmp .a5_notfound
.a5_tail:
    cmp rbx, r12
    ja .a5_notfound
.a5_tail_outer:
    xor ecx, ecx
.a5_tail_verify:
    cmp ecx, r11d
    je .a5_found_tail
    lea rax, [r8+rbx]
    mov al, byte ptr [rax+rcx]
    cmp al, byte ptr [r10+rcx]
    jne .a5_tail_next
    inc ecx
    jmp .a5_tail_verify
.a5_tail_next:
    inc rbx
    cmp rbx, r12
    jbe .a5_tail_outer
    jmp .a5_notfound
.a5_found:
    lea rax, [r8+r14]
    add rax, r11
    vzeroupper
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.a5_found_tail:
    lea rax, [r8+rbx]
    add rax, r11
    vzeroupper
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.a5_notfound:
    xor eax, eax
    vzeroupper
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# parse_colon_u8(rdi=current, rsi=end) -> eax=value, edx=0 success; edx=1 fail
parse_colon_u8:
    xor eax, eax
    xor edx, edx
.seek_colon:
    cmp rdi, rsi
    jae .bad
    mov cl, byte ptr [rdi]
    inc rdi
    cmp cl, ':'
    jne .seek_colon
.skip_ws:
    cmp rdi, rsi
    jae .bad
    mov cl, byte ptr [rdi]
    cmp cl, ' '
    je .ws
    cmp cl, 9
    je .ws
    cmp cl, 10
    je .ws
    cmp cl, 13
    je .ws
    jmp .digits
.ws:
    inc rdi
    jmp .skip_ws
.digits:
    xor r8d, r8d                    # digit count
.loop_digits:
    cmp rdi, rsi
    jae .done
    movzx ecx, byte ptr [rdi]
    cmp ecx, '0'
    jb .done
    cmp ecx, '9'
    ja .done
    sub ecx, '0'
    imul eax, eax, 10
    add eax, ecx
    cmp eax, 255
    ja .bad
    inc r8d
    inc rdi
    jmp .loop_digits
.done:
    test r8d, r8d
    jz .bad
    xor edx, edx
    ret
.bad:
    xor eax, eax
    mov edx, 1
    ret

print_stdout:
    mov rdx, rsi
    mov rsi, rdi
    mov eax, SYS_write
    mov edi, 1
    syscall
    ret
print_stderr:
    mov rdx, rsi
    mov rsi, rdi
    mov eax, SYS_write
    mov edi, 2
    syscall
    ret
exit_group:
    mov eax, SYS_exit_group
    syscall
    hlt

.section .rodata
opt_probe: .asciz "--probe"
opt_isa_capabilities: .asciz "--isa-capabilities"
opt_silicon_audit: .asciz "--silicon-audit"
opt_silicon_contract: .asciz "--silicon-contract"
opt_strict_silicon: .asciz "--strict-silicon-check"
opt_schedule: .asciz "--schedule"
opt_o:     .asciz "-o"
opt_isa_limit: .asciz "--isa-limit"
isa_name_native: .asciz "native"
isa_name_avx512f: .asciz "avx512f"
isa_name_avx512dq: .asciz "avx512dq"
isa_name_avx2: .asciz "avx2"
fmt_marker: .ascii "wheelchair.scalar/1"
fmt_marker_end:
general_lane_marker: .ascii "wheelchair.general/1"
general_lane_marker_end:
tensor_fmt_marker: .ascii "wheelchair.tensor/1"
tensor_fmt_marker_end:
exit_key: .ascii "\"exit_code\""
exit_key_end:
newline: .ascii "\n"
msg_isa_caps_header: .ascii "ISA capability algebra:\n"
msg_isa_caps_header_end:
msg_cap_vec256fp: .ascii "  vector-fp-256\n"
msg_cap_vec256fp_end:
msg_cap_vec256int: .ascii "  vector-int-256\n"
msg_cap_vec256int_end:
msg_cap_vec512: .ascii "  vector-512\n"
msg_cap_vec512_end:
msg_cap_predicate: .ascii "  predication\n"
msg_cap_predicate_end:
msg_cap_masktail: .ascii "  predicated-tail\n"
msg_cap_masktail_end:
msg_cap_embcast: .ascii "  embedded-broadcast\n"
msg_cap_embcast_end:
msg_cap_gather: .ascii "  gather\n"
msg_cap_gather_end:
msg_cap_i64mul_native: .ascii "  i64-vector-multiply:native\n"
msg_cap_i64mul_native_end:
msg_cap_i64mul_synth: .ascii "  i64-vector-multiply:synthesizable\n"
msg_cap_i64mul_synth_end:
msg_cap_i64fp: .ascii "  i64-f64-vector-convert\n"
msg_cap_i64fp_end:
msg_cap_i64fp_synth: .ascii "  i64-f64-vector-convert:synthesizable\n"
msg_cap_i64fp_synth_end:
msg_cap_trunc_synth: .ascii "  nonnegative-f64-u64-truncate:synthesizable\n"
msg_cap_trunc_synth_end:
msg_cap_maski64_native: .ascii "  predicate-to-i64-mask:native\n"
msg_cap_maski64_native_end:
msg_cap_maski64_synth: .ascii "  predicate-to-i64-mask:synthesizable\n"
msg_cap_maski64_synth_end:
msg_cap_vl: .ascii "  variable-vector-length-evex\n"
msg_cap_vl_end:
msg_cap_bmi2: .ascii "  bit-extract-deposit\n"
msg_cap_bmi2_end:
msg_cap_crossstate: .ascii "  cross-vector-state\n"
msg_cap_crossstate_end:
msg_cap_reduce: .ascii "  reduction-tree\n"
msg_cap_reduce_end:
probe_prefix: .ascii "Topology Parallel Compiler assembly seed\nCPU vendor: "
probe_prefix_end:
msg_avx: .ascii "AVX: usable\n"
msg_avx_end:
msg_avx2: .ascii "AVX2: available\n"
msg_avx2_end:
msg_fma: .ascii "FMA3: available\n"
msg_fma_end:
msg_avx512: .ascii "AVX-512F: usable\n"
msg_avx512_end:
msg_avx512bw: .ascii "AVX-512BW source scan: enabled\n"
msg_avx512bw_end:
msg_ok: .ascii "topologyc: emitted sovereign ELF64\n"
msg_ok_end:
msg_tensor_ok: .ascii "topologyc: emitted structural tensor ELF64 through causal static ownership\n"
msg_tensor_ok_end:
msg_general_ok: .ascii "topologyc: emitted sovereign general ELF64\n"
msg_general_ok_end:
msg_tensor_error: .ascii "topologyc: structured source rejected by sovereign general and topology frontends\n"
msg_tensor_error_end:
msg_general_executor_error: .ascii "topologyc: requested executor width cannot be honored by an unrecovered general region\n"
msg_general_executor_error_end:
msg_scan_scalar: .ascii "compiler source scan: scalar baseline\n"
msg_scan_scalar_end:
msg_scan_avx2: .ascii "compiler source scan: AVX2 32-byte topology\n"
msg_scan_avx2_end:
msg_scan_avx512: .ascii "compiler source scan: AVX-512BW 64-byte topology\n"
msg_scan_avx512_end:
msg_compile_single: .ascii "compiler topology: single fused SIMD shard; duplicate source passes and clone/wait sharding rejected\n"
msg_compile_single_end:
msg_compile_parallel: .ascii "compiler topology: static 2-way CPU shard; NUMA-local proof passed\n"
msg_compile_parallel_end:
msg_compile_numa_fallback: .ascii "compiler topology: remote-NUMA shard rejected; local fallback used\n"
msg_compile_numa_fallback_end:
msg_mem_static: .ascii "source memory: 64 KiB static local region\n"
msg_mem_static_end:
msg_mem_dynamic_base: .ascii "source memory: page-rounded anonymous region\n"
msg_mem_dynamic_base_end:
msg_mem_dynamic_huge: .ascii "source memory: 2 MiB geometry + MADV_HUGEPAGE accepted; actual THP allocation UNPROVEN\n"
msg_mem_dynamic_huge_end:
msg_mem_numa_bind: .ascii "source NUMA policy: MPOL_BIND accepted before first touch\n"
msg_mem_numa_bind_end:
msg_mem_firsttouch: .ascii "source NUMA policy: mbind unavailable; current-node first-touch fallback\n"
msg_mem_firsttouch_end:
msg_strict_ok: .ascii "topologyc: strict silicon profile accepted\n"
msg_strict_ok_end:
msg_strict_reject: .ascii "topologyc: strict silicon profile rejected; exact resource profile unavailable\n"
msg_strict_reject_end:
msg_usage: .ascii "usage: topologyc --probe | --isa-capabilities | --silicon-audit | --silicon-contract | --strict-silicon-check | --schedule 10_RESOURCE_COUNTS | topologyc INPUT.wh -o OUTPUT [--isa-limit native|avx512f|avx512dq|avx2]\n"
msg_usage_end:
msg_input: .ascii "topologyc: input open/read failed\n"
msg_input_end:
msg_source_large: .ascii "topologyc: source exceeds assembly-seed 64 MiB admission bound\n"
msg_source_large_end:
msg_format: .ascii "topologyc: unsupported source format; sovereign assembly seed rejects\n"
msg_format_end:
msg_parse: .ascii "topologyc: malformed or out-of-range exit_code\n"
msg_parse_end:
msg_output: .ascii "topologyc: output create/write failed\n"
msg_output_end:



# Resource scheduler JSON and bottleneck names.
sched_head: .ascii "{\"format\":\"topology.resource-schedule/2\",\"profile\":\"amd-zen4-family19h-model11h\""
sched_head_end:
sched_bound: .ascii ",\"resource_bound_cycles\":"
sched_bound_end:
sched_simd: .ascii ",\"simd_bytes\":"
sched_simd_end:
sched_group_form: .ascii ",\"group_form\":"
sched_group_form_end:
sched_group_rank: .ascii ",\"group_rank\":"
sched_group_rank_end:
sched_group_lane: .ascii ",\"group_lane_factor\":"
sched_group_lane_end:
sched_group_body: .ascii ",\"group_body_factor\":"
sched_group_body_end:
sched_group_carrier: .ascii ",\"group_carrier_factor\":"
sched_group_carrier_end:
sched_code: .ascii ",\"estimated_hot_code_bytes\":"
sched_code_end:
sched_bneck: .ascii ",\"bottleneck\":\""
sched_bneck_end:
sched_tail: .ascii "\",\"semantic_legality\":\"MUST_BE_PROVED_BEFORE_SCHEDULING\",\"exact_port_routing\":\"UNPROVEN\"}\n"
sched_tail_end:
bottleneck_fp_add: .ascii "fp_add"
bottleneck_fp_add_end:
bottleneck_fp_mul: .ascii "fp_mul"
bottleneck_fp_mul_end:
bottleneck_fp_div: .ascii "fp_div"
bottleneck_fp_div_end:
bottleneck_fp_convert: .ascii "fp_convert"
bottleneck_fp_convert_end:
bottleneck_int_alu: .ascii "int_alu"
bottleneck_int_alu_end:
bottleneck_int_mul: .ascii "int_mul"
bottleneck_int_mul_end:
bottleneck_int_div: .ascii "int_div"
bottleneck_int_div_end:
bottleneck_load: .ascii "load"
bottleneck_load_end:
bottleneck_agu: .ascii "agu"
bottleneck_agu_end:
bottleneck_branch: .ascii "branch"
bottleneck_branch_end:
bottleneck_traffic: .ascii "traffic"
bottleneck_traffic_end:
bottleneck_none: .ascii "none"
bottleneck_none_end:
.align 8
bottleneck_ptrs:
    .quad bottleneck_fp_add,bottleneck_fp_mul,bottleneck_fp_div,bottleneck_fp_convert,bottleneck_int_alu,bottleneck_int_mul,bottleneck_int_div,bottleneck_load,bottleneck_agu,bottleneck_branch,bottleneck_traffic
bottleneck_lens:
    .long bottleneck_fp_add_end-bottleneck_fp_add
    .long bottleneck_fp_mul_end-bottleneck_fp_mul
    .long bottleneck_fp_div_end-bottleneck_fp_div
    .long bottleneck_fp_convert_end-bottleneck_fp_convert
    .long bottleneck_int_alu_end-bottleneck_int_alu
    .long bottleneck_int_mul_end-bottleneck_int_mul
    .long bottleneck_int_div_end-bottleneck_int_div
    .long bottleneck_load_end-bottleneck_load
    .long bottleneck_agu_end-bottleneck_agu
    .long bottleneck_branch_end-bottleneck_branch
    .long bottleneck_traffic_end-bottleneck_traffic

# Target-only Silicon Reality contract. It intentionally carries no program DAG,
# kernel list, task graph, tile size or processing-element count.
contract_head: .ascii "{\"format\":\"wheelchair.silicon-reality/10\",\"target_kind\":\"physical-domain-graph\",\"vendor\":\""
contract_head_end:
contract_family: .ascii "\",\"family\":"
contract_family_end:
contract_model: .ascii ",\"model\":"
contract_model_end:
contract_allowed: .ascii ",\"allowed_execution_contexts\":"
contract_allowed_end:
contract_cpu_quota_usec: .ascii ",\"cpu_quota_usec\":"
contract_cpu_quota_usec_end:
contract_cpu_period_usec: .ascii ",\"cpu_period_usec\":"
contract_cpu_period_usec_end:
contract_execution_admission: .ascii ",\"execution_admission_capacity\":"
contract_execution_admission_end:
contract_cacheline: .ascii ",\"cache_line_bytes\":"
contract_cacheline_end:
contract_l1d: .ascii ",\"l1d_bytes\":"
contract_l1d_end:
contract_l2: .ascii ",\"l2_bytes\":"
contract_l2_end:
contract_l3: .ascii ",\"l3_bytes\":"
contract_l3_end:
contract_threads_per_core: .ascii ",\"threads_per_core\":"
contract_threads_per_core_end:
contract_cores_per_package: .ascii ",\"cores_per_package\":"
contract_cores_per_package_end:
contract_logical_per_package: .ascii ",\"logical_per_package\":"
contract_logical_per_package_end:
contract_l1d_share: .ascii ",\"l1d_share_threads\":"
contract_l1d_share_end:
contract_l2_share: .ascii ",\"l2_share_threads\":"
contract_l2_share_end:
contract_l3_share: .ascii ",\"l3_share_threads\":"
contract_l3_share_end:
contract_domain_identity_exact: .ascii ",\"domain_identity_exact\":"
contract_domain_identity_exact_end:
contract_l1d_domain_count: .ascii ",\"l1d_admitted_domain_count\":"
contract_l1d_domain_count_end:
contract_l1d_domain_max: .ascii ",\"l1d_max_admitted_intersection\":"
contract_l1d_domain_max_end:
contract_l2_domain_count: .ascii ",\"l2_admitted_domain_count\":"
contract_l2_domain_count_end:
contract_l2_domain_max: .ascii ",\"l2_max_admitted_intersection\":"
contract_l2_domain_max_end:
contract_l3_domain_count: .ascii ",\"l3_admitted_domain_count\":"
contract_l3_domain_count_end:
contract_l3_domain_max: .ascii ",\"l3_max_admitted_intersection\":"
contract_l3_domain_max_end:
contract_static_placement_exact: .ascii ",\"static_placement_exact\":"
contract_static_placement_exact_end:
contract_static_placement_required: .ascii ",\"static_placement_required\":"
contract_static_placement_required_end:
contract_preferred_l3_contexts: .ascii ",\"preferred_l3_execution_contexts\":"
contract_preferred_l3_contexts_end:
contract_fabric_proved: .ascii ",\"fabric_target_facts_proved\":"
contract_fabric_proved_end:
contract_fabric_logic: .ascii ",\"fabric_logic_units\":"
contract_fabric_logic_end:
contract_fabric_registers: .ascii ",\"fabric_register_units\":"
contract_fabric_registers_end:
contract_fabric_dsp: .ascii ",\"fabric_dsp_units\":"
contract_fabric_dsp_end:
contract_fabric_storage: .ascii ",\"fabric_local_storage_bytes\":"
contract_fabric_storage_end:
contract_fabric_routes: .ascii ",\"fabric_routing_domains\":"
contract_fabric_routes_end:
contract_fabric_clocks: .ascii ",\"fabric_clock_regions\":"
contract_fabric_clocks_end:
contract_fabric_compute_num: .ascii ",\"fabric_compute_ticks_num\":"
contract_fabric_compute_num_end:
contract_fabric_compute_den: .ascii ",\"fabric_compute_ticks_den\":"
contract_fabric_compute_den_end:
contract_fabric_activation: .ascii ",\"fabric_activation_ticks\":"
contract_fabric_activation_end:
contract_fabric_transport_fixed: .ascii ",\"fabric_transport_fixed_ticks\":"
contract_fabric_transport_fixed_end:
contract_fabric_transport_byte: .ascii ",\"fabric_transport_ticks_per_byte\":"
contract_fabric_transport_byte_end:
contract_tail: .ascii ",\"time_authority\":\"causal_depth\",\"space_authority\":\"traffic_x_silicon_domain_graph\",\"storage_authority\":\"fact_lifetime\",\"multiplicity_authority\":\"groupfact_x_execution_admission\",\"semantic_authority\":\"physical_dag\",\"silicon_domain_graph_authority\":true,\"domain_identity_authority\":\"apic_x_cache_share_intersection\",\"execution_admission_authority\":\"affinity_set\",\"cpu_quota_authority\":\"temporal_budget_only\",\"cpu_quota_is_multiplicity_authority\":false,\"locality_is_execution_capacity_authority\":false,\"power_of_two_execution_roundup\":false,\"placement_authority\":\"traffic_x_exact_l3_domain_identity\",\"placement_is_aot_inherited\":true,\"cardinality_fallback\":false,\"cpu_number_adjacency_assumed\":false,\"geometric_die_adjacency_assumed\":false,\"vendor_model_routes\":false,\"source_size_affinity_crossover\":false,\"von_neumann_order_authority\":false,\"relinearize_before_spatial_realization\":false,\"runtime_silicon_allocator\":false,\"runtime_idle_resource_query\":false,\"runtime_ready_queue\":false,\"runtime_work_stealing\":false,\"parallel_dsl_route\":false,\"hardware_kernel_language\":false,\"fixed_processing_element_count\":false,\"fixed_tile_size\":false,\"occupancy_is_objective\":false,\"theoretical_work_convergence_is_objective\":true,\"arbitrary_transistor_addressing\":false,\"target_exposed_primitives_are_boundary\":true,\"simultaneous_heterogeneous_realization\":true,\"physical_edge_facts\":true,\"edge_traffic_cross_domain_cost\":true,\"shared_causal_completion_law\":true,\"x86_fpga_exclusive_target_selection\":false,\"fpga_offload_kernel_model\":false,\"runtime_device_selector\":false,\"fabric_target_facts_are_external_target_facts\":true,\"joint_domain_placement\":\"strict_improvement_coordinate_closure\",\"joint_domain_fixed_round_limit\":false,\"fabric_activation_bridge_present\":false,\"fabric_activation_abi_present\":true,\"fabric_activation_abi_version\":2,\"fabric_activation_entry_abi\":true,\"fabric_external_completion_explicit_state\":true,\"fabric_realization_descriptor\":true,\"fabric_realization_descriptor_version\":2,\"field_fabric_datapath_descriptor\":true,\"field_fabric_descriptor_second_ir\":false,\"field_fabric_x86_fallback\":false,\"fabric_native_fallback\":false,\"unbridged_fabric_execution_allowed\":false,\"unproven_fabric_materialized\":false,\"fpga_bitstream_emitter_present\":false}\n"
contract_tail_end:

# JSON fragments for the compiler's own physical audit.
audit_head: .ascii "{\"format\":\"topology.silicon-audit/10\",\"vendor\":\""
audit_head_end:
audit_family: .ascii "\",\"family\":"
audit_family_end:
audit_model: .ascii ",\"model\":"
audit_model_end:
audit_stepping: .ascii ",\"stepping\":"
audit_stepping_end:
audit_allowed: .ascii ",\"allowed_cpus\":"
audit_allowed_end:
audit_cpu_quota_usec: .ascii ",\"cpu_quota_usec\":"
audit_cpu_quota_usec_end:
audit_cpu_period_usec: .ascii ",\"cpu_period_usec\":"
audit_cpu_period_usec_end:
audit_execution_admission: .ascii ",\"execution_admission_capacity\":"
audit_execution_admission_end:
audit_current_cpu: .ascii ",\"current_cpu\":"
audit_current_cpu_end:
audit_numa: .ascii ",\"current_numa_node\":"
audit_numa_end:
audit_page: .ascii ",\"page_size\":"
audit_page_end:
audit_cacheline: .ascii ",\"cache_line_bytes\":"
audit_cacheline_end:
audit_l1d: .ascii ",\"l1d_bytes\":"
audit_l1d_end:
audit_l1i: .ascii ",\"l1i_bytes\":"
audit_l1i_end:
audit_l2: .ascii ",\"l2_bytes\":"
audit_l2_end:
audit_l3: .ascii ",\"l3_bytes\":"
audit_l3_end:
audit_threads_per_core: .ascii ",\"threads_per_core\":"
audit_threads_per_core_end:
audit_cores_per_package: .ascii ",\"cores_per_package\":"
audit_cores_per_package_end:
audit_logical_per_package: .ascii ",\"logical_per_package\":"
audit_logical_per_package_end:
audit_l1d_share: .ascii ",\"l1d_share_threads\":"
audit_l1d_share_end:
audit_l2_share: .ascii ",\"l2_share_threads\":"
audit_l2_share_end:
audit_l3_share: .ascii ",\"l3_share_threads\":"
audit_l3_share_end:
audit_domain_identity_exact: .ascii ",\"domain_identity_exact\":"
audit_domain_identity_exact_end:
audit_l1d_domain_count: .ascii ",\"l1d_admitted_domain_count\":"
audit_l1d_domain_count_end:
audit_l1d_domain_max: .ascii ",\"l1d_max_admitted_intersection\":"
audit_l1d_domain_max_end:
audit_l2_domain_count: .ascii ",\"l2_admitted_domain_count\":"
audit_l2_domain_count_end:
audit_l2_domain_max: .ascii ",\"l2_max_admitted_intersection\":"
audit_l2_domain_max_end:
audit_l3_domain_count: .ascii ",\"l3_admitted_domain_count\":"
audit_l3_domain_count_end:
audit_l3_domain_max: .ascii ",\"l3_max_admitted_intersection\":"
audit_l3_domain_max_end:
audit_static_placement_exact: .ascii ",\"static_placement_exact\":"
audit_static_placement_exact_end:
audit_static_placement_required: .ascii ",\"static_placement_required\":"
audit_static_placement_required_end:
audit_preferred_l3_contexts: .ascii ",\"preferred_l3_execution_contexts\":"
audit_preferred_l3_contexts_end:
audit_fabric_proved: .ascii ",\"fabric_target_facts_proved\":"
audit_fabric_proved_end:
audit_fabric_logic: .ascii ",\"fabric_logic_units\":"
audit_fabric_logic_end:
audit_fabric_registers: .ascii ",\"fabric_register_units\":"
audit_fabric_registers_end:
audit_fabric_dsp: .ascii ",\"fabric_dsp_units\":"
audit_fabric_dsp_end:
audit_fabric_storage: .ascii ",\"fabric_local_storage_bytes\":"
audit_fabric_storage_end:
audit_fabric_routes: .ascii ",\"fabric_routing_domains\":"
audit_fabric_routes_end:
audit_fabric_clocks: .ascii ",\"fabric_clock_regions\":"
audit_fabric_clocks_end:
audit_simd: .ascii ",\"compiler_scan_width_bytes\":"
audit_simd_end:
audit_align: .ascii ",\"hot_loop_alignment\":"
audit_align_end:
audit_carriers: .ascii ",\"modelled_reduction_carriers\":"
audit_carriers_end:
audit_scan_loop: .ascii ",\"fused_scan_loop_bytes\":"
audit_scan_loop_end:
audit_scan_loads: .ascii ",\"loads_per_vector_block\":"
audit_scan_loads_end:
audit_scan_cmps: .ascii ",\"vector_compares_per_block\":"
audit_scan_cmps_end:
audit_scan_vregs: .ascii ",\"vector_registers_hot_scan\":"
audit_scan_vregs_end:
audit_scan_kregs: .ascii ",\"mask_registers_hot_scan\":"
audit_scan_kregs_end:
audit_profile_prefix: .ascii ",\"microarchitecture_profile\":\""
audit_profile_prefix_end:
profile_fact_derived: .ascii "fact-derived-x86_64"
profile_fact_derived_end:
audit_profile_status: .ascii "\",\"profile_status\":\""
audit_profile_status_end:
status_clean: .ascii "PROVEN_CLEAN"
status_clean_end:
status_debt: .ascii "KNOWN_DEBT"
status_debt_end:
audit_tail: .ascii "\",\"compiler_hot_scan\":\"REGRESSION_GATED_NOT_EXHAUSTIVE\",\"general_resource_scheduler\":\"CONNECTED_RELEASE_GATE\",\"computation_elimination\":\"PARALLEL_PRESERVING_RELEASE_GATE\",\"communication_elimination\":\"PARTITION_LOCAL_MINIMAL_BOUNDARY_RELEASE_GATE\",\"affinity_policy\":\"AOT_EXACT_L3_DOMAIN_INHERITED_PLACEMENT\",\"source_numa_bind\":\"FIRST_TOUCH_DOMAIN_FACT\",\"hugepage_policy\":\"PHYSICAL_PAGE_GEOMETRY\",\"die_geometric_distance\":\"UNEXPOSED_NOT_ASSUMED\",\"exact_uop_port_routing\":\"UNPROVEN\",\"exact_tlb_occupancy\":\"UNPROVEN\",\"dram_channel_hash\":\"UNPROVEN\",\"exact_transistor_switching\":\"UNPROVEN_NOT_ISA_CONTROLLABLE\",\"architecture_complete\":false}\n"
audit_tail_end:

# Minimal ET_EXEC x86-64 ELF, one RX PT_LOAD. Code at offset 0x78:
#   mov edi, imm32
#   mov eax, 60
#   syscall
.equ ELF_CODE_OFF, 0x78
elf_template:
    # e_ident[16]
    .byte 0x7f,'E','L','F', 2,1,1,0, 0,0,0,0,0,0,0,0
    .word 2                         # ET_EXEC
    .word 62                        # EM_X86_64
    .long 1                         # EV_CURRENT
    .quad 0x400078                  # e_entry
    .quad 64                        # e_phoff
    .quad 0                         # e_shoff
    .long 0                         # e_flags
    .word 64                        # e_ehsize
    .word 56                        # e_phentsize
    .word 1                         # e_phnum
    .word 0                         # e_shentsize
    .word 0                         # e_shnum
    .word 0                         # e_shstrndx
    # Elf64_Phdr
    .long 1                         # PT_LOAD
    .long 5                         # PF_R | PF_X
    .quad 0                         # p_offset
    .quad 0x400000                  # p_vaddr
    .quad 0x400000                  # p_paddr
    .quad 0x84                      # p_filesz
    .quad 0x84                      # p_memsz
    .quad 0x1000                    # p_align
    # code at 0x78
    .byte 0xBF,0,0,0,0              # mov edi, imm32 (patched)
    .byte 0xB8,0x3C,0,0,0           # mov eax,60
    .byte 0x0F,0x05                  # syscall
elf_template_end:

.section .bss
.align 64
max_cpuid:      .skip 4
max_extended_cpuid: .skip 4
feature_bits:   .skip 4
isa_cap_bits:   .skip 4
isa_limit_mode: .skip 4
cpu_family:     .skip 4
cpu_model:      .skip 4
cpu_stepping:   .skip 4
cache_line_bytes: .skip 4
l1d_bytes: .skip 8
l1i_bytes: .skip 8
l2_bytes: .skip 8
l3_bytes: .skip 8
l1d_share_threads: .skip 4
l2_share_threads: .skip 4
l3_share_threads: .skip 4
topology_leaf: .skip 4
threads_per_core: .skip 4
logical_per_package: .skip 4
cores_per_package: .skip 4
x2apic_id: .skip 4
profile_status: .skip 4
hot_loop_alignment: .skip 4
reduction_carriers: .skip 4
fp_add_latency_ticks: .skip 4
front_end_budget: .skip 4
simd_scan_width: .skip 4
scan_loop_bytes: .skip 4
scan_loads_per_block: .skip 4
scan_vector_compares_per_block: .skip 4
scan_vector_registers: .skip 4
scan_mask_registers: .skip 4
architectural_vector_registers: .skip 4
last_scan_path:  .skip 4
allowed_cpu_count: .skip 4
current_cpu: .skip 4
current_numa_node: .skip 4
numa_bind_ok: .skip 4
hugepage_advice_ok: .skip 4
page_size: .skip 8
numa_nodemask: .skip 8
source_length: .skip 8
execution_admission_capacity: .skip 4
.p2align 3
input_fd: .skip 8
fmt_result: .skip 8
exit_result: .skip 8
schedule_counts: .skip 40
schedule_bound_ticks: .skip 4
schedule_issue_bound_ticks: .skip 4
schedule_bound_cycles: .skip 4
schedule_bottleneck_id: .skip 4
group_body_cap: .skip 4
group_body_cost_ops: .skip 4
group_body_cost_bytes: .skip 4
group_carrier_cap: .skip 4
schedule_total_ops: .skip 4
schedule_estimated_code_bytes: .skip 4
# Automatic Grouping sparse compile-time facts. Logical axes stay in ShapeFact-N.
group_logical_rank: .skip 4
group_relation_mask: .skip 4
group_lane_factor: .skip 4
group_rank: .skip 4
group_form: .skip 4
group_body_factor: .skip 4
group_carrier_factor: .skip 4
group_cardinality_exact: .skip 4
.p2align 3
group_cardinality: .skip 8
vendor_string:  .skip 16
.align 64
source_ptr: .skip 8
source_alloc_size: .skip 8
source_dynamic: .skip 4
.align 4096
source_buffer:  .skip STATIC_SOURCE_CAP
.align 64
output_buffer:  .skip 256

