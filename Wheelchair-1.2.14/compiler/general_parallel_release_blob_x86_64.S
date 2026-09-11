.intel_syntax noprefix
.section .rodata
.p2align 6
.global general_parallel_release_blob
general_parallel_release_blob:
.incbin "build/general_parallel_release_template.bin"
.global general_parallel_release_blob_end
general_parallel_release_blob_end:
