.intel_syntax noprefix
# One canonical ReductionFact frontier. Consumed-leaf count is its occupied
# level bitmap; left blocks are older than the incoming right block. The u64
# leaf domain bounds storage at 64 f64 levels. Caller supplies a free temporary.
.macro REDUCTION_FRONTIER_INSERT count, temp
    xor ecx,ecx
.Lrfi_merge_\@:
    bt \count,rcx
    jnc .Lrfi_store_\@
    vmovsd \temp,qword ptr [rsp+rcx*8]
    vaddsd xmm0,\temp,xmm0
    inc ecx
    jmp .Lrfi_merge_\@
.Lrfi_store_\@:
    vmovsd qword ptr [rsp+rcx*8],xmm0
    inc \count
.endm

.macro REDUCTION_FRONTIER_FINISH count, temp
    bsf rcx,\count
    vmovsd xmm0,qword ptr [rsp+rcx*8]
    btr \count,rcx
    test \count,\count
    jz .Lrff_done_\@
.Lrff_merge_\@:
    bsf rcx,\count
    vmovsd \temp,qword ptr [rsp+rcx*8]
    vaddsd xmm0,\temp,xmm0
    btr \count,rcx
    test \count,\count
    jnz .Lrff_merge_\@
.Lrff_done_\@:
.endm
