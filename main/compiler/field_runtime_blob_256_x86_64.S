.intel_syntax noprefix
.section .rodata
.global field_runtime_template_blob
.global field_runtime_template_blob_end
field_runtime_template_blob:
.incbin "build/field_runtime_256_template"
field_runtime_template_blob_end:

.global field_runtime_f64_template_blob
field_runtime_f64_template_blob:
.incbin "build/field_runtime_256_f64_template"
