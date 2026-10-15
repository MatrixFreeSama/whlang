.equ FIELD_LANES,8
.include "compiler/native256_physical_profile.inc"
.include "build/field_runtime_256_offsets.inc"
.include "compiler/field_frontend_common_x86_64.S"

.section .rodata
ff_runtime_f32_facts:
.include "build/field_runtime_256_facts.inc"
ff_runtime_f32_facts_end:
.include "build/field_runtime_256_f64_facts_offsets.inc"
ff_runtime_f64_facts:
.include "build/field_runtime_256_f64_facts.inc"

ff_codegen_f32_fragments:
    .quad cg_direct_gather256,cg_direct_gather256_end-cg_direct_gather256
    .quad cg_epilogue256,cg_epilogue256_end-cg_epilogue256
    .quad cg_regular_qaddr,cg_regular_qaddr_end-cg_regular_qaddr
    .quad cg_regular_load256,cg_regular_load256_end-cg_regular_load256
ff_codegen_f64_fragments:
    .quad cg_direct_gather_f64_256,cg_direct_gather_f64_256_end-cg_direct_gather_f64_256
    .quad cg_epilogue_f64_256,cg_epilogue_f64_256_end-cg_epilogue_f64_256
    .quad cg_regular_qaddr_f64,4
    .quad cg_regular_load_f64_256,cg_regular_load_f64_256_end-cg_regular_load_f64_256
