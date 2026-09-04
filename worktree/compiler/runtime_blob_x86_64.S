.intel_syntax noprefix
.section .rodata
.global runtime_template_blob
.global runtime_template_blob_end
runtime_template_blob:
.incbin "build/tensor_runtime_template"
runtime_template_blob_end:
