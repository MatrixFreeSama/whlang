.intel_syntax noprefix
.include "compiler/silicon_reality.inc"

# External target facts for an exposed reconfigurable-fabric domain.
# These are build-target facts, never source/program annotations.  Production
# defaults are deliberately zero: an absent or unproved fabric cannot be
# manufactured by the compiler.  Board/tool integration may provide the same
# facts with assembler --defsym values when it has measured/declared authority.
.ifndef FABRIC_TARGET_PRESENT
.equ FABRIC_TARGET_PRESENT,0
.endif
.ifndef FABRIC_LOGIC_UNITS
.equ FABRIC_LOGIC_UNITS,0
.endif
.ifndef FABRIC_REGISTER_UNITS
.equ FABRIC_REGISTER_UNITS,0
.endif
.ifndef FABRIC_DSP_UNITS
.equ FABRIC_DSP_UNITS,0
.endif
.ifndef FABRIC_LOCAL_STORAGE_BYTES
.equ FABRIC_LOCAL_STORAGE_BYTES,0
.endif
.ifndef FABRIC_ROUTING_DOMAINS
.equ FABRIC_ROUTING_DOMAINS,0
.endif
.ifndef FABRIC_CLOCK_REGIONS
.equ FABRIC_CLOCK_REGIONS,0
.endif
.ifndef FABRIC_COMPUTE_TICKS_NUM
.equ FABRIC_COMPUTE_TICKS_NUM,0
.endif
.ifndef FABRIC_COMPUTE_TICKS_DEN
.equ FABRIC_COMPUTE_TICKS_DEN,0
.endif
.ifndef FABRIC_ACTIVATION_TICKS
.equ FABRIC_ACTIVATION_TICKS,0
.endif
.ifndef FABRIC_TRANSPORT_FIXED_TICKS
.equ FABRIC_TRANSPORT_FIXED_TICKS,0
.endif
.ifndef FABRIC_TRANSPORT_TICKS_PER_BYTE
.equ FABRIC_TRANSPORT_TICKS_PER_BYTE,0
.endif

.section .text
.global fabric_target_facts_proved
.type fabric_target_facts_proved,@function
fabric_target_facts_proved:
    cmp dword ptr [rip+ft_present],1
    jne .ftfp_no
    cmp qword ptr [rip+ft_logic_units],0
    je .ftfp_no
    cmp qword ptr [rip+ft_register_units],0
    je .ftfp_no
    cmp dword ptr [rip+ft_routing_domains],0
    je .ftfp_no
    cmp dword ptr [rip+ft_clock_regions],0
    je .ftfp_no
    cmp qword ptr [rip+ft_compute_ticks_num],0
    je .ftfp_no
    cmp qword ptr [rip+ft_compute_ticks_den],0
    je .ftfp_no
    mov eax,1
    ret
.ftfp_no:
    xor eax,eax
    ret

.section .rodata
.p2align 3
.global ft_present
ft_present: .long FABRIC_TARGET_PRESENT
.global ft_routing_domains
ft_routing_domains: .long FABRIC_ROUTING_DOMAINS
.global ft_clock_regions
ft_clock_regions: .long FABRIC_CLOCK_REGIONS
.p2align 3
.global ft_logic_units
ft_logic_units: .quad FABRIC_LOGIC_UNITS
.global ft_register_units
ft_register_units: .quad FABRIC_REGISTER_UNITS
.global ft_dsp_units
ft_dsp_units: .quad FABRIC_DSP_UNITS
.global ft_local_storage_bytes
ft_local_storage_bytes: .quad FABRIC_LOCAL_STORAGE_BYTES
.global ft_compute_ticks_num
ft_compute_ticks_num: .quad FABRIC_COMPUTE_TICKS_NUM
.global ft_compute_ticks_den
ft_compute_ticks_den: .quad FABRIC_COMPUTE_TICKS_DEN
.global ft_activation_ticks
ft_activation_ticks: .quad FABRIC_ACTIVATION_TICKS
.global ft_transport_fixed_ticks
ft_transport_fixed_ticks: .quad FABRIC_TRANSPORT_FIXED_TICKS
.global ft_transport_ticks_per_byte
ft_transport_ticks_per_byte: .quad FABRIC_TRANSPORT_TICKS_PER_BYTE

.section .note.GNU-stack,"",@progbits
