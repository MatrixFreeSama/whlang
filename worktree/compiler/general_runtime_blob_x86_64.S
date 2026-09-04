.intel_syntax noprefix
.section .rodata
.global general_runtime_blob
.global general_runtime_blob_end
general_runtime_blob:
.incbin "build/general_runtime_template"
general_runtime_blob_end:
