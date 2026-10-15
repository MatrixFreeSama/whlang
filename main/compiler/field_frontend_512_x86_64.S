.equ FIELD_LANES,16
.include "build/field_runtime_512_offsets.inc"
.include "compiler/field_frontend_common_x86_64.S"

.section .rodata
ff_runtime_f32_facts:
.include "build/field_runtime_512_facts.inc"
ff_runtime_f32_facts_end:
.include "build/field_runtime_512_f64_facts_offsets.inc"
ff_runtime_f64_facts:
.include "build/field_runtime_512_f64_facts.inc"

ff_codegen_f32_fragments:
    .quad cg_direct_gather512,cg_direct_gather512_end-cg_direct_gather512
    .quad cg_epilogue512,cg_epilogue512_end-cg_epilogue512
    .quad cg_regular_qaddr,cg_regular_qaddr_end-cg_regular_qaddr
    .quad cg_regular_load512,cg_regular_load512_end-cg_regular_load512
ff_codegen_f64_fragments:
    .quad cg_direct_gather_f64_512,cg_direct_gather_f64_512_end-cg_direct_gather_f64_512
    .quad cg_epilogue_f64_512,cg_epilogue_f64_512_end-cg_epilogue_f64_512
    .quad cg_regular_qaddr_f64,4
    .quad cg_regular_load_f64_512,cg_regular_load_f64_512_end-cg_regular_load_f64_512
