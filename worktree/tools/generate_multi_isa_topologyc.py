#!/usr/bin/env python3
"""Generate the 1.2.7 topology compiler with workload-blind physical ISA mapping.

The handwritten compiler remains the native authority. This build-time generator
only specializes the assembly source around silicon classification and resource
costs; it never emits user program machine code at runtime.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
src_path = ROOT / "compiler" / "topologyc_x86_64.S"
out_path = ROOT / "build" / "topologyc_multi_isa_x86_64.S"
s = src_path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global s
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {n}")
    s = s.replace(old, new, 1)


replace_once(
    '.include "compiler/isa_capabilities.inc"\n',
    '.include "compiler/isa_capabilities.inc"\n.include "compiler/physical_vector_shapes.inc"\n',
    "physical-shape include",
)
replace_once(
    '.global schedule_unroll\n',
    '.global schedule_unroll\n.global physical_vector_shape\n.global physical_vector_lanes\n.global physical_datapath_bits\n.global physical_vector_uops_per_semantic\n',
    "physical-shape globals",
)

start = s.index("select_silicon_profile:\n")
end = s.index("\nprepare_source_memory:\n", start)
new_select = r'''select_silicon_profile:
    # Workload-blind physical vector-shape selection.  CPUID/vendor information
    # is used only to establish hardware datapath shape and issue geometry.
    mov dword ptr [rip+profile_id], SILICON_PROFILE_GENERIC
    mov dword ptr [rip+profile_status], 0
    mov dword ptr [rip+physical_vector_shape], PHYS_VEC_UNKNOWN
    mov dword ptr [rip+physical_vector_lanes], 1
    mov dword ptr [rip+physical_datapath_bits], 0
    mov dword ptr [rip+physical_vector_uops_per_semantic], 1
    mov dword ptr [rip+hot_loop_alignment], 32
    mov dword ptr [rip+reduction_carriers], 4
    mov dword ptr [rip+front_end_budget], 32
    mov dword ptr [rip+vector_fp_issue_ticks], 6
    mov dword ptr [rip+vector_int_issue_ticks], 3
    mov dword ptr [rip+vector_mul_issue_ticks], 6
    mov dword ptr [rip+vector_load_issue_ticks], 6
    mov dword ptr [rip+vector_agu_issue_ticks], 4
    mov dword ptr [rip+reduction_latency_ticks], 36
    mov dword ptr [rip+scan_loop_bytes], 0
    mov dword ptr [rip+scan_loads_per_block], 0
    mov dword ptr [rip+scan_vector_compares_per_block], 0
    mov dword ptr [rip+scan_vector_registers], 0
    mov dword ptr [rip+scan_mask_registers], 0

    # AuthenticAMD. Family 19h is split by architectural AVX-512 presence:
    # Zen3 is AVX2-only; Zen4/4c expose AVX-512 over 256-bit datapaths.
    cmp dword ptr [rip+vendor_string+0], 0x68747541   # Auth
    jne .ssp_try_intel
    cmp dword ptr [rip+vendor_string+4], 0x69746e65   # enti
    jne .ssp_try_intel
    cmp dword ptr [rip+vendor_string+8], 0x444d4163   # cAMD
    jne .ssp_try_intel
    mov eax,dword ptr [rip+cpu_family]
    cmp eax,0x1a
    jae .ssp_amd_zen5
    cmp eax,0x19
    je .ssp_amd_family19
    cmp eax,0x17
    je .ssp_amd_prezen4
    jmp .ssp_width

.ssp_amd_zen5:
    mov eax,dword ptr [rip+feature_bits]
    bt eax,3
    jnc .ssp_amd_native256_if_avx2
    mov dword ptr [rip+profile_id], SILICON_PROFILE_AMD_ZEN5_NATIVE512
    mov dword ptr [rip+profile_status], 1
    mov dword ptr [rip+physical_vector_shape], PHYS_VEC_NATIVE512
    mov dword ptr [rip+physical_vector_lanes], 8
    mov dword ptr [rip+physical_datapath_bits], 512
    mov dword ptr [rip+physical_vector_uops_per_semantic], 1
    mov dword ptr [rip+hot_loop_alignment], 64
    mov dword ptr [rip+front_end_budget], 64
    jmp .ssp_width

.ssp_amd_family19:
    mov eax,dword ptr [rip+feature_bits]
    bt eax,3
    jnc .ssp_amd_zen3
    mov dword ptr [rip+profile_id], SILICON_PROFILE_AMD_ZEN4_SPLIT512
    mov dword ptr [rip+profile_status], 1
    mov dword ptr [rip+physical_vector_shape], PHYS_VEC_SPLIT512X256
    mov dword ptr [rip+physical_vector_lanes], 8
    mov dword ptr [rip+physical_datapath_bits], 256
    mov dword ptr [rip+physical_vector_uops_per_semantic], 2
    mov dword ptr [rip+hot_loop_alignment], 64
    mov dword ptr [rip+reduction_carriers], 6
    mov dword ptr [rip+front_end_budget], 64
    # One semantic 512-bit vector consumes two 256-bit physical slices.
    mov dword ptr [rip+vector_fp_issue_ticks], 12
    mov dword ptr [rip+vector_int_issue_ticks], 6
    mov dword ptr [rip+vector_mul_issue_ticks], 12
    mov dword ptr [rip+vector_load_issue_ticks], 12
    jmp .ssp_width
.ssp_amd_zen3:
    mov dword ptr [rip+profile_id], SILICON_PROFILE_AMD_ZEN3_NATIVE256
    jmp .ssp_set_native256

.ssp_amd_prezen4:
    mov dword ptr [rip+profile_id], SILICON_PROFILE_AMD_PREZEN4_NATIVE256
.ssp_amd_native256_if_avx2:
    mov eax,dword ptr [rip+feature_bits]
    bt eax,1
    jnc .ssp_width
.ssp_set_native256:
    mov dword ptr [rip+profile_status], 1
    mov dword ptr [rip+physical_vector_shape], PHYS_VEC_NATIVE256
    mov dword ptr [rip+physical_vector_lanes], 4
    mov dword ptr [rip+physical_datapath_bits], 256
    mov dword ptr [rip+physical_vector_uops_per_semantic], 1
    mov dword ptr [rip+hot_loop_alignment], 32
    mov dword ptr [rip+front_end_budget], 32
    jmp .ssp_width

.ssp_try_intel:
    cmp dword ptr [rip+vendor_string+0], 0x756e6547   # Genu
    jne .ssp_width
    cmp dword ptr [rip+vendor_string+4], 0x49656e69   # ineI
    jne .ssp_width
    cmp dword ptr [rip+vendor_string+8], 0x6c65746e   # ntel
    jne .ssp_width
    mov eax,dword ptr [rip+feature_bits]
    bt eax,3
    jnc .ssp_intel_avx2
    mov dword ptr [rip+profile_id], SILICON_PROFILE_INTEL_NATIVE512
    mov dword ptr [rip+profile_status], 1
    mov dword ptr [rip+physical_vector_shape], PHYS_VEC_NATIVE512
    mov dword ptr [rip+physical_vector_lanes], 8
    mov dword ptr [rip+physical_datapath_bits], 512
    mov dword ptr [rip+physical_vector_uops_per_semantic], 1
    mov dword ptr [rip+hot_loop_alignment], 64
    mov dword ptr [rip+front_end_budget], 64
    jmp .ssp_width
.ssp_intel_avx2:
    bt eax,1
    jnc .ssp_width
    mov dword ptr [rip+profile_id], SILICON_PROFILE_INTEL_NATIVE256
    jmp .ssp_set_native256

.ssp_width:
    # Compiler source scanning follows architectural ISA availability, while the
    # physical profile above describes the user-kernel execution datapath.
    mov dword ptr [rip+simd_scan_width], 1
    mov eax, dword ptr [rip+feature_bits]
    bt eax, 4
    jnc .ssp_avx2
    mov dword ptr [rip+simd_scan_width], 64
    mov dword ptr [rip+scan_loop_bytes], silicon_hot_fused_scan_avx512_end-silicon_hot_fused_scan_avx512
    mov dword ptr [rip+scan_loads_per_block], 1
    mov dword ptr [rip+scan_vector_compares_per_block], 2
    mov dword ptr [rip+scan_vector_registers], 3
    mov dword ptr [rip+scan_mask_registers], 2
    ret
.ssp_avx2:
    bt eax, 1
    jnc .ssp_done
    mov dword ptr [rip+simd_scan_width], 32
    mov dword ptr [rip+scan_loop_bytes], silicon_hot_fused_scan_avx2_end-silicon_hot_fused_scan_avx2
    mov dword ptr [rip+scan_loads_per_block], 1
    mov dword ptr [rip+scan_vector_compares_per_block], 2
    mov dword ptr [rip+scan_vector_registers], 4
    mov dword ptr [rip+scan_mask_registers], 0
.ssp_done:
    ret
'''
s = s[:start] + new_select + s[end:]

# Resource-schedule constants become profile variables.  Counts remain semantic
# and workload-blind; only the physical issue cost changes.
for old, new, label in [
    ("mov eax, dword ptr [r8+0]\n    imul eax, eax, 6", "mov eax, dword ptr [r8+0]\n    imul eax, dword ptr [rip+vector_fp_issue_ticks]", "fp add ticks"),
    ("mov eax, dword ptr [r8+4]\n    imul eax, eax, 6", "mov eax, dword ptr [r8+4]\n    imul eax, dword ptr [rip+vector_fp_issue_ticks]", "fp mul ticks"),
    ("mov eax, dword ptr [r8+16]\n    imul eax, eax, 3", "mov eax, dword ptr [r8+16]\n    imul eax, dword ptr [rip+vector_int_issue_ticks]", "int alu ticks"),
    ("mov eax, dword ptr [r8+20]\n    imul eax, eax, 6", "mov eax, dword ptr [r8+20]\n    imul eax, dword ptr [rip+vector_mul_issue_ticks]", "int mul ticks"),
    ("mov eax, dword ptr [r8+28]\n    imul eax, eax, 6", "mov eax, dword ptr [r8+28]\n    imul eax, dword ptr [rip+vector_load_issue_ticks]", "load ticks"),
    ("mov eax, dword ptr [r8+32]\n    imul eax, eax, 4", "mov eax, dword ptr [r8+32]\n    imul eax, dword ptr [rip+vector_agu_issue_ticks]", "agu ticks"),
    ("mov eax, 36\n    lea edx, [rcx-1]", "mov eax, dword ptr [rip+reduction_latency_ticks]\n    lea edx, [rcx-1]", "reduction latency"),
]:
    replace_once(old, new, label)

# Add physical-shape fields to silicon audit JSON before scan-loop details.
needle = '''    lea rdi, [rip+audit_carriers]\n    mov esi, audit_carriers_end-audit_carriers\n    mov edx, dword ptr [rip+reduction_carriers]\n    call print_json_num_field\n'''
insert = needle + '''    lea rdi, [rip+audit_phys_shape]\n    mov esi, audit_phys_shape_end-audit_phys_shape\n    mov edx, dword ptr [rip+physical_vector_shape]\n    call print_json_num_field\n    lea rdi, [rip+audit_phys_lanes]\n    mov esi, audit_phys_lanes_end-audit_phys_lanes\n    mov edx, dword ptr [rip+physical_vector_lanes]\n    call print_json_num_field\n    lea rdi, [rip+audit_phys_bits]\n    mov esi, audit_phys_bits_end-audit_phys_bits\n    mov edx, dword ptr [rip+physical_datapath_bits]\n    call print_json_num_field\n    lea rdi, [rip+audit_phys_uops]\n    mov esi, audit_phys_uops_end-audit_phys_uops\n    mov edx, dword ptr [rip+physical_vector_uops_per_semantic]\n    call print_json_num_field\n'''
replace_once(needle, insert, "audit physical fields")

# Expand profile-name reporting without changing strict-profile semantics.
old_profile_switch = '''    mov eax, dword ptr [rip+profile_id]\n    cmp eax, 1\n    jne .psa_generic\n    lea rdi, [rip+profile_zen4]\n    mov esi, profile_zen4_end-profile_zen4\n    call print_stdout\n    jmp .psa_status\n.psa_generic:\n    lea rdi, [rip+profile_generic]\n    mov esi, profile_generic_end-profile_generic\n    call print_stdout\n.psa_status:\n'''
new_profile_switch = '''    mov eax, dword ptr [rip+profile_id]\n    cmp eax,SILICON_PROFILE_AMD_ZEN4_SPLIT512\n    je .psa_zen4\n    cmp eax,SILICON_PROFILE_AMD_ZEN3_NATIVE256\n    je .psa_zen3\n    cmp eax,SILICON_PROFILE_AMD_ZEN5_NATIVE512\n    je .psa_zen5\n    cmp eax,SILICON_PROFILE_INTEL_NATIVE256\n    je .psa_intel256\n    cmp eax,SILICON_PROFILE_INTEL_NATIVE512\n    je .psa_intel512\n    cmp eax,SILICON_PROFILE_AMD_PREZEN4_NATIVE256\n    je .psa_amdpre\n    jmp .psa_generic\n.psa_zen4:\n    lea rdi,[rip+profile_zen4]; mov esi,profile_zen4_end-profile_zen4; call print_stdout; jmp .psa_status\n.psa_zen3:\n    lea rdi,[rip+profile_zen3]; mov esi,profile_zen3_end-profile_zen3; call print_stdout; jmp .psa_status\n.psa_zen5:\n    lea rdi,[rip+profile_zen5]; mov esi,profile_zen5_end-profile_zen5; call print_stdout; jmp .psa_status\n.psa_intel256:\n    lea rdi,[rip+profile_intel256]; mov esi,profile_intel256_end-profile_intel256; call print_stdout; jmp .psa_status\n.psa_intel512:\n    lea rdi,[rip+profile_intel512]; mov esi,profile_intel512_end-profile_intel512; call print_stdout; jmp .psa_status\n.psa_amdpre:\n    lea rdi,[rip+profile_amdpre]; mov esi,profile_amdpre_end-profile_amdpre; call print_stdout; jmp .psa_status\n.psa_generic:\n    lea rdi, [rip+profile_generic]\n    mov esi, profile_generic_end-profile_generic\n    call print_stdout\n.psa_status:\n'''
replace_once(old_profile_switch, new_profile_switch, "profile audit switch")

old_profiles = '''profile_zen4: .ascii "amd-zen4-family19h-model11h"\nprofile_zen4_end:\nprofile_generic: .ascii "generic-cross-vendor-x86_64"\nprofile_generic_end:\n'''
new_profiles = '''profile_zen4: .ascii "amd-zen4-split512x256"\nprofile_zen4_end:\nprofile_zen3: .ascii "amd-zen3-native256"\nprofile_zen3_end:\nprofile_zen5: .ascii "amd-zen5-native512"\nprofile_zen5_end:\nprofile_intel256: .ascii "intel-avx2-native256"\nprofile_intel256_end:\nprofile_intel512: .ascii "intel-avx512-native512"\nprofile_intel512_end:\nprofile_amdpre: .ascii "amd-zen1-zen2-native256"\nprofile_amdpre_end:\nprofile_generic: .ascii "generic-cross-vendor-x86_64"\nprofile_generic_end:\n'''
replace_once(old_profiles, new_profiles, "profile strings")

replace_once(
    'audit_carriers_end:\n',
    'audit_carriers_end:\naudit_phys_shape: .ascii ",\\"physical_vector_shape_id\\":"\naudit_phys_shape_end:\naudit_phys_lanes: .ascii ",\\"semantic_f64_lanes\\":"\naudit_phys_lanes_end:\naudit_phys_bits: .ascii ",\\"physical_datapath_bits\\":"\naudit_phys_bits_end:\naudit_phys_uops: .ascii ",\\"physical_vector_uops_per_semantic\\":"\naudit_phys_uops_end:\n',
    "audit field strings",
)

# The old schedule JSON claimed Zen4 even on non-Zen4 hosts.  Make the header
# architecture-neutral; detailed physical shape is emitted as a numeric field.
replace_once(
    'sched_head: .ascii "{\\"format\\":\\"topology.resource-schedule/1\\",\\"profile\\":\\"amd-zen4-family19h-model11h\\""\n',
    'sched_head: .ascii "{\\"format\\":\\"topology.resource-schedule/2\\",\\"profile\\":\\"physical-shape-aot\\""\n',
    "schedule header",
)
needle_sched = '''    lea rdi, [rip+sched_simd]\n    mov esi, sched_simd_end-sched_simd\n    mov edx, dword ptr [rip+simd_scan_width]\n    call print_json_num_field\n'''
replace_once(
    needle_sched,
    needle_sched + '''    lea rdi,[rip+sched_phys_shape]\n    mov esi,sched_phys_shape_end-sched_phys_shape\n    mov edx,dword ptr [rip+physical_vector_shape]\n    call print_json_num_field\n''',
    "schedule physical shape field",
)
replace_once(
    'sched_simd_end:\n',
    'sched_simd_end:\nsched_phys_shape: .ascii ",\\"physical_vector_shape_id\\":"\nsched_phys_shape_end:\n',
    "schedule shape string",
)

# Add physical-profile state and issue-cost variables to BSS.
replace_once(
    '.section .bss\n',
    '.section .bss\n.align 4\nphysical_vector_shape: .zero 4\nphysical_vector_lanes: .zero 4\nphysical_datapath_bits: .zero 4\nphysical_vector_uops_per_semantic: .zero 4\nvector_fp_issue_ticks: .zero 4\nvector_int_issue_ticks: .zero 4\nvector_mul_issue_ticks: .zero 4\nvector_load_issue_ticks: .zero 4\nvector_agu_issue_ticks: .zero 4\nreduction_latency_ticks: .zero 4\n',
    "physical profile BSS",
)

out_path.write_text(s, encoding="utf-8")
print("MULTI_ISA_TOPOLOGYC_GENERATION=PASS")
print("PHYSICAL_VECTOR_SHAPES=native256,split512x256,native512")
print("WORKLOAD_DISPATCH=0")
print("RUNTIME_PROFITABILITY_SELECTOR=0")
