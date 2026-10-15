# One typed InputFact comparison relation, instantiated at compile time and
# cold runtime admission. rax=payload, edi=natural type, rsi=lo/hi/flags.
# edx=0 accepted / 1 rejected. No user computation or cache is involved.
.macro INPUT_RANGE_RELATION name
\name:
    xor edx,edx
    cmp qword ptr [rsi+16],0; je .irr_ok\@
    cmp edi,4; je .irr_f32\@
    cmp edi,5; je .irr_f64\@
    cmp edi,2; je .irr_i64\@
    cmp edi,1; je .irr_uint\@
    cmp edi,3; jne .irr_bad\@
.irr_uint\@:
    test qword ptr [rsi+16],1; jz .irr_umax\@
    cmp rax,[rsi]; jb .irr_bad\@
.irr_umax\@:
    test qword ptr [rsi+16],2; jz .irr_ok\@
    cmp rax,[rsi+8]; ja .irr_bad\@
    ret
.irr_i64\@:
    test qword ptr [rsi+16],1; jz .irr_imax\@
    cmp rax,[rsi]; jl .irr_bad\@
.irr_imax\@:
    test qword ptr [rsi+16],2; jz .irr_ok\@
    cmp rax,[rsi+8]; jg .irr_bad\@
    ret
.irr_f32\@:
    movd xmm0,eax
    test qword ptr [rsi+16],1; jz .irr_f32max\@
    ucomiss xmm0,[rsi]; jp .irr_bad\@; jb .irr_bad\@
.irr_f32max\@:
    test qword ptr [rsi+16],2; jz .irr_ok\@
    ucomiss xmm0,[rsi+8]; jp .irr_bad\@; ja .irr_bad\@
    ret
.irr_f64\@:
    movq xmm0,rax
    test qword ptr [rsi+16],1; jz .irr_f64max\@
    ucomisd xmm0,[rsi]; jp .irr_bad\@; jb .irr_bad\@
.irr_f64max\@:
    test qword ptr [rsi+16],2; jz .irr_ok\@
    ucomisd xmm0,[rsi+8]; jp .irr_bad\@; ja .irr_bad\@
.irr_ok\@:
    ret
.irr_bad\@:
    mov edx,1; ret
.endm
