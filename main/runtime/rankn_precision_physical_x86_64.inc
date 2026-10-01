# Wheelchair parameterized Rank-N floating physical authority.
# Any floating precision wider than the native 64-bit lane is represented by
# one logical ValueFact whose significand is a Rank-N limb axis. Type identity
# is compact; precision is an independent u64 Physical Fact in the program
# trailer and is copied once into each hot object header. Fourier geometry is
# type-level Physical Fact data and is never duplicated in ValueFacts.
#
# Object layout:
#   +0  u32 interned semantic type identity
#   +4  u32 alignment padding (no semantic state)
#   +8  u64 precision bits
#   +16 u64 sign (0/1)
#   +24 i64 unbiased exponent of normalized top significand bit
#   +32 primary little-endian u64 limbs
# Primary limb count is derived from precision and is never stored separately.

.equ RPF_TYPE_BASE,TYPE_STATIC_LAST+1
.equ RPF_TYPE,0
.equ RPF_PREC,8
.equ RPF_SIGN,16
.equ RPF_EXP,24
.equ RPF_DATA,32

.text

.macro RPF_SAVE
    push rbx
    push rbp
    push r11
    push r12
    push r13
    push r14
    push r15
.endm
.macro RPF_RESTORE
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop rbp
    pop rbx
.endm

# edi=interned type -> rax=P or 0 invalid, edx=packed Fourier geometry.
# The exact program trailer stores one 16-byte TypePhysicalFact per fpP type;
# no bit mask, named-width ceiling, per-value geometry, or runtime planner exists.
rpf_precision_from_type:
    cmp edi,RPF_TYPE_BASE
    jb .rpft_bad
    mov eax,edi
    sub eax,RPF_TYPE_BASE
    jc .rpft_bad
    cmp eax,dword ptr [rip+rankn_type_count_patch]
    jae .rpft_bad
    mov rcx,qword ptr [rip+rankn_physical_fact_ptr]
    test rcx,rcx
    jz .rpft_bad
    shl rax,4
    mov edx,dword ptr [rcx+rax+8]
    mov rax,qword ptr [rcx+rax]
    cmp rax,64
    jbe .rpft_bad
    ret
.rpft_bad:
    xor eax,eax
    xor edx,edx
    ret

# edi=interned type -> rax=ceil(P/64), 0 invalid.
rpf_limbs_from_type:
    call rpf_precision_from_type
    test rax,rax
    jz .rpfl_bad
    add rax,63
    jc .rpfl_bad
    shr rax,6
    ret
.rpfl_bad: xor eax,eax; ret

# rdi=ptr, rcx=count limbs
rpf_zero_limbs:
    xor eax,eax
    test rcx,rcx
    jz .rpzl_done
.rpzl_loop:
    mov [rdi],rax
    add rdi,8
    dec rcx
    jnz .rpzl_loop
.rpzl_done: ret

# rdi=object, rsi=u64 payload, rdx=left shift. Carrier must already be zero.
# A normalized <=64-bit source occupies at most two destination limbs.
rpf_deposit_u64_shifted:
    mov r8,rdx
    shr r8,6
    mov ecx,edx
    and ecx,63
    mov rax,rsi
    xor rdx,rdx
    shld rdx,rax,cl
    shl rax,cl
    mov [rdi+RPF_DATA+r8*8],rax
    test rdx,rdx
    jz .rpfdu_done
    mov [rdi+RPF_DATA+r8*8+8],rdx
.rpfdu_done:
    ret

# rdi=raw u64 limbs, rcx=N, edx=small addend (0..9) -> eax=overflow.
# Decimal ingress uses the exact recurrence D <- 10*D + digit directly on
# its integer carrier; no per-digit floating multiply/normalize episode exists.
rpf_raw_mul10_add:
    mov r8d,edx
    mov r10d,10
    xor r9d,r9d
.rpfr10_loop:
    cmp r9,rcx
    jae .rpfr10_done
    mov rax,[rdi+r9*8]
    mul r10
    add rax,r8
    adc rdx,0
    mov [rdi+r9*8],rax
    mov r8,rdx
    inc r9
    jmp .rpfr10_loop
.rpfr10_done:
    xor eax,eax
    test r8,r8
    setnz al
    ret

# rdi=ptr, rcx=count -> rax=msb bit index, -1 zero
rpf_msb:
    test rcx,rcx
    jz .rpfm_zero
    lea rdx,[rcx-1]
.rpfm_loop:
    mov rax,[rdi+rdx*8]
    test rax,rax
    jnz .rpfm_yes
    dec rdx
    jns .rpfm_loop
.rpfm_zero:
    mov eax,-1
    ret
.rpfm_yes:
    bsr rax,rax
    shl rdx,6
    add rax,rdx
    ret

# rdi=a,rsi=b,rcx=count -> eax -1/0/1 unsigned big-int compare
rpf_cmp:
    test rcx,rcx
    jz .rpfc_eq
    lea rdx,[rcx-1]
.rpfc_loop:
    mov rax,[rdi+rdx*8]
    mov r8,[rsi+rdx*8]
    cmp rax,r8
    ja .rpfc_gt
    jb .rpfc_lt
    dec rdx
    jns .rpfc_loop
.rpfc_eq: xor eax,eax; ret
.rpfc_gt: mov eax,1; ret
.rpfc_lt: mov eax,-1; ret

# rdi=a in/out,rsi=b,rcx=count -> carry eax 0/1
rpf_add_limbs:
    xor edx,edx
    test rcx,rcx
    jz .rpfal_done
    clc
.rpfal_loop:
    mov rax,[rsi]
    adc [rdi],rax
    lea rdi,[rdi+8]
    lea rsi,[rsi+8]
    dec rcx
    jnz .rpfal_loop
    setc dl
.rpfal_done: mov eax,edx; ret

# rdi=a in/out,rsi=b,rcx=count -> borrow eax 0/1, requires a>=b for no borrow
rpf_sub_limbs:
    xor edx,edx
    test rcx,rcx
    jz .rpfsl_done
    clc
.rpfsl_loop:
    mov rax,[rsi]
    sbb [rdi],rax
    lea rdi,[rdi+8]
    lea rsi,[rsi+8]
    dec rcx
    jnz .rpfsl_loop
    setc dl
.rpfsl_done: mov eax,edx; ret

# rdi=dst, rsi=canonical src, rcx=src limbs, rdx=dst limbs, r8=signed shift.
# Materialize one operation-local exact carrier in one pass.  Positive shift
# moves left exactly; negative shift moves right and collapses every discarded
# low bit into sticky bit 0.  This is the Local-Strict physical projection used
# by add/sub: copy, guard extension, exponent alignment and sticky formation are
# one relation rather than four full-carrier episodes.
rpf_project_local_carrier:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov r15,rdi                  # dst
    mov rbx,rsi                  # src
    mov r12,rcx                  # src N
    mov r13,rdx                  # dst N
    mov r14,r8                   # signed shift
    test r14,r14
    js .rpfplc_right

    # Exact left projection.
    mov rbp,r14
    shr rbp,6                    # whole-limb displacement q
    mov r10d,r14d
    and r10d,63                  # intra-limb displacement r
    xor r11d,r11d                # destination i
.rpfplc_left_loop:
    cmp r11,r13
    jae .rpfplc_done
    xor eax,eax
    cmp r11,rbp
    jb .rpfplc_left_store
    mov r9,r11
    sub r9,rbp                   # nominal source j
    test r10d,r10d
    jz .rpfplc_left_direct
    # Current source contributes its low part when it exists.
    cmp r9,r12
    jae .rpfplc_left_prev
    mov rax,[rbx+r9*8]
    mov ecx,r10d
    shl rax,cl
.rpfplc_left_prev:
    # Previous source contributes the cross-limb high part even when j==srcN.
    test r9,r9
    jz .rpfplc_left_store
    lea rdx,[r9-1]
    cmp rdx,r12
    jae .rpfplc_left_store
    mov rdx,[rbx+rdx*8]
    mov ecx,64
    sub ecx,r10d
    shr rdx,cl
    or rax,rdx
    jmp .rpfplc_left_store
.rpfplc_left_direct:
    cmp r9,r12
    jae .rpfplc_left_store
    mov rax,[rbx+r9*8]
.rpfplc_left_store:
    mov [r15+r11*8],rax
    inc r11
    jmp .rpfplc_left_loop

.rpfplc_right:
    neg r14                     # positive right distance
    xor ebp,ebp                 # sticky accumulator in rbp
    test r12,r12
    jz .rpfplc_zero_dst
    mov rax,r12
    shl rax,6
    cmp r14,rax
    jb .rpfplc_right_partial
    # Entire source is discarded; only sticky survives.
    xor r11d,r11d
.rpfplc_all_sticky:
    cmp r11,r12
    jae .rpfplc_zero_dst
    or rbp,[rbx+r11*8]
    inc r11
    jmp .rpfplc_all_sticky

.rpfplc_right_partial:
    mov r9,r14
    shr r9,6                    # q
    mov r10d,r14d
    and r10d,63                 # r
    xor r11d,r11d
.rpfplc_sticky_words:
    cmp r11,r9
    jae .rpfplc_sticky_bits
    or rbp,[rbx+r11*8]
    inc r11
    jmp .rpfplc_sticky_words
.rpfplc_sticky_bits:
    test r10d,r10d
    jz .rpfplc_right_move
    mov rax,[rbx+r9*8]
    mov ecx,r10d
    mov rdx,1
    shl rdx,cl
    dec rdx
    and rax,rdx
    or rbp,rax
.rpfplc_right_move:
    xor r11d,r11d               # destination i
.rpfplc_right_loop:
    cmp r11,r13
    jae .rpfplc_finish_sticky
    lea r8,[r11+r9]             # source j=i+q
    xor eax,eax
    cmp r8,r12
    jae .rpfplc_right_store
    mov rax,[rbx+r8*8]
    test r10d,r10d
    jz .rpfplc_right_store
    mov ecx,r10d
    shr rax,cl
    lea rdx,[r8+1]
    cmp rdx,r12
    jae .rpfplc_right_store
    mov rdx,[rbx+rdx*8]
    mov ecx,64
    sub ecx,r10d
    shl rdx,cl
    or rax,rdx
.rpfplc_right_store:
    mov [r15+r11*8],rax
    inc r11
    jmp .rpfplc_right_loop

.rpfplc_zero_dst:
    xor r11d,r11d
.rpfplc_zero_loop:
    cmp r11,r13
    jae .rpfplc_finish_sticky
    mov qword ptr [r15+r11*8],0
    inc r11
    jmp .rpfplc_zero_loop
.rpfplc_finish_sticky:
    test rbp,rbp
    jz .rpfplc_done
    or qword ptr [r15],1
.rpfplc_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

# rdi=src, rcx=count, rdx=bit index -> eax 0/1
rpf_test_bit:
    test rdx,rdx
    js .rpftb_zero
    mov rax,rdx
    shr rax,6
    cmp rax,rcx
    jae .rpftb_zero
    mov r8,rdx
    and r8d,63
    mov rax,[rdi+rax*8]
    mov rcx,r8
    shr rax,cl
    and eax,1
    ret
.rpftb_zero: xor eax,eax; ret

# rdi=src, rcx=count, rdx=number of lowest bits -> eax nonzero if any set.
rpf_any_low_bits:
    test rdx,rdx
    jle .rpfalb_zero
    mov r8,rdx
    shr r8,6                 # full limbs
    xor r9d,r9d
    xor eax,eax
.rpfalb_full:
    cmp r9,r8
    jae .rpfalb_rem
    cmp r9,rcx
    jae .rpfalb_zero
    or rax,[rdi+r9*8]
    inc r9
    jmp .rpfalb_full
.rpfalb_rem:
    test rax,rax
    jnz .rpfalb_yes
    mov r10,rdx
    and r10d,63
    jz .rpfalb_zero
    cmp r8,rcx
    jae .rpfalb_zero
    mov rax,[rdi+r8*8]
    mov rcx,r10
    mov r11,-1
    shl r11,cl
    not r11
    test rax,r11
    setnz al
    movzx eax,al
    ret
.rpfalb_yes: mov eax,1; ret
.rpfalb_zero: xor eax,eax; ret

# rdi=dst, esi=interned type. Initialize semantic header only.
# The primary carrier is deliberately untouched: strict closures that overwrite
# every live limb must not pay an otherwise dead zero-fill pass.
rpf_object_header_init:
    push rbx
    push r12
    mov r12,rdi
    mov ebx,esi
    mov edi,esi
    call rpf_precision_from_type
    test rax,rax
    jz .rpfoh_bad
    mov [r12+RPF_PREC],rax
    mov [r12+RPF_TYPE],ebx
    mov qword ptr [r12+RPF_SIGN],0
    mov qword ptr [r12+RPF_EXP],0
    xor eax,eax
    jmp .rpfoh_done
.rpfoh_bad: mov eax,1
.rpfoh_done:
    pop r12
    pop rbx
    ret

# rdi=dst, esi=interned type. Initialize header and a canonical zero carrier.
# Zero constructors keep the direct hot path; strict nonzero closures use the
# header-only entry above and therefore never pay this zero-fill.
rpf_object_init:
    push rbx
    push r12
    mov r12,rdi
    mov ebx,esi
    mov edi,esi
    call rpf_precision_from_type
    test rax,rax
    jz .rpfoi_bad
    mov [r12+RPF_PREC],rax
    mov [r12+RPF_TYPE],ebx
    mov rcx,rax
    add rcx,63
    jc .rpfoi_bad
    shr rcx,6
    mov qword ptr [r12+RPF_SIGN],0
    mov qword ptr [r12+RPF_EXP],0
    lea rdi,[r12+RPF_DATA]
    call rpf_zero_limbs
    xor eax,eax
    jmp .rpfoi_done
.rpfoi_bad: mov eax,1
.rpfoi_done:
    pop r12
    pop rbx
    ret

# rdi=dst, rsi=src ptr, edx=src limb count, ecx=sign,
# r8=signed binary scale K where value=src_integer*2^K, r9d=dest encoded type.
# Correctly rounds to destination precision with round-to-nearest-even.
rpf_round_from_integer:
    mov r10d,-1               # producer did not preserve a top-bit fact
    jmp .rpfr_entry
# Same strict closure with a producer-supplied exact source top bit in r10d.
# This is not a second rounding path; it only skips physical rediscovery.
rpf_round_from_integer_known_top:
.rpfr_entry:
    RPF_SAVE
    sub rsp,48
    mov r12,rdi
    mov r13,rsi
    mov r14d,edx
    mov [rsp],rcx             # sign
    mov [rsp+8],r8            # K
    mov r15d,r9d
    test r10d,r10d
    jns .rpfr_top_known
    mov rdi,r13
    mov ecx,r14d
    call rpf_msb
    test eax,eax
    js .rpfr_zero
    jmp .rpfr_top_ready
.rpfr_top_known:
    mov eax,r10d
.rpfr_top_ready:
    mov ebx,eax               # source top bit t
    mov [rsp+24],eax          # preserve t across generic copy loops
    mov rdi,r12
    mov esi,r15d
    call rpf_object_header_init
    test eax,eax
    jnz .rpfr_bad
    mov eax,[r12+RPF_PREC]
    mov ebp,eax               # P
    mov rcx,[r12+RPF_PREC]
    add rcx,63
    shr rcx,6
    mov [rsp+32],rcx          # N is immutable throughout rounding
    # Header-only init keeps the primary carrier untouched.  The common
    # right-shift closure overwrites every live limb exactly once.
    # shift = t-(P-1)
    mov eax,ebp
    dec eax
    mov edx,ebx
    sub edx,eax
    mov [rsp+16],edx          # signed shift
    test edx,edx
    js .rpfr_left
    # Right-shift copy by repeating source copy into destination scratch then shift.
    # First copy low N limbs from source; source may have more limbs, so use a temporary
    # region immediately after primary payload with src_limbs capacity.
    mov rcx,[rsp+32]
    lea rdi,[r12+RPF_DATA]
    xor eax,eax
    # generic bit extraction: destination bit j gets source bit j+shift.
    xor r10d,r10d
.rpfr_r_word:
    cmp r10d,ecx
    jae .rpfr_r_round
    mov eax,r10d
    shl eax,6
    add eax,[rsp+16]
    mov r11d,eax
    shr r11d,6
    mov r9d,eax
    and r9d,63
    xor rax,rax
    cmp r11d,r14d
    jae .rpfr_r_store
    mov rax,[r13+r11*8]
    test r9d,r9d
    jz .rpfr_r_store
    mov ecx,r9d
    shr rax,cl
    lea edx,[r11+1]
    cmp edx,r14d
    jae .rpfr_r_restorec
    mov rdx,[r13+rdx*8]
    mov ecx,64
    sub ecx,r9d
    shl rdx,cl
    or rax,rdx
.rpfr_r_restorec:
    mov rcx,[rsp+32]
.rpfr_r_store:
    mov [rdi+r10*8],rax
    inc r10d
    jmp .rpfr_r_word
.rpfr_r_round:
    mov edx,[rsp+16]
    test edx,edx
    jz .rpfr_store_meta
    dec edx
    mov rdi,r13
    mov ecx,r14d
    call rpf_test_bit
    mov [rsp+20],eax          # guard must survive sticky helper caller-saved scratch
    mov edx,[rsp+16]
    dec edx
    mov rdi,r13
    mov ecx,r14d
    call rpf_any_low_bits
    mov r11d,eax              # sticky below guard (function includes [0,edx), with edx=shift-1)
    cmp dword ptr [rsp+20],0
    je .rpfr_store_meta
    test r11d,r11d
    jnz .rpfr_inc
    test qword ptr [r12+RPF_DATA],1
    jz .rpfr_store_meta
.rpfr_inc:
    lea rdi,[r12+RPF_DATA]
    mov rcx,[rsp+32]
    mov rax,1
    clc
    xor r10d,r10d
.rpfr_inc_loop:
    cmp r10d,ecx
    jae .rpfr_inc_carry_out
    add [rdi+r10*8],rax
    setc al
    movzx rax,al
    test rax,rax
    jz .rpfr_inc_done
    inc r10d
    jmp .rpfr_inc_loop
.rpfr_inc_carry_out:
    test rax,rax
    jnz .rpfr_overflow
.rpfr_inc_done:
    # If rounding overflowed P bits, shift primary right one and exponent increments.
    mov eax,ebp
    mov edx,eax
    shr edx,6
    and eax,63
    test eax,eax
    jz .rpfr_check_fullword
    mov r10,[r12+RPF_DATA+rdx*8]
    bt r10,rax
    jnc .rpfr_store_meta
    jmp .rpfr_overflow
.rpfr_check_fullword:
    # P multiple of 64; overflow would be carry beyond N, already lost. Detect all-zero after wrap impossible here.
    jmp .rpfr_store_meta
.rpfr_overflow:
    # RNE overflow proves that every retained low bit wrapped to zero and the
    # only surviving information is the carry across bit P.  Close directly to
    # the normalized top bit instead of rescanning/shifting the whole carrier.
    mov eax,ebp
    dec eax
    mov edx,eax
    shr edx,6
    and eax,63
    mov r10,1
    mov ecx,eax
    shl r10,cl
    mov [r12+RPF_DATA+rdx*8],r10
    inc dword ptr [rsp+24]
    jmp .rpfr_store_meta
.rpfr_left:
    neg edx                    # left shift amount d
    mov [rsp+20],edx
    # The sparse left-deposit path ORs source pieces, so only this uncommon path
    # materializes a zero carrier.
    lea rdi,[r12+RPF_DATA]
    mov rcx,[rsp+32]
    call rpf_zero_limbs
    mov eax,[rsp+20]
    mov r10d,eax
    shr r10d,6                # word shift
    mov r11d,eax
    and r11d,63               # bit shift
    xor ebx,ebx               # source limb index
.rpfr_l_src:
    cmp ebx,r14d
    jae .rpfr_store_meta
    mov rax,[r13+rbx*8]
    test rax,rax
    jz .rpfr_l_next
    mov edx,ebx
    add edx,r10d
    mov rcx,[rsp+32]
    cmp rdx,rcx
    jae .rpfr_l_next
    test r11d,r11d
    jz .rpfr_l_direct
    mov ecx,r11d
    mov r8,rax
    shl r8,cl
    or [r12+RPF_DATA+rdx*8],r8
    inc edx
    mov rcx,[rsp+32]
    cmp rdx,rcx
    jae .rpfr_l_next
    mov ecx,64
    sub ecx,r11d
    shr rax,cl
    or [r12+RPF_DATA+rdx*8],rax
    jmp .rpfr_l_next
.rpfr_l_direct:
    or [r12+RPF_DATA+rdx*8],rax
.rpfr_l_next:
    inc ebx
    jmp .rpfr_l_src
.rpfr_store_meta:
    mov rax,[rsp]
    mov [r12+RPF_SIGN],rax
    mov rax,[rsp+8]
    movsxd rdx,dword ptr [rsp+24]
    add rax,rdx
    mov [r12+RPF_EXP],rax
    mov rax,r12
    xor edx,edx
    xor eax,eax                # status in eax for arithmetic users
    jmp .rpfr_done
.rpfr_zero:
    mov rdi,r12
    mov esi,r15d
    call rpf_object_init
    test eax,eax
    jnz .rpfr_bad
    xor eax,eax
    jmp .rpfr_done
.rpfr_bad:
    mov eax,1
.rpfr_done:
    add rsp,48
    RPF_RESTORE
    ret

# NOTE: left-shift normalization above is completed by this helper used by all
# public constructors. It creates a temporary integer already positioned so the
# common rounding path normally right-shifts or keeps position. Public arithmetic
# therefore never depends on the sparse .rpfr_left fallback.

# rdi=dest, rsi=u64, edx=encoded type -> rax=dest, edx status
.global rankn_fp_from_u64
rankn_fp_from_u64:
    RPF_SAVE
    sub rsp,16
    mov r12,rdi; mov r13,rsi; mov r14d,edx
    test r13,r13
    jz .rffu_zero
    mov [rsp],r13
    bsr rax,r13
    mov ebx,eax                # top bit of source
    mov edi,r14d
    call rpf_precision_from_type
    test eax,eax
    jz .rffu_bad
    mov ebp,eax
    mov rdi,r12; mov esi,r14d; call rpf_object_init; test eax,eax; jnz .rffu_bad
    mov [r12+RPF_SIGN],qword ptr 0
    mov [r12+RPF_EXP],rbx
    # Place source integer so its msb lands at P-1 in one at-most-two-limb deposit.
    mov eax,ebp; dec eax; sub eax,ebx
    mov edx,eax
    mov rdi,r12
    mov rsi,r13
    call rpf_deposit_u64_shifted
    mov rax,r12; xor edx,edx; jmp .rffu_done
.rffu_zero:
    mov rdi,r12; mov esi,r14d; call rpf_object_init; test eax,eax; jnz .rffu_bad
    mov rax,r12; xor edx,edx; jmp .rffu_done
.rffu_bad: xor eax,eax; mov edx,1
.rffu_done: add rsp,16; RPF_RESTORE; ret

.global rankn_fp_from_i64
rankn_fp_from_i64:
    push rbx
    mov rbx,rsi
    test rsi,rsi
    jns .rffi_pos
    neg rsi
.rffi_pos:
    call rankn_fp_from_u64
    test edx,edx
    jnz .rffi_done
    test rbx,rbx
    jns .rffi_done
    mov qword ptr [rax+RPF_SIGN],1
.rffi_done: pop rbx; ret

# rdi=dest,rsi=f64 bits,edx=encoded type -> rax=dest, edx status
.global rankn_fp_from_f64_bits
rankn_fp_from_f64_bits:
    RPF_SAVE
    mov r12,rdi; mov r13,rsi; mov r14d,edx
    mov rax,r13
    shr rax,52
    and eax,0x7ff
    cmp eax,0x7ff
    je .rffd_bad
    mov r15,r13; shr r15,63
    mov rbx,r13
    mov rcx,0x0007ffffffffffff
    and rbx,rcx
    test eax,eax
    jz .rffd_sub
    mov rcx,0x0010000000000000
    or rbx,rcx
    sub eax,1023
    mov ebp,eax                # top exponent E
    jmp .rffd_have
.rffd_sub:
    test rbx,rbx
    jz .rffd_zero
    bsr rcx,rbx
    mov ebp,-1074
    add ebp,ecx
.rffd_have:
    # Normalize integer mantissa into destination P bits.
    mov rdi,r12; mov esi,r14d; call rpf_object_init; test eax,eax; jnz .rffd_bad
    mov [r12+RPF_SIGN],r15
    movsxd rax,ebp; mov [r12+RPF_EXP],rax
    mov eax,[r12+RPF_PREC]; dec eax
    bsr rcx,rbx
    sub eax,ecx                # shift mantissa left
    mov edx,eax
    mov rdi,r12
    mov rsi,rbx
    call rpf_deposit_u64_shifted
    mov rax,r12; xor edx,edx; jmp .rffd_done
.rffd_zero:
    mov rdi,r12; mov esi,r14d; call rpf_object_init; test eax,eax; jnz .rffd_bad
    mov rax,r12; xor edx,edx; jmp .rffd_done
.rffd_bad: xor eax,eax; mov edx,1
.rffd_done: RPF_RESTORE; ret

# rdi=dst, rsi=src, edx=dest encoded type -> rax=dst, edx status
.global rankn_fp_convert
rankn_fp_convert:
    RPF_SAVE
    mov r12,rdi; mov r13,rsi; mov r14d,edx
    cmp dword ptr [r13+RPF_TYPE],r14d
    jne .rpfcv_rescale
    mov rdi,r12; mov rsi,r13; mov edx,r14d
    call rpf_copy_object
    test eax,eax
    jnz .rpfcv_bad
    mov rax,r12; xor edx,edx; jmp .rpfcv_done
.rpfcv_rescale:
    mov r15,[r13+RPF_PREC]
    add r15,63
    shr r15,6
    mov rax,[r13+RPF_EXP]
    mov ecx,[r13+RPF_PREC]
    dec ecx
    sub rax,rcx                # K = E-(Ps-1)
    mov r8,rax
    mov rcx,[r13+RPF_SIGN]
    lea rsi,[r13+RPF_DATA]
    mov edx,r15d
    mov rdi,r12
    mov r9d,r14d
    call rpf_round_from_integer
    test eax,eax
    jnz .rpfcv_bad
    mov rax,r12; xor edx,edx; jmp .rpfcv_done
.rpfcv_bad: xor eax,eax; mov edx,1
.rpfcv_done: RPF_RESTORE; ret

# Internal addition core. r10d=0 add,1 subtract b sign.
# Each operand is projected once from its canonical ValueFact into an operation-
# local guard/sticky carrier.  The local carrier may be noncanonical; it cannot
# escape this semantic operation and is closed by the one strict RNE authority.
rpf_add_core:
    RPF_SAVE
    sub rsp,48
    mov r12,rdi; mov r13,rsi; mov r14,rdx; mov r15d,ecx
    mov [rsp],r10d
    mov edi,r15d; call rpf_precision_from_type; test rax,rax; jz .rpfac_bad
    mov rbx,rax                              # destination PrecisionFact P
    mov rbp,rax; add rbp,63; shr rbp,6      # canonical limb count N
    cmp [r13+RPF_PREC],rbx; jne .rpfac_bad
    cmp [r14+RPF_PREC],rbx; jne .rpfac_bad

    # Operation-local carriers live after the primary destination payload.
    lea r8,[r12+RPF_DATA]
    mov rax,rbp; shl rax,3
    lea r9,[r8+rax]
    lea r11,[r9+rax+16]
    mov [rsp+8],r9
    mov [rsp+16],r11

    # Emax and the two signed local projections: 3-(Emax-Eoperand).
    mov rax,[r13+RPF_EXP]
    mov rdx,[r14+RPF_EXP]
    cmp rax,rdx
    jge .rpfac_emax_a
    mov [rsp+24],rdx
    mov rcx,rdx
    sub rcx,rax
    mov rax,3
    sub rax,rcx
    mov [rsp+32],rax                        # shift A
    mov qword ptr [rsp+40],3                # shift B
    jmp .rpfac_project
.rpfac_emax_a:
    mov [rsp+24],rax
    mov qword ptr [rsp+32],3                # shift A
    sub rax,rdx
    mov rcx,3
    sub rcx,rax
    mov [rsp+40],rcx                        # shift B

.rpfac_project:
    # A: canonical P-bit significand -> one local (N+2)-limb guard carrier.
    mov rdi,[rsp+8]
    lea rsi,[r13+RPF_DATA]
    mov rcx,rbp
    lea rdx,[rbp+2]
    mov r8,[rsp+32]
    call rpf_project_local_carrier
    # B: same relation, independently.  No copy/shift/alignment episodes remain.
    mov rdi,[rsp+16]
    lea rsi,[r14+RPF_DATA]
    mov rcx,rbp
    lea rdx,[rbp+2]
    mov r8,[rsp+40]
    call rpf_project_local_carrier

    mov r9,[rsp+8]
    mov r11,[rsp+16]
    mov rcx,[r13+RPF_SIGN]
    mov rdx,[r14+RPF_SIGN]
    xor edx,dword ptr [rsp]                 # subtract flips b sign bit
    cmp rcx,rdx
    jne .rpfac_sub
    mov rdi,r9; mov rsi,r11; lea ecx,[ebp+2]; call rpf_add_limbs
    mov r10,[r13+RPF_SIGN]
    jmp .rpfac_round
.rpfac_sub:
    mov rdi,r9; mov rsi,r11; lea ecx,[ebp+2]; call rpf_cmp
    test eax,eax
    jz .rpfac_zero
    js .rpfac_bigger_b
    mov rdi,r9; mov rsi,r11; lea ecx,[ebp+2]; call rpf_sub_limbs
    mov r10,[r13+RPF_SIGN]
    jmp .rpfac_round
.rpfac_bigger_b:
    mov rdi,r11; mov rsi,r9; lea ecx,[ebp+2]; call rpf_sub_limbs
    mov r9,r11
    mov r10,[r14+RPF_SIGN]
    xor r10d,[rsp]
.rpfac_round:
    # local carrier scale: Emax-(P-1)-3.  Strict closure owns normalization/RNE.
    mov r8,[rsp+24]
    mov eax,[r13+RPF_PREC]; dec eax; sub r8,rax; sub r8,3
    mov rdi,r12; mov rsi,r9; lea edx,[ebp+2]; mov rcx,r10; mov r9d,r15d
    call rpf_round_from_integer
    test eax,eax; jnz .rpfac_bad
    xor eax,eax; jmp .rpfac_done
.rpfac_zero:
    mov rdi,r12; mov esi,r15d; call rpf_object_init
    xor eax,eax; jmp .rpfac_done
.rpfac_bad: mov eax,1
.rpfac_done: add rsp,48; RPF_RESTORE; ret

.global rankn_fp_add
rankn_fp_add: xor r10d,r10d; jmp rpf_add_core
.global rankn_fp_sub
rankn_fp_sub: mov r10d,1; jmp rpf_add_core

# -----------------------------------------------------------------------------
# 1.3.40 high-precision multiplication is one native Fourier factorization.
# P is geometry data.  No alternate multiplication candidate, algorithm
# selector, or named-precision threshold exists.  Division keeps the common
# base-2^32 helpers below.
# -----------------------------------------------------------------------------

# Correct count-preserving base-2^32 shift helper used by Knuth division.
# Logical base-2^32 digits are physical dwords, not zero-extended qword slots.
rpf_shl32_slots2:
    push rbx; push rbp
    mov ebx,ecx; mov ebp,edx
    test ebp,ebp; jz .rs322_done
    xor r8d,r8d; xor r9d,r9d
.rs322_loop:
    cmp r8d,ebx; jae .rs322_done
    mov eax,dword ptr [rdi+r8*4]
    mov r10,rax; mov ecx,ebp; shl r10,cl; or r10,r9
    mov r9,r10; shr r9,32
    mov dword ptr [rdi+r8*4],r10d
    inc r8d; jmp .rs322_loop
.rs322_done:
    pop rbp; pop rbx; ret

# rdi=src64,esi=n64,edx=base32 digit -> eax digit.
rpf_get32:
    mov ecx,edx
    mov eax,edx; shr eax,1
    cmp eax,esi; jae .rg32_zero
    mov rax,[rdi+rax*8]
    test ecx,1; jz .rg32_done
    shr rax,32
.rg32_done:
    mov eax,eax
    ret
.rg32_zero: xor eax,eax; ret

# rdi=dst64,rsi=src base32 dwords,ecx=dst64 count,edx=src32 count.
# Each destination qword is written once from two compact 32-bit digits.
rpf_32_to_u64:
    xor r8d,r8d
.r32u_loop:
    cmp r8d,ecx
    jae .r32u_done
    lea r9d,[r8d+r8d]
    xor eax,eax
    cmp r9d,edx
    jae .r32u_store
    mov eax,dword ptr [rsi+r9*4]
    lea r10d,[r9d+1]
    cmp r10d,edx
    jae .r32u_store
    mov r11d,dword ptr [rsi+r10*4]
    shl r11,32
    or rax,r11
.r32u_store:
    mov [rdi+r8*8],rax
    inc r8d
    jmp .r32u_loop
.r32u_done:
    ret

# -----------------------------------------------------------------------------
# Native zero-algorithm-if Fourier product realization.
# The transform engine below is local x86-64 assembly.  Geometry is derived
# from P under one rounding-safety inequality and one physical cost surface.
# Forward DIF order is 5 -> 3 -> 2; inverse DIT is the exact reverse.  Packing
# z=a+i*b lets one forward transform and one inverse transform recover a*b from
# Im(F^-1(F(z)^2))/2, so no global permutation or conjugate-partner pass exists.
# -----------------------------------------------------------------------------
.equ G_B,0
.equ G_A2,4
.equ G_A3,8
.equ G_A5,12
.equ G_NCOEF,16
.equ G_NFFT,24
.equ G_SIZE,40

.section .rodata
.p2align 4
rpf_nf_neg_half: .double -0.5,-0.5
rpf_nf_k3_fwd:   .double 0.86602540378443864676,-0.86602540378443864676
rpf_nf_k3_inv:   .double -0.86602540378443864676,0.86602540378443864676
rpf_nf_c1:       .double 0.30901699437494742410,0.30901699437494742410
rpf_nf_c2:       .double -0.80901699437494742410,-0.80901699437494742410
rpf_nf_s1:       .double 0.95105651629515357212,0.95105651629515357212
rpf_nf_s2:       .double 0.58778525229247312917,0.58778525229247312917
rpf_nf_rot_fwd:  .double 1.0,-1.0
rpf_nf_rot_inv:  .double -1.0,1.0
rpf_nf_half:     .double 0.5

.text

.macro NF_CMUL out,a,w,t0,t1,t2
    vmovddup \t0, \w
    vpermilpd \t1, \w, 3
    vpermilpd \t2, \a, 1
    vmulpd \out, \a, \t0
    vmulpd \t2, \t2, \t1
    vaddsubpd \out, \out, \t2
.endm

# rdi=tw, rsi=m, rdx=len, ecx=inv(0 fwd / 1 inv)
# Extended-precision recurrence with periodic renormalization; no libm/runtime planner.
rpf_nf_make_tw:
    push rbx; push rbp; push r12; push r13; push r14; push r15
    sub rsp,96
    mov r12,rdi; mov r13,rsi; mov r14,rdx; mov r15d,ecx
    mov [rsp+0],rdx
    # One exact base-angle seed.  The fast binary64 recurrence below is
    # periodically re-anchored with x87 FSINCOS, so phase error cannot walk.
    fldpi
    fadd st(0),st(0)
    fild qword ptr [rsp+0]
    fdivp st(1),st(0)
    test r15d,r15d
    jnz .rpf_nmtf_sign_ok
    fchs
.rpf_nmtf_sign_ok:
    fstp tbyte ptr [rsp+16]                 # signed base angle
    fld tbyte ptr [rsp+16]
    fsincos
    fstp qword ptr [rsp+32]                 # wr
    fstp qword ptr [rsp+40]                 # wi
    vmovsd xmm2,[rsp+32]
    vmovsd xmm3,[rsp+40]
    # j=0 is the exact unit twiddle.  Do not ask x87 to rediscover (1,0).
    mov rax,0x3ff0000000000000
    vmovq xmm0,rax
    vxorpd xmm1,xmm1,xmm1
    xor ebx,ebx
.rpf_nmtf_loop:
    cmp rbx,r13
    jae .rpf_nmtf_done
    # Re-anchor every 16 nonzero values from j*base_angle using x87 extended input.
    test rbx,rbx
    jz .rpf_nmtf_have_phase
    test bl,15
    jnz .rpf_nmtf_have_phase
    mov [rsp+8],rbx
    fild qword ptr [rsp+8]
    fld tbyte ptr [rsp+16]
    fmulp st(1),st(0)
    fsincos
    fstp qword ptr [rsp+48]                 # cr
    fstp qword ptr [rsp+56]                 # ci
    vmovsd xmm0,[rsp+48]
    vmovsd xmm1,[rsp+56]
.rpf_nmtf_have_phase:
    mov rax,rbx
    shl rax,4
    vmovsd [r12+rax],xmm0
    vmovsd [r12+rax+8],xmm1
    # (cr+i ci) *= (wr+i wi), all in registers.
    vmulsd xmm4,xmm0,xmm2
    vmulsd xmm5,xmm1,xmm3
    vsubsd xmm4,xmm4,xmm5                  # nr
    vmulsd xmm6,xmm0,xmm3
    vmulsd xmm5,xmm1,xmm2
    vaddsd xmm6,xmm6,xmm5                  # ni
    vmovapd xmm0,xmm4
    vmovapd xmm1,xmm6
    inc rbx
    jmp .rpf_nmtf_loop
.rpf_nmtf_done:
    add rsp,96
    pop r15; pop r14; pop r13; pop r12; pop rbp; pop rbx
    ret

# rdi=A, rsi=N, rdx=len, rcx=T
rpf_nf_dif2:
    push rbx; push rbp; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi; mov r14,rdx; mov r15,rcx
    mov rbp,r14; shr rbp,1                 # m
    xor ebx,ebx                             # base
.rpf_nd2_base:
    cmp rbx,r13; jae .rpf_nd2_done
    xor r10d,r10d                           # j
.rpf_nd2_vec:
    lea rax,[r10+2]
    cmp rax,rbp; ja .rpf_nd2_scalar
    lea r8,[rbx+r10]
    lea r9,[r8+rbp]
    shl r8,4; shl r9,4
    vmovupd ymm0,[r12+r8]
    vmovupd ymm1,[r12+r9]
    vaddpd ymm2,ymm0,ymm1
    vsubpd ymm3,ymm0,ymm1
    mov rax,r10; shl rax,4
    vmovupd ymm4,[r15+rax]
    vmovddup ymm5,ymm4
    vpermilpd ymm6,ymm4,15
    vpermilpd ymm7,ymm3,5
    vmulpd ymm3,ymm3,ymm5
    vmulpd ymm7,ymm7,ymm6
    vaddsubpd ymm3,ymm3,ymm7
    vmovupd [r12+r8],ymm2
    vmovupd [r12+r9],ymm3
    add r10,2
    jmp .rpf_nd2_vec
.rpf_nd2_scalar:
    cmp r10,rbp; jae .rpf_nd2_next
    lea r8,[rbx+r10]; lea r9,[r8+rbp]
    shl r8,4; shl r9,4
    vmovupd xmm0,[r12+r8]
    vmovupd xmm1,[r12+r9]
    vaddpd xmm2,xmm0,xmm1
    vsubpd xmm3,xmm0,xmm1
    mov rax,r10; shl rax,4
    vmovupd xmm4,[r15+rax]
    NF_CMUL xmm3,xmm3,xmm4,xmm5,xmm6,xmm7
    vmovupd [r12+r8],xmm2
    vmovupd [r12+r9],xmm3
    inc r10
    jmp .rpf_nd2_scalar
.rpf_nd2_next:
    add rbx,r14
    jmp .rpf_nd2_base
.rpf_nd2_done:
    vzeroupper
    pop r15; pop r14; pop r13; pop r12; pop rbp; pop rbx
    ret

# inverse DIT radix2: rdi=A,rsi=N,rdx=m,rcx=T
rpf_nf_dit2:
    push rbx; push rbp; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi; mov rbp,rdx; mov r15,rcx
    lea r14,[rbp+rbp]                      # len
    xor ebx,ebx
.rpf_ni2_base:
    cmp rbx,r13; jae .rpf_ni2_done
    xor r10d,r10d
.rpf_ni2_vec:
    lea rax,[r10+2]
    cmp rax,rbp; ja .rpf_ni2_scalar
    lea r8,[rbx+r10]; lea r9,[r8+rbp]
    shl r8,4; shl r9,4
    vmovupd ymm0,[r12+r8]
    vmovupd ymm1,[r12+r9]
    mov rax,r10; shl rax,4
    vmovupd ymm4,[r15+rax]
    vmovddup ymm5,ymm4
    vpermilpd ymm6,ymm4,15
    vpermilpd ymm7,ymm1,5
    vmulpd ymm1,ymm1,ymm5
    vmulpd ymm7,ymm7,ymm6
    vaddsubpd ymm1,ymm1,ymm7
    vaddpd ymm2,ymm0,ymm1
    vsubpd ymm3,ymm0,ymm1
    vmovupd [r12+r8],ymm2
    vmovupd [r12+r9],ymm3
    add r10,2
    jmp .rpf_ni2_vec
.rpf_ni2_scalar:
    cmp r10,rbp; jae .rpf_ni2_next
    lea r8,[rbx+r10]; lea r9,[r8+rbp]
    shl r8,4; shl r9,4
    vmovupd xmm0,[r12+r8]
    vmovupd xmm1,[r12+r9]
    mov rax,r10; shl rax,4
    vmovupd xmm4,[r15+rax]
    NF_CMUL xmm1,xmm1,xmm4,xmm5,xmm6,xmm7
    vaddpd xmm2,xmm0,xmm1
    vsubpd xmm3,xmm0,xmm1
    vmovupd [r12+r8],xmm2
    vmovupd [r12+r9],xmm3
    inc r10; jmp .rpf_ni2_scalar
.rpf_ni2_next:
    add rbx,r14; jmp .rpf_ni2_base
.rpf_ni2_done:
    vzeroupper
    pop r15; pop r14; pop r13; pop r12; pop rbp; pop rbx
    ret

# forward DIF radix3: rdi=A,rsi=N,rdx=len,rcx=T
rpf_nf_dif3:
    push rbx; push rbp; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi; mov r14,rdx; mov r15,rcx
    mov rax,r14; xor edx,edx; mov ecx,3; div rcx; mov rbp,rax
    xor ebx,ebx
.rpf_nd3_base:
    cmp rbx,r13; jae .rpf_nd3_done
    xor r10d,r10d
.rpf_nd3_j:
    cmp r10,rbp; jae .rpf_nd3_next
    lea r8,[rbx+r10]; lea r9,[r8+rbp]; lea r11,[r9+rbp]
    shl r8,4; shl r9,4; shl r11,4
    vmovupd xmm0,[r12+r8]
    vmovupd xmm1,[r12+r9]
    vmovupd xmm2,[r12+r11]
    vaddpd xmm4,xmm1,xmm2                   # s
    vsubpd xmm5,xmm1,xmm2                   # d
    vaddpd xmm6,xmm0,xmm4                   # y0
    vmulpd xmm7,xmm4,[rip+rpf_nf_neg_half]
    vaddpd xmm7,xmm7,xmm0                   # mid
    vpermilpd xmm8,xmm5,1
    vmulpd xmm8,xmm8,[rip+rpf_nf_k3_fwd]        # rot
    vaddpd xmm9,xmm7,xmm8                   # y1
    vsubpd xmm10,xmm7,xmm8                  # y2
    mov rax,r10; shl rax,4
    vmovupd xmm3,[r15+rax]                   # w
    NF_CMUL xmm11,xmm3,xmm3,xmm0,xmm1,xmm2 # w2
    NF_CMUL xmm9,xmm9,xmm3,xmm0,xmm1,xmm2
    NF_CMUL xmm10,xmm10,xmm11,xmm0,xmm1,xmm2
    vmovupd [r12+r8],xmm6
    vmovupd [r12+r9],xmm9
    vmovupd [r12+r11],xmm10
    inc r10; jmp .rpf_nd3_j
.rpf_nd3_next:
    add rbx,r14; jmp .rpf_nd3_base
.rpf_nd3_done:
    pop r15; pop r14; pop r13; pop r12; pop rbp; pop rbx
    ret

# inverse DIT radix3: rdi=A,rsi=N,rdx=m,rcx=T
rpf_nf_dit3:
    push rbx; push rbp; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13,rsi; mov rbp,rdx; mov r15,rcx
    lea r14,[rbp+rbp*2]
    xor ebx,ebx
.rpf_ni3_base:
    cmp rbx,r13; jae .rpf_ni3_done
    xor r10d,r10d
.rpf_ni3_j:
    cmp r10,rbp; jae .rpf_ni3_next
    lea r8,[rbx+r10]; lea r9,[r8+rbp]; lea r11,[r9+rbp]
    shl r8,4; shl r9,4; shl r11,4
    mov rax,r10; shl rax,4
    vmovupd xmm3,[r15+rax]
    NF_CMUL xmm12,xmm3,xmm3,xmm0,xmm1,xmm2 # w2
    vmovupd xmm0,[r12+r8]
    vmovupd xmm1,[r12+r9]
    vmovupd xmm2,[r12+r11]
    NF_CMUL xmm1,xmm1,xmm3,xmm4,xmm5,xmm6
    NF_CMUL xmm2,xmm2,xmm12,xmm4,xmm5,xmm6
    vaddpd xmm4,xmm1,xmm2
    vsubpd xmm5,xmm1,xmm2
    vaddpd xmm6,xmm0,xmm4
    vmulpd xmm7,xmm4,[rip+rpf_nf_neg_half]
    vaddpd xmm7,xmm7,xmm0
    vpermilpd xmm8,xmm5,1
    vmulpd xmm8,xmm8,[rip+rpf_nf_k3_inv]
    vaddpd xmm9,xmm7,xmm8
    vsubpd xmm10,xmm7,xmm8
    vmovupd [r12+r8],xmm6
    vmovupd [r12+r9],xmm9
    vmovupd [r12+r11],xmm10
    inc r10; jmp .rpf_ni3_j
.rpf_ni3_next:
    add rbx,r14; jmp .rpf_ni3_base
.rpf_ni3_done:
    pop r15; pop r14; pop r13; pop r12; pop rbp; pop rbx
    ret

# forward DIF radix5; scalar SIMD formula, same Fourier authority.
rpf_nf_dif5:
    push rbx; push rbp; push r12; push r13; push r14; push r15
    sub rsp,128
    mov r12,rdi; mov r13,rsi; mov r14,rdx; mov r15,rcx
    mov rax,r14; xor edx,edx; mov ecx,5; div rcx; mov rbp,rax
    xor ebx,ebx
.rpf_nd5_base:
    cmp rbx,r13; jae .rpf_nd5_done
    xor r10d,r10d
.rpf_nd5_j:
    cmp r10,rbp; jae .rpf_nd5_next
    lea r8,[rbx+r10]
    mov rax,r8; shl rax,4; lea r11,[r12+rax]       # p0
    mov rax,rbp; shl rax,4; mov [rsp+96],rax       # stride bytes
    vmovupd xmm0,[r11]
    mov rax,[rsp+96]; vmovupd xmm1,[r11+rax]
    lea rdx,[rax+rax]; vmovupd xmm2,[r11+rdx]
    lea rcx,[rdx+rax]; vmovupd xmm3,[r11+rcx]
    lea rdi,[rcx+rax]; vmovupd xmm4,[r11+rdi]
    vaddpd xmm5,xmm1,xmm4                          # t1
    vaddpd xmm6,xmm2,xmm3                          # t2
    vsubpd xmm7,xmm1,xmm4                          # d1
    vsubpd xmm8,xmm2,xmm3                          # d2
    vmulpd xmm9,xmm5,[rip+rpf_nf_c1]
    vmulpd xmm15,xmm6,[rip+rpf_nf_c2]
    vaddpd xmm9,xmm9,xmm15
    vaddpd xmm9,xmm9,xmm0                          # A
    vmulpd xmm10,xmm5,[rip+rpf_nf_c2]
    vmulpd xmm15,xmm6,[rip+rpf_nf_c1]
    vaddpd xmm10,xmm10,xmm15
    vaddpd xmm10,xmm10,xmm0                        # B
    vmulpd xmm11,xmm7,[rip+rpf_nf_s1]
    vmulpd xmm15,xmm8,[rip+rpf_nf_s2]
    vaddpd xmm11,xmm11,xmm15                       # e1
    vmulpd xmm12,xmm7,[rip+rpf_nf_s2]
    vmulpd xmm15,xmm8,[rip+rpf_nf_s1]
    vsubpd xmm12,xmm12,xmm15                       # e2
    vpermilpd xmm13,xmm11,1
    vmulpd xmm13,xmm13,[rip+rpf_nf_rot_fwd]
    vpermilpd xmm14,xmm12,1
    vmulpd xmm14,xmm14,[rip+rpf_nf_rot_fwd]
    vaddpd xmm15,xmm0,xmm5
    vaddpd xmm15,xmm15,xmm6
    vmovupd [r11],xmm15                             # y0
    vmovapd xmm0,xmm9; vaddpd xmm0,xmm0,xmm13      # y1
    vmovapd xmm1,xmm10; vaddpd xmm1,xmm1,xmm14     # y2
    vmovapd xmm2,xmm10; vsubpd xmm2,xmm2,xmm14     # y3
    vmovapd xmm3,xmm9; vsubpd xmm3,xmm3,xmm13      # y4
    vmovupd [rsp+0],xmm0; vmovupd [rsp+16],xmm1; vmovupd [rsp+32],xmm2; vmovupd [rsp+48],xmm3
    mov rax,r10; shl rax,4; vmovupd xmm4,[r15+rax] # w
    NF_CMUL xmm5,xmm4,xmm4,xmm6,xmm7,xmm8         # w2
    NF_CMUL xmm6,xmm5,xmm4,xmm7,xmm8,xmm9         # w3
    NF_CMUL xmm7,xmm6,xmm4,xmm8,xmm9,xmm10        # w4
    vmovupd xmm0,[rsp+0]; NF_CMUL xmm0,xmm0,xmm4,xmm8,xmm9,xmm10
    vmovupd xmm1,[rsp+16]; NF_CMUL xmm1,xmm1,xmm5,xmm8,xmm9,xmm10
    vmovupd xmm2,[rsp+32]; NF_CMUL xmm2,xmm2,xmm6,xmm8,xmm9,xmm10
    vmovupd xmm3,[rsp+48]; NF_CMUL xmm3,xmm3,xmm7,xmm8,xmm9,xmm10
    mov rax,[rsp+96]
    vmovupd [r11+rax],xmm0
    lea rdx,[rax+rax]; vmovupd [r11+rdx],xmm1
    lea rcx,[rdx+rax]; vmovupd [r11+rcx],xmm2
    lea rdi,[rcx+rax]; vmovupd [r11+rdi],xmm3
    inc r10; jmp .rpf_nd5_j
.rpf_nd5_next:
    add rbx,r14; jmp .rpf_nd5_base
.rpf_nd5_done:
    add rsp,128
    pop r15; pop r14; pop r13; pop r12; pop rbp; pop rbx
    ret

# inverse DIT radix5
rpf_nf_dit5:
    push rbx; push rbp; push r12; push r13; push r14; push r15
    sub rsp,128
    mov r12,rdi; mov r13,rsi; mov rbp,rdx; mov r15,rcx
    lea r14,[rbp+rbp*4]
    xor ebx,ebx
.rpf_ni5_base:
    cmp rbx,r13; jae .rpf_ni5_done
    xor r10d,r10d
.rpf_ni5_j:
    cmp r10,rbp; jae .rpf_ni5_next
    lea r8,[rbx+r10]; mov rax,r8; shl rax,4; lea r11,[r12+rax]
    mov rax,rbp; shl rax,4; mov [rsp+96],rax
    mov rdx,r10; shl rdx,4; vmovupd xmm4,[r15+rdx] # w
    NF_CMUL xmm5,xmm4,xmm4,xmm6,xmm7,xmm8         # w2
    NF_CMUL xmm6,xmm5,xmm4,xmm7,xmm8,xmm9         # w3
    NF_CMUL xmm7,xmm6,xmm4,xmm8,xmm9,xmm10        # w4
    vmovupd xmm0,[r11]
    mov rax,[rsp+96]
    vmovupd xmm1,[r11+rax]; NF_CMUL xmm1,xmm1,xmm4,xmm8,xmm9,xmm10
    lea rdx,[rax+rax]; vmovupd xmm2,[r11+rdx]; NF_CMUL xmm2,xmm2,xmm5,xmm8,xmm9,xmm10
    lea rcx,[rdx+rax]; vmovupd xmm3,[r11+rcx]; NF_CMUL xmm3,xmm3,xmm6,xmm8,xmm9,xmm10
    lea rdi,[rcx+rax]; vmovupd xmm4,[r11+rdi]; NF_CMUL xmm4,xmm4,xmm7,xmm8,xmm9,xmm10
    vaddpd xmm5,xmm1,xmm4
    vaddpd xmm6,xmm2,xmm3
    vsubpd xmm7,xmm1,xmm4
    vsubpd xmm8,xmm2,xmm3
    vmulpd xmm9,xmm5,[rip+rpf_nf_c1]
    vmulpd xmm15,xmm6,[rip+rpf_nf_c2]
    vaddpd xmm9,xmm9,xmm15; vaddpd xmm9,xmm9,xmm0
    vmulpd xmm10,xmm5,[rip+rpf_nf_c2]
    vmulpd xmm15,xmm6,[rip+rpf_nf_c1]
    vaddpd xmm10,xmm10,xmm15; vaddpd xmm10,xmm10,xmm0
    vmulpd xmm11,xmm7,[rip+rpf_nf_s1]
    vmulpd xmm15,xmm8,[rip+rpf_nf_s2]
    vaddpd xmm11,xmm11,xmm15
    vmulpd xmm12,xmm7,[rip+rpf_nf_s2]
    vmulpd xmm15,xmm8,[rip+rpf_nf_s1]
    vsubpd xmm12,xmm12,xmm15
    vpermilpd xmm13,xmm11,1; vmulpd xmm13,xmm13,[rip+rpf_nf_rot_inv]
    vpermilpd xmm14,xmm12,1; vmulpd xmm14,xmm14,[rip+rpf_nf_rot_inv]
    vaddpd xmm15,xmm0,xmm5; vaddpd xmm15,xmm15,xmm6
    vmovupd [r11],xmm15
    vmovapd xmm1,xmm9; vaddpd xmm1,xmm1,xmm13
    vmovapd xmm4,xmm9; vsubpd xmm4,xmm4,xmm13
    vmovapd xmm2,xmm10; vaddpd xmm2,xmm2,xmm14
    vmovapd xmm3,xmm10; vsubpd xmm3,xmm3,xmm14
    mov rax,[rsp+96]
    vmovupd [r11+rax],xmm1
    lea rdx,[rax+rax]; vmovupd [r11+rdx],xmm2
    lea rcx,[rdx+rax]; vmovupd [r11+rcx],xmm3
    lea rdi,[rcx+rax]; vmovupd [r11+rdi],xmm4
    inc r10; jmp .rpf_ni5_j
.rpf_ni5_next:
    add rbx,r14; jmp .rpf_ni5_base
.rpf_ni5_done:
    add rsp,128
    pop r15; pop r14; pop r13; pop r12; pop rbp; pop rbx
    ret

# int rpf_fourier_mul_u64(out,a,b,P,scratch)
# SysV: rdi out, rsi a, rdx b, ecx P, r8 scratch. Inputs need no extra guard.
.type rpf_fourier_mul_u64,@function
rpf_fourier_mul_u64:
    push rbx; push rbp; push r12; push r13; push r14; push r15
    sub rsp,160
    mov [rsp+0],rdi                         # out
    mov [rsp+8],rsi                         # a
    mov [rsp+16],rdx                        # b
    mov [rsp+24],r8                         # scratch
    mov [rsp+32],ecx                        # P
    mov [rsp+44],r9d                        # type-level AOT packed geometry
    mov eax,[rsp+44]
    test eax,eax
    jz .rpf_nfm_bad
    # packed geometry bytes: b | a2<<8 | a3<<16 | a5<<24
    mov edx,eax; and edx,255; mov [rsp+64+G_B],edx
    mov edx,eax; shr edx,8; and edx,255; mov [rsp+64+G_A2],edx
    mov edx,eax; shr edx,16; and edx,255; mov [rsp+64+G_A3],edx
    shr eax,24; mov [rsp+64+G_A5],eax
    # ncoef = ceil(P/b)
    mov eax,[rsp+32]; mov ecx,[rsp+64+G_B]; add eax,ecx; dec eax
    xor edx,edx; div ecx; mov [rsp+64+G_NCOEF],rax
    # N = 2^a2 * 3^a3 * 5^a5
    mov ecx,[rsp+64+G_A2]; mov rax,1; shl rax,cl
    mov edx,[rsp+64+G_A3]
.rpf_nfm_pack3:
    test edx,edx; jz .rpf_nfm_pack5_start
    imul rax,rax,3; dec edx; jmp .rpf_nfm_pack3
.rpf_nfm_pack5_start:
    mov edx,[rsp+64+G_A5]
.rpf_nfm_pack5:
    test edx,edx; jz .rpf_nfm_geom_pack_done
    imul rax,rax,5; dec edx; jmp .rpf_nfm_pack5
.rpf_nfm_geom_pack_done:
    mov [rsp+64+G_NFFT],rax
.rpf_nfm_geom_ready:
    mov eax,[rsp+64+G_B]; mov [rsp+36],eax # bcoef
    mov eax,[rsp+32]; add eax,63; shr eax,6; mov [rsp+40],eax # n64
    mov r14,[rsp+64+G_NCOEF]
    mov r15,[rsp+64+G_NFFT]
    # Layout A=align64(scratch), T=A+16N, product=align64(T+8N+16)
    mov r12,[rsp+24]; add r12,63; and r12,-64
    mov rax,r15; shl rax,4; lea r13,[r12+rax]     # T
    mov rax,r15; shl rax,3; lea rbx,[r13+rax+16]  # product tentative
    add rbx,63; and rbx,-64
    mov [rsp+48],rbx                         # product
    # zero A (2*N qwords)
    mov rdi,r12; xor eax,eax; mov rcx,r15; shl rcx,1; rep stosq
    # unpack digits into complex A: real=a digit, imag=b digit
    mov ecx,[rsp+36]; mov rax,1; shl rax,cl; dec rax; mov [rsp+56],rax # mask
    xor rbp,rbp                               # k
.rpf_nfm_unpack:
    cmp rbp,r14; jae .rpf_nfm_forward
    # bit = k*b
    mov rax,rbp; mov ecx,[rsp+36]; imul rax,rcx
    mov r8,rax; shr r8,6                      # q
    and eax,63; mov r9d,eax                   # shift
    mov r10,[rsp+8]; mov rax,[r10+r8*8]
    mov r11,[rsp+16]; mov rdx,[r11+r8*8]
    test r9d,r9d; jz .rpf_nfm_unpack_mask
    mov ecx,r9d; shr rax,cl; shr rdx,cl
    lea r10,[r8+1]; cmp r10d,dword ptr [rsp+40]; jae .rpf_nfm_unpack_mask
    mov r11,[rsp+8]; mov r10,[r11+r10*8]
    mov ecx,64; sub ecx,r9d; shl r10,cl; or rax,r10
    lea r10,[r8+1]; mov r11,[rsp+16]; mov r10,[r11+r10*8]
    shl r10,cl; or rdx,r10
    jmp .rpf_nfm_unpack_do_mask
.rpf_nfm_unpack_mask:
    test r9d,r9d; jnz .rpf_nfm_unpack_do_mask
.rpf_nfm_unpack_do_mask:
    and rax,[rsp+56]; and rdx,[rsp+56]
    vxorpd xmm0,xmm0,xmm0; vcvtsi2sd xmm0,xmm0,rax
    vxorpd xmm1,xmm1,xmm1; vcvtsi2sd xmm1,xmm1,rdx
    mov r10,rbp; shl r10,4
    vmovsd [r12+r10],xmm0
    vmovsd [r12+r10+8],xmm1
    inc rbp; jmp .rpf_nfm_unpack
.rpf_nfm_forward:
    # forward order: radix5 -> radix3 -> radix2, len=N
    mov rbp,r15                               # len
    mov ebx,[rsp+64+G_A5]
.rpf_nfm_f5:
    test ebx,ebx; jz .rpf_nfm_f3_start
    mov rax,rbp; xor edx,edx; mov ecx,5; div rcx
    mov rdi,r13; mov rsi,rax; mov rdx,rbp; xor ecx,ecx; call rpf_nf_make_tw
    mov rdi,r12; mov rsi,r15; mov rdx,rbp; mov rcx,r13; call rpf_nf_dif5
    mov rax,rbp; xor edx,edx; mov ecx,5; div rcx; mov rbp,rax
    dec ebx; jmp .rpf_nfm_f5
.rpf_nfm_f3_start:
    mov ebx,[rsp+64+G_A3]
.rpf_nfm_f3:
    test ebx,ebx; jz .rpf_nfm_f2_start
    mov rax,rbp; xor edx,edx; mov ecx,3; div rcx
    mov rdi,r13; mov rsi,rax; mov rdx,rbp; xor ecx,ecx; call rpf_nf_make_tw
    mov rdi,r12; mov rsi,r15; mov rdx,rbp; mov rcx,r13; call rpf_nf_dif3
    mov rax,rbp; xor edx,edx; mov ecx,3; div rcx; mov rbp,rax
    dec ebx; jmp .rpf_nfm_f3
.rpf_nfm_f2_start:
    mov ebx,[rsp+64+G_A2]
.rpf_nfm_f2:
    test ebx,ebx; jz .rpf_nfm_square
    mov rax,rbp; shr rax,1
    mov rdi,r13; mov rsi,rax; mov rdx,rbp; xor ecx,ecx; call rpf_nf_make_tw
    mov rdi,r12; mov rsi,r15; mov rdx,rbp; mov rcx,r13; call rpf_nf_dif2
    shr rbp,1
    dec ebx; jmp .rpf_nfm_f2
.rpf_nfm_square:
    # Z <- Z^2, two complex values per AVX2 iteration
    xor rbp,rbp
.rpf_nfm_sq_vec:
    lea rax,[rbp+2]; cmp rax,r15; ja .rpf_nfm_sq_scalar
    mov rax,rbp; shl rax,4
    vmovupd ymm0,[r12+rax]
    vmovddup ymm1,ymm0
    vpermilpd ymm2,ymm0,15
    vpermilpd ymm3,ymm0,5
    vmulpd ymm0,ymm0,ymm1
    vmulpd ymm3,ymm3,ymm2
    vaddsubpd ymm0,ymm0,ymm3
    vmovupd [r12+rax],ymm0
    add rbp,2; jmp .rpf_nfm_sq_vec
.rpf_nfm_sq_scalar:
    cmp rbp,r15; jae .rpf_nfm_inverse
    mov rax,rbp; shl rax,4
    vmovupd xmm0,[r12+rax]
    NF_CMUL xmm0,xmm0,xmm0,xmm1,xmm2,xmm3
    vmovupd [r12+rax],xmm0
    inc rbp; jmp .rpf_nfm_sq_scalar
.rpf_nfm_inverse:
    # inverse order: radix2 -> radix3 -> radix5, m=1
    mov rbp,1
    mov ebx,[rsp+64+G_A2]
.rpf_nfm_i2:
    test ebx,ebx; jz .rpf_nfm_i3_start
    lea rdx,[rbp+rbp]
    mov rdi,r13; mov rsi,rbp; mov ecx,1; call rpf_nf_make_tw
    mov rdi,r12; mov rsi,r15; mov rdx,rbp; mov rcx,r13; call rpf_nf_dit2
    shl rbp,1
    dec ebx; jmp .rpf_nfm_i2
.rpf_nfm_i3_start:
    mov ebx,[rsp+64+G_A3]
.rpf_nfm_i3:
    test ebx,ebx; jz .rpf_nfm_i5_start
    lea rdx,[rbp+rbp*2]
    mov rdi,r13; mov rsi,rbp; mov ecx,1; call rpf_nf_make_tw
    mov rdi,r12; mov rsi,r15; mov rdx,rbp; mov rcx,r13; call rpf_nf_dit3
    lea rbp,[rbp+rbp*2]
    dec ebx; jmp .rpf_nfm_i3
.rpf_nfm_i5_start:
    mov ebx,[rsp+64+G_A5]
.rpf_nfm_i5:
    test ebx,ebx; jz .rpf_nfm_carry
    lea rdx,[rbp+rbp*4]
    mov rdi,r13; mov rsi,rbp; mov ecx,1; call rpf_nf_make_tw
    mov rdi,r12; mov rsi,r15; mov rdx,rbp; mov rcx,r13; call rpf_nf_dit5
    lea rbp,[rbp+rbp*4]
    dec ebx; jmp .rpf_nfm_i5
.rpf_nfm_carry:
    vzeroupper
    # zero product limbs
    mov rdi,[rsp+48]; xor eax,eax; mov ecx,[rsp+40]; lea ecx,[ecx*2+4]; rep stosq
    # inv = 0.5/N
    vxorpd xmm7,xmm7,xmm7
    vcvtsi2sd xmm7,xmm7,r15
    vmovsd xmm6,[rip+rpf_nf_half]
    vdivsd xmm6,xmm6,xmm7
    xor r11d,r11d                            # carry
    xor rbp,rbp                              # k
    lea r14,[r14+r14-1]                      # coefficient count
.rpf_nfm_carry_loop:
    cmp rbp,r14; jae .rpf_nfm_carry_tail
    mov rax,rbp; shl rax,4
    vmovsd xmm0,[r12+rax+8]
    vmulsd xmm0,xmm0,xmm6
    vcvtsd2si rax,xmm0
    test rax,rax; js .rpf_nfm_bad
    add rax,r11
    mov r11,rax
    mov ecx,[rsp+36]
    shr r11,cl                               # new carry
    and rax,[rsp+56]                         # digit
    # pack digit at bit=k*b
    mov rdx,rbp; imul rdx,rcx
    mov r8,rdx; shr r8,6
    and edx,63
    mov r9,[rsp+48]
    mov ecx,edx
    mov r10,rax; shl r10,cl; or [r9+r8*8],r10
    mov ecx,[rsp+36]
    add ecx,edx
    cmp ecx,64; jbe .rpf_nfm_pack_done
    mov ecx,64; sub ecx,edx
    shr rax,cl; or [r9+r8*8+8],rax
.rpf_nfm_pack_done:
    inc rbp; jmp .rpf_nfm_carry_loop
.rpf_nfm_carry_tail:
    test r11,r11; jz .rpf_nfm_ok
.rpf_nfm_tail_loop:
    mov rax,r11; and rax,[rsp+56]
    mov ecx,[rsp+36]; shr r11,cl
    mov rdx,rbp; imul rdx,rcx
    mov r8,rdx; shr r8,6; and edx,63
    mov r9,[rsp+48]; mov ecx,edx
    mov r10,rax; shl r10,cl; or [r9+r8*8],r10
    mov ecx,[rsp+36]; add ecx,edx; cmp ecx,64; jbe .rpf_nfm_tail_next
    mov ecx,64; sub ecx,edx; shr rax,cl; or [r9+r8*8+8],rax
.rpf_nfm_tail_next:
    inc rbp; test r11,r11; jnz .rpf_nfm_tail_loop
.rpf_nfm_ok:
    mov rax,[rsp+48]
    jmp .rpf_nfm_done
.rpf_nfm_bad:
    xor eax,eax
.rpf_nfm_done:
    add rsp,160
    pop r15; pop r14; pop r13; pop r12; pop rbp; pop rbx
    ret


# rdi=dst,rsi=a,rdx=b,ecx=type -> eax status.
# This is the sole P>64 multiplication authority.  It preserves the old
# ValueFact ABI and old precision/RNE authority; only physical multiplication
# has been assimilated into the native Fourier DAG.
.global rankn_fp_mul
rankn_fp_mul:
    RPF_SAVE
    sub rsp,48
    mov r12,rdi; mov r13,rsi; mov r14,rdx; mov r15d,ecx
    mov edi,r15d; call rpf_precision_from_type; test rax,rax; jz .rpfm_bad
    test edx,edx; jz .rpfm_bad
    mov [rsp+40],edx                       # one type-level AOT geometry fact
    mov [rsp+32],rax                       # P
    mov rbp,rax; add rbp,63; shr rbp,6
    mov rax,[rsp+32]
    cmp [r13+RPF_PREC],rax; jne .rpfm_bad
    cmp [r14+RPF_PREC],rax; jne .rpfm_bad
    # Static/AOT-owned scratch begins immediately after the primary carrier.
    lea r8,[r12+RPF_DATA]
    mov eax,ebp; shl rax,3; add r8,rax
    # rpf_fourier_mul_u64 returns the exact integer product in RAX.
    xor edi,edi
    lea rsi,[r13+RPF_DATA]
    lea rdx,[r14+RPF_DATA]
    mov ecx,[rsp+32]
    mov r9d,[rsp+40]
    call rpf_fourier_mul_u64
    test rax,rax; jz .rpfm_bad
    mov [rsp],rax
    mov r8,[r13+RPF_EXP]; add r8,[r14+RPF_EXP]
    mov eax,[rsp+32]; dec eax; movsxd rax,eax; shl rax,1; sub r8,rax
    mov rcx,[r13+RPF_SIGN]; xor rcx,[r14+RPF_SIGN]
    mov rdi,r12; mov rsi,[rsp]; lea edx,[rbp*2+4]; mov r9d,r15d
    call rpf_round_from_integer
    test eax,eax; jnz .rpfm_bad
    xor eax,eax; jmp .rpfm_done
.rpfm_bad:
    mov eax,1
.rpfm_done:
    add rsp,48
    RPF_RESTORE
    ret

# rdi=dst,rsi=a,rdx=b,ecx=type -> eax status.
# Base-2^32 Knuth digit division.  One quotient digit is resolved per episode;
# the former bit-by-bit restoring path is intentionally absent.
.global rankn_fp_div
rankn_fp_div:
    RPF_SAVE
    sub rsp,160
    mov r12,rdi; mov r13,rsi; mov r14,rdx; mov r15d,ecx
    mov edi,r15d; call rpf_precision_from_type; test rax,rax; jz .rpfd2_bad
    mov [rsp+120],eax                              # P, Knuth digit core remains dword-indexed
    mov rbp,rax; add rbp,63; shr rbp,6
    cmp [r13+RPF_PREC],rax; jne .rpfd2_bad
    cmp [r14+RPF_PREC],rax; jne .rpfd2_bad
    # Division is a relation over ValueFacts, so its zero identities belong here
    # rather than in individual transcendental functions.  Reject a zero divisor;
    # close an exact zero numerator directly and never enter Knuth geometry with
    # an empty high digit domain.
    mov rdi,r14; call rpf_object_is_zero; test eax,eax; jnz .rpfd2_bad
    mov rdi,r13; call rpf_object_is_zero; test eax,eax; jz .rpfd2_nonzero_a
    mov rdi,r12; mov esi,r15d; call rpf_object_init; test eax,eax; jnz .rpfd2_bad
    xor eax,eax; jmp .rpfd2_done
.rpfd2_nonzero_a:
    mov eax,dword ptr [rsp+120]
    lea ecx,[eax+31]; shr ecx,5; mov [rsp+124],ecx # nd
    lea edx,[eax+4]; mov [rsp+128],edx             # K
    mov eax,edx; shr eax,5; mov [rsp+132],eax      # qw
    and edx,31; mov [rsp+136],edx                  # rb
    mov eax,[rsp+124]; add eax,[rsp+132]; add eax,6; mov [rsp+140],eax # ucap
    # scratch layout: compact U[ucap]u32, V[nd+2]u32, Q[ucap]u32, then Q64.
    # Base-2^32 is the division recurrence itself; widening every logical digit
    # to a qword was pure traffic and doubled the live scratch footprint.
    lea r8,[r12+RPF_DATA]; mov eax,ebp; shl rax,3; lea r9,[r8+rax]
    mov [rsp],r9                                    # U
    mov ecx,[rsp+140]; mov eax,ecx; shl rax,2; lea r10,[r9+rax]
    mov [rsp+8],r10                                 # V
    mov ecx,[rsp+124]; add ecx,2; mov eax,ecx; shl rax,2; lea r11,[r10+rax]
    mov [rsp+16],r11                                # Q
    mov ecx,[rsp+140]; mov eax,ecx; shl rax,2; add r11,rax
    add r11,7; and r11,-8
    mov [rsp+24],r11                                # Q64
    # U is assembled with OR and therefore needs one dword clear. V's live
    # digits and Q's quotient digits are written once; only V guards are zeroed.
    mov rdi,[rsp]; xor eax,eax; mov ecx,[rsp+140]; rep stosd
    mov r10,[rsp+8]; mov eax,[rsp+124]
    mov dword ptr [r10+rax*4],0
    mov dword ptr [r10+rax*4+4],0
    # Build U=(A << K) and V=B in base32 slots.
    xor ebx,ebx
.rpfd2_fill:
    cmp ebx,[rsp+124]; jae .rpfd2_filled
    lea rdi,[r13+RPF_DATA]; mov esi,ebp; mov edx,ebx; call rpf_get32
    mov r8d,eax
    mov r9d,ebx; add r9d,[rsp+132]
    mov r10,[rsp]
    mov ecx,[rsp+136]; test ecx,ecx; jz .rpfd2_u_direct
    mov eax,r8d; shl eax,cl; or dword ptr [r10+r9*4],eax
    inc r9d; mov eax,r8d; mov ecx,32; sub ecx,[rsp+136]; shr eax,cl; or dword ptr [r10+r9*4],eax
    jmp .rpfd2_v
.rpfd2_u_direct:
    or dword ptr [r10+r9*4],r8d
.rpfd2_v:
    lea rdi,[r14+RPF_DATA]; mov esi,ebp; mov edx,ebx; call rpf_get32
    mov r10,[rsp+8]; mov dword ptr [r10+rbx*4],eax
    inc ebx; jmp .rpfd2_fill
.rpfd2_filled:
    # Normalized fpP already carries its high-bit fact at P-1.  Preserve that
    # information instead of rescanning V/U after materialization.
    mov eax,[rsp+124]
    mov [rsp+144],eax                               # n = ceil(P/32)
    # un_pre = ceil((2P+4)/32), the exact digit count of A<<K before Knuth normalization.
    mov eax,[rsp+120]
    mov edx,eax
    add rax,rax
    add rax,35
    shr rax,5
    mov [rsp+148],eax                               # un pre-normalization
    # s = n*32-P.  Since B is normalized this is exactly clz32(V[n-1]).
    mov ecx,[rsp+144]
    shl ecx,5
    sub ecx,edx
    mov [rsp+152],ecx
    # normalize V and U by s. U owns one explicit zero guard for any carry-out.
    mov rdi,[rsp+8]; mov ecx,[rsp+144]; inc ecx; mov edx,[rsp+152]; call rpf_shl32_slots2
    mov rdi,[rsp]; mov ecx,[rsp+148]; inc ecx; mov edx,[rsp+152]; call rpf_shl32_slots2
    # un_norm = n + ceil((P+4)/32).  No post-shift highlen scan is needed.
    mov eax,[rsp+120]
    add rax,35
    shr rax,5
    add eax,[rsp+144]
    mov [rsp+148],eax
    mov r10,[rsp]; mov edx,eax; mov dword ptr [r10+rdx*4],0
    mov ecx,eax; sub ecx,[rsp+144]; mov [rsp+156],ecx # m
    mov dword ptr [rsp+88],0                        # qn32 high-water mark
    # vtop cached in stack 112
    mov r10,[rsp+8]; mov edx,[rsp+144]; dec edx; mov eax,dword ptr [r10+rdx*4]; mov [rsp+112],rax
    mov ebx,[rsp+156]
.rpfd2_j:
    test ebx,ebx; js .rpfd2_quot_done
    mov r10,[rsp]; mov edx,ebx; add edx,[rsp+144]
    mov r8d,dword ptr [r10+rdx*4]
    mov r9d,dword ptr [r10+rdx*4-4]
    mov rax,r8; shl rax,32; or rax,r9; mov [rsp+96],rax # num
    xor edx,edx; mov rcx,[rsp+112]; div rcx
    mov r8,rax; shr r8,32; test r8,r8; jz .rpfd2_q_ok
    mov eax,0xffffffff
    mov rdx,[rsp+96]; mov r8,rax; imul r8,[rsp+112]; sub rdx,r8
.rpfd2_q_ok:
    mov [rsp+64],rax                                # qhat
    mov [rsp+72],rdx                                # rhat
    cmp dword ptr [rsp+144],2; jb .rpfd2_subtract
.rpfd2_adjust:
    mov rax,[rsp+72]; shr rax,32; test rax,rax; jnz .rpfd2_subtract
    mov r10,[rsp+8]; mov edx,[rsp+144]; sub edx,2
    mov r11d,dword ptr [r10+rdx*4]
    mov rax,[rsp+64]; imul rax,r11                 # exact 32x32 product
    mov r8,rax
    mov r9,[rsp+72]; shl r9,32
    mov r10,[rsp]; mov edx,ebx; add edx,[rsp+144]; sub edx,2
    mov eax,dword ptr [r10+rdx*4]; or r9,rax
    cmp r8,r9; jbe .rpfd2_subtract
    dec qword ptr [rsp+64]
    mov rax,[rsp+112]; add [rsp+72],rax
    jmp .rpfd2_adjust
.rpfd2_subtract:
    xor r8d,r8d                                     # i
    xor r9d,r9d                                     # carry
    xor r10d,r10d                                   # borrow
.rpfd2_sub_loop:
    cmp r8d,[rsp+144]; jae .rpfd2_sub_top
    mov r11,[rsp+8]; mov r11d,dword ptr [r11+r8*4]
    mov rax,[rsp+64]; imul rax,r11
    add rax,r9; mov r9,rax; shr r9,32
    mov eax,eax; add rax,r10                 # sub
    mov r11,[rsp]; mov edx,ebx; add edx,r8d
    mov ecx,dword ptr [r11+rdx*4]
    cmp rcx,rax; setb r10b; movzx r10d,r10b
    sub ecx,eax; mov dword ptr [r11+rdx*4],ecx
    inc r8d; jmp .rpfd2_sub_loop
.rpfd2_sub_top:
    mov r11,[rsp]; mov edx,ebx; add edx,[rsp+144]
    mov ecx,dword ptr [r11+rdx*4]
    mov rax,r9; add rax,r10
    cmp rcx,rax; setb r8b; movzx r8d,r8b            # under
    sub ecx,eax; mov dword ptr [r11+rdx*4],ecx
    test r8d,r8d; jz .rpfd2_store_q
    dec qword ptr [rsp+64]
    xor r9d,r9d; xor r10d,r10d
.rpfd2_addback:
    cmp r10d,[rsp+144]; jae .rpfd2_addtop
    mov r11,[rsp]; mov edx,ebx; add edx,r10d
    mov eax,dword ptr [r11+rdx*4]
    mov rcx,[rsp+8]; mov ecx,dword ptr [rcx+r10*4]; add rax,rcx; add rax,r9
    mov dword ptr [r11+rdx*4],eax
    shr rax,32; mov r9,rax
    inc r10d; jmp .rpfd2_addback
.rpfd2_addtop:
    mov r11,[rsp]; mov edx,ebx; add edx,[rsp+144]; add dword ptr [r11+rdx*4],r9d
.rpfd2_store_q:
    mov r11,[rsp+16]; mov eax,dword ptr [rsp+64]; mov dword ptr [r11+rbx*4],eax
    cmp dword ptr [rsp+88],0
    jne .rpfd2_qhigh_known
    test eax,eax
    jz .rpfd2_qhigh_known
    lea ecx,[ebx+1]
    mov [rsp+88],ecx
.rpfd2_qhigh_known:
    dec ebx; jmp .rpfd2_j
.rpfd2_quot_done:
    # remainder lives in U[0..n-1]
    xor r8d,r8d; xor r9d,r9d; mov r10,[rsp]
.rpfd2_rem_loop:
    cmp r8d,[rsp+144]; jae .rpfd2_rem_done
    mov eax,dword ptr [r10+r8*4]; or r9,rax; inc r8d; jmp .rpfd2_rem_loop
.rpfd2_rem_done:
    mov [rsp+104],r9
    mov eax,[rsp+88]
    test eax,eax
    jz .rpfd2_bad                                   # nonzero numerator and scaled quotient cannot vanish
    mov [rsp+108],eax                               # qn32 carried from quotient production
    mov eax,[rsp+108]; add eax,1; shr eax,1; add eax,1; mov [rsp+100],eax # q64 count
    mov rdi,[rsp+24]; mov rsi,[rsp+16]; mov ecx,[rsp+100]; mov edx,[rsp+108]; call rpf_32_to_u64
    cmp qword ptr [rsp+104],0; je .rpfd2_no_sticky
    mov r10,[rsp+24]; or qword ptr [r10],1
.rpfd2_no_sticky:
    mov r8,[r13+RPF_EXP]; sub r8,[r14+RPF_EXP]
    movsxd rax,dword ptr [rsp+128]; sub r8,rax
    # Quotient production already owns the high-water digit.  Preserve its
    # exact top bit instead of rescanning the converted Q64 carrier.
    mov ecx,[rsp+108]; dec ecx
    mov r11,[rsp+16]
    mov eax,dword ptr [r11+rcx*4]
    bsr edx,eax
    shl ecx,5
    add ecx,edx
    mov r10d,ecx
    mov rcx,[r13+RPF_SIGN]; xor rcx,[r14+RPF_SIGN]
    mov rdi,r12; mov rsi,[rsp+24]; mov edx,[rsp+100]; mov r9d,r15d
    call rpf_round_from_integer_known_top
    test eax,eax; jnz .rpfd2_bad
    xor eax,eax; jmp .rpfd2_done
.rpfd2_bad: mov eax,1
.rpfd2_done:
    add rsp,160
    RPF_RESTORE
    ret

# rdi=dst,rsi=src,rdx=positive u64 divisor,ecx=type -> eax status.
# Exact scalar quotient relation used by local mathematical propagation.  A
# series index remains an integer fact; it is never inflated into a second fpP
# ValueFact merely to feed the general big/big divider.  Two guard limbs are
# appended to the significand, one streaming u128/u64 division resolves every
# quotient limb, and the exact remainder becomes sticky below the RNE guard.
# There is one relation for every P>64 and no precision threshold or named-width
# route.
.global rankn_fp_div_u64
rankn_fp_div_u64:
    RPF_SAVE
    sub rsp,48
    mov r12,rdi
    mov r13,rsi
    mov r14,rdx
    mov r15d,ecx
    test r14,r14
    jz .rpfdu64_bad
    cmp dword ptr [r13+RPF_TYPE],r15d
    jne .rpfdu64_bad
    mov rax,[r13+RPF_PREC]
    cmp rax,64
    jbe .rpfdu64_bad
    mov [rsp],rax                         # P
    # Zero is an exact scalar-quotient fixed point.  Close it directly instead
    # of fabricating an all-zero integer carrier that the nonzero RNE closure
    # intentionally does not accept.
    mov rdi,r13
    call rpf_object_is_zero
    test eax,eax
    jz .rpfdu64_nonzero
    mov rdi,r12
    mov esi,r15d
    call rpf_object_init
    test eax,eax
    jnz .rpfdu64_bad
    xor eax,eax
    jmp .rpfdu64_done
.rpfdu64_nonzero:
    mov rbp,[rsp]
    add rbp,63
    jc .rpfdu64_bad
    shr rbp,6                             # N
    mov [rsp+8],rbp
    # Quotient scratch starts after the primary carrier.  U=M<<128 therefore
    # owns exactly N+2 source/quotient limbs; every quotient limb is overwritten
    # once, so no zero-fill is required.
    lea r11,[r12+RPF_DATA+rbp*8]
    mov [rsp+16],r11
    lea r10,[rbp+2]
    mov [rsp+24],r10                      # L=N+2
    xor edx,edx                           # streaming remainder
    mov rbx,r10
.rpfdu64_loop:
    test rbx,rbx
    jz .rpfdu64_quot_done
    dec rbx
    xor eax,eax
    cmp rbx,2
    jb .rpfdu64_have_limb
    mov rcx,rbx
    sub rcx,2
    cmp rcx,rbp
    jae .rpfdu64_have_limb
    mov rax,[r13+RPF_DATA+rcx*8]
.rpfdu64_have_limb:
    div r14                               # RDX:RAX / divisor
    mov r11,[rsp+16]
    mov [r11+rbx*8],rax
    jmp .rpfdu64_loop
.rpfdu64_quot_done:
    test rdx,rdx
    jz .rpfdu64_round
    mov r11,[rsp+16]
    or qword ptr [r11],1                  # remainder is sticky far below guard
.rpfdu64_round:
    # x = M*2^(E-(P-1)); Q approximates (M<<128)/d.  The +128 guard extension
    # is removed only through the shared strict RNE closure.
    mov r8,[r13+RPF_EXP]
    mov rax,[rsp]
    dec rax
    sub r8,rax
    sub r8,128
    mov rcx,[r13+RPF_SIGN]
    mov rdi,r12
    mov rsi,[rsp+16]
    mov edx,dword ptr [rsp+24]
    mov r9d,r15d
    call rpf_round_from_integer
    test eax,eax
    jnz .rpfdu64_bad
    xor eax,eax
    jmp .rpfdu64_done
.rpfdu64_bad:
    mov eax,1
.rpfdu64_done:
    add rsp,48
    RPF_RESTORE
    ret

# rdi=a,rsi=b -> eax=1 iff the represented fpP ValueFacts are bit-identical.
# Local propagation needs only representation equality, not a full numeric
# ordering episode.  This shared predicate is the convergence authority for
# sqrt/exp/log/sincos fixed-point silence.
rpf_value_equal:
    mov eax,dword ptr [rdi+RPF_TYPE]
    cmp dword ptr [rsi+RPF_TYPE],eax
    jne .rpfve_no
    mov rax,[rdi+RPF_PREC]
    cmp [rsi+RPF_PREC],rax
    jne .rpfve_no
    mov rdx,[rdi+RPF_SIGN]
    cmp [rsi+RPF_SIGN],rdx
    jne .rpfve_no
    mov rdx,[rdi+RPF_EXP]
    cmp [rsi+RPF_EXP],rdx
    jne .rpfve_no
    add rax,63
    jc .rpfve_no
    shr rax,6
    mov rcx,rax
    lea rdi,[rdi+RPF_DATA]
    lea rsi,[rsi+RPF_DATA]
    repe cmpsq
    sete al
    movzx eax,al
    ret
.rpfve_no:
    xor eax,eax
    ret

# rdi=a,rsi=b -> eax=-1/0/1 numeric comparison.  This is the sole P>64
# comparison authority: sign, normalized exponent and significand are compared
# directly.  Precision is data; no named-width or producer-shape route exists.
.global rankn_fp_cmp
rankn_fp_cmp:
    RPF_SAVE
    mov r12,rdi; mov r13,rsi
    mov rax,[r12+RPF_PREC]; cmp [r13+RPF_PREC],rax; jne .rpfcmp_bad
    mov rbx,rax; add rbx,63; shr rbx,6
    # Normalized nonzero ValueFacts are identified by their P-1 bit, so zero
    # classification is O(1) rather than two full significand scans.
    mov rdi,r12; call rpf_object_is_zero; mov r14d,eax
    mov rdi,r13; call rpf_object_is_zero; mov r15d,eax
    test r14d,r14d; jz .rpfcmp_a_nonzero
    test r15d,r15d; jnz .rpfcmp_eq
    cmp qword ptr [r13+RPF_SIGN],0; jne .rpfcmp_gt
    jmp .rpfcmp_lt
.rpfcmp_a_nonzero:
    test r15d,r15d; jz .rpfcmp_both_nonzero
    cmp qword ptr [r12+RPF_SIGN],0; jne .rpfcmp_lt
    jmp .rpfcmp_gt
.rpfcmp_both_nonzero:
    mov rax,[r12+RPF_SIGN]; mov rcx,[r13+RPF_SIGN]
    cmp rax,rcx; je .rpfcmp_same_sign
    test rax,rax; jnz .rpfcmp_lt
    jmp .rpfcmp_gt
.rpfcmp_same_sign:
    mov rdx,[r12+RPF_EXP]; mov r8,[r13+RPF_EXP]
    cmp rdx,r8; je .rpfcmp_sig
    ja .rpfcmp_mag_gt
    # |a| < |b|
    test rax,rax; jnz .rpfcmp_gt
    jmp .rpfcmp_lt
.rpfcmp_mag_gt:
    test rax,rax; jnz .rpfcmp_lt
    jmp .rpfcmp_gt
.rpfcmp_sig:
    lea rdi,[r12+RPF_DATA]; lea rsi,[r13+RPF_DATA]; mov ecx,ebx; call rpf_cmp
    test eax,eax; jz .rpfcmp_eq
    mov rcx,[r12+RPF_SIGN]
    test rcx,rcx; jz .rpfcmp_done
    neg eax
    jmp .rpfcmp_done
.rpfcmp_eq: xor eax,eax; jmp .rpfcmp_done
.rpfcmp_gt: mov eax,1; jmp .rpfcmp_done
.rpfcmp_lt: mov eax,-1; jmp .rpfcmp_done
.rpfcmp_bad: xor eax,eax
.rpfcmp_done:
    RPF_RESTORE
    ret

# rdi=dst,rsi=src -> rax=dst, edx status
.global rankn_fp_neg
rankn_fp_neg:
    push r12; push r13
    mov r12,rdi; mov r13,rsi
    cmp r12,r13
    je .rpfn_sign
    mov edx,[r13+RPF_TYPE]
    call rpf_copy_object
    mov edx,eax
    test eax,eax
    jnz .rpfn_done
.rpfn_sign:
    xor qword ptr [r12+RPF_SIGN],1
    xor edx,edx
.rpfn_done:
    mov rax,r12
    pop r13; pop r12
    ret
.global rankn_fp_abs
rankn_fp_abs:
    push r12; push r13
    mov r12,rdi; mov r13,rsi
    cmp r12,r13
    je .rpfa_sign
    mov edx,[r13+RPF_TYPE]
    call rpf_copy_object
    mov edx,eax
    test eax,eax
    jnz .rpfa_done
.rpfa_sign:
    mov qword ptr [r12+RPF_SIGN],0
    xor edx,edx
.rpfa_done:
    mov rax,r12
    pop r13; pop r12
    ret


# -----------------------------------------------------------------------------
# Precision-native transcendental relations (1.3.44).
# These routines consume only the existing fpP algebraic authority.  Their
# contraction depth and stopping point are derived from the local value and the
# current representation; no named-width implementation family exists.
# A caller provides a contiguous workspace of 32 ordinary fpP object spans.
# Slot 0 is the result.  Every slot is separated by the same P-derived physical
# span used by the compiler's ordinary fpP allocator, so Fourier/division scratch
# remains private without a runtime allocator.
# -----------------------------------------------------------------------------

# edi=encoded type -> rax exact physical object span /0.  One runtime
# authority mirrors g_rankn_fp_object_span: PrecisionFact plus its Fourier
# geometry determine the maximum live add/mul/compact-div layout.  No fixed
# bytes-per-limb envelope or subsystem-private span survives.
rpf_object_span:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp,16
    call rpf_precision_from_type
    test rax,rax
    jz .rpos_bad
    mov r12,rax                              # P
    mov r14d,edx                             # packed Fourier geometry
    add rax,63
    jc .rpos_bad
    shr rax,6
    mov r13,rax                              # N
    test r14d,r14d
    jz .rpos_bad

    mov ecx,r14d
    shr ecx,8
    and ecx,255
    cmp ecx,62
    ja .rpos_bad
    mov r15,1
    shl r15,cl
    mov edx,r14d
    shr edx,16
    and edx,255
.rpos_f3:
    test edx,edx
    jz .rpos_f5_start
    imul r15,r15,3
    jo .rpos_bad
    dec edx
    jmp .rpos_f3
.rpos_f5_start:
    mov edx,r14d
    shr edx,24
.rpos_f5:
    test edx,edx
    jz .rpos_have_fft
    imul r15,r15,5
    jo .rpos_bad
    dec edx
    jmp .rpos_f5
.rpos_have_fft:
    mov rbx,r13
    shl rbx,3
    add rbx,32                               # primary_end

    # Exact Fourier scratch end.
    mov rax,rbx
    add rax,63
    and rax,-64                              # A
    mov rcx,r15
    shl rcx,4
    add rax,rcx                              # T
    mov rcx,r15
    shl rcx,3
    add rax,rcx
    add rax,16
    add rax,63
    and rax,-64                              # product
    mov rcx,r13
    shl rcx,4
    add rcx,32                               # (2N+4)*8
    add rax,rcx
    mov [rsp],rax

    # Exact compact Knuth scratch end.
    mov r8,r12
    add r8,31
    shr r8,5                                 # nd
    mov r9,r12
    add r9,4
    shr r9,5                                 # qw
    mov r10,r8
    add r10,r9
    add r10,6                                # ucap
    mov rax,rbx
    mov rcx,r10
    shl rcx,2
    add rax,rcx                              # U
    mov rcx,r8
    add rcx,2
    shl rcx,2
    add rax,rcx                              # V
    mov rcx,r10
    shl rcx,2
    add rax,rcx                              # Q
    add rax,7
    and rax,-8                               # Q64
    mov rcx,r10
    add rcx,1
    shr rcx,1
    add rcx,1
    shl rcx,3
    add rax,rcx
    cmp rax,[rsp]
    jbe .rpos_add
    mov [rsp],rax
.rpos_add:
    mov rax,r13
    add rax,2
    shl rax,4
    add rax,rbx                              # two local add carriers
    cmp rax,[rsp]
    jbe .rpos_align
    mov [rsp],rax
.rpos_align:
    mov rax,[rsp]
    add rax,63
    and rax,-64
    jmp .rpos_done
.rpos_bad:
    xor eax,eax
.rpos_done:
    add rsp,16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# rdi=base,rsi=span,edx=slot -> rax slot pointer.
rpf_math_slot:
    mov eax,edx
    imul rax,rsi
    add rax,rdi
    ret

# rdi=dst, esi=encoded type, rdx=signed exponent -> eax status.
# Build the exact power-of-two 2^rdx in the destination representation.
rpf_make_pow2:
    RPF_SAVE
    mov r12,rdi; mov r13d,esi; mov r14,rdx
    mov rdi,r12; mov esi,r13d; call rpf_object_init
    test eax,eax; jnz .rpfmp_bad
    mov [r12+RPF_EXP],r14
    mov eax,[r12+RPF_PREC]; dec eax
    mov edx,eax; shr edx,6; and eax,63
    bts qword ptr [r12+RPF_DATA+rdx*8],rax
    xor eax,eax; jmp .rpfmp_done
.rpfmp_bad: mov eax,1
.rpfmp_done: RPF_RESTORE; ret

# rdi=obj -> eax=1 zero,0 nonzero. Normalized nonzero objects always own bit P-1.
rpf_object_is_zero:
    mov rax,[rdi+RPF_PREC]
    cmp rax,64
    jbe .rpfioz_yes
    dec rax
    mov rcx,rax
    shr rax,6
    and ecx,63
    mov rdx,[rdi+RPF_DATA+rax*8]
    bt rdx,rcx
    setnc al
    movzx eax,al
    ret
.rpfioz_yes:
    mov eax,1
    ret

# rdi=dst,rsi=src,edx=type -> eax status. Same-P copy is a carrier clone, not a conversion.
rpf_copy_object:
    push r12
    push r13
    mov r12,rdi
    mov r13,rsi
    cmp dword ptr [r13+RPF_TYPE],edx
    jne .rpfco_bad
    cmp r12,r13
    je .rpfco_ok
    mov rax,[r13+RPF_PREC]
    cmp rax,64
    jbe .rpfco_bad
    add rax,63
    jc .rpfco_bad
    shr rax,6
    add rax,4                 # four qwords of header plus N payload limbs
    mov rcx,rax
    mov rdi,r12
    mov rsi,r13
    rep movsq
.rpfco_ok:
    xor eax,eax
    jmp .rpfco_done
.rpfco_bad:
    mov eax,1
.rpfco_done:
    pop r13
    pop r12
    ret

# Local tolerance proof helpers.  The compiler supplies a conservative binary
# exponent k with 2^k <= the user contract.  These helpers never modify a
# ValueFact and never choose another arithmetic implementation.
# rdi=value,rsi=k -> eax=1 only when |value| < 2^k is proven from normalized E.
rpf_abs_lt_pow2:
    mov rax,[rdi+RPF_EXP]
    cmp rax,rsi
    setl al
    movzx eax,al
    ret

# rdi=numerator,rsi=denominator,rdx=k -> eax=1 only when |num/den| < 2^k.
# For normalized nonzero values, num < 2^(En+1), den >= 2^Ed.
rpf_abs_ratio_lt_pow2:
    mov rax,[rdi+RPF_EXP]
    sub rax,[rsi+RPF_EXP]
    jo .rpfar_no
    inc rax
    jo .rpfar_no
    cmp rax,rdx
    setle al
    movzx eax,al
    ret
.rpfar_no:
    xor eax,eax
    ret

# rdi=workspace base,rsi=src,edx=type,r8d=tolerance-active,r9=tolerance exponent.
.global rankn_fp_sqrt
rankn_fp_sqrt:
    RPF_SAVE
    sub rsp,64
    mov r12,rdi; mov r13,rsi; mov r14d,edx
    mov r11d,r8d
    mov [rsp+40],r9
    mov edi,r14d; call rpf_object_span; test rax,rax; jz .rpfsq_bad
    mov r15,rax
    cmp dword ptr [r13+RPF_TYPE],r14d; jne .rpfsq_bad
    mov rdi,r13; call rpf_object_is_zero; test eax,eax; jnz .rpfsq_zero
    cmp qword ptr [r13+RPF_SIGN],0; jne .rpfsq_bad
    # g = 2^ceil(E/2), a local exponent-derived seed.
    mov rdi,r12; mov rsi,r15; mov edx,1; call rpf_math_slot; mov [rsp],rax
    mov rdx,[r13+RPF_EXP]; mov rax,rdx; and eax,1; add rdx,rax; sar rdx,1
    mov rdi,[rsp]; mov esi,r14d; call rpf_make_pow2; test eax,eax; jnz .rpfsq_bad
    # prev2 = 0.
    mov rdi,r12; mov rsi,r15; mov edx,5; call rpf_math_slot; mov [rsp+8],rax
    mov rdi,rax; xor esi,esi; mov edx,r14d; call rankn_fp_from_u64; test edx,edx; jnz .rpfsq_bad
    # Stable local carriers are addressed once.  Iteration advances roles, not bytes.
    mov rdi,r12; mov rsi,r15; mov edx,2; call rpf_math_slot; mov [rsp+16],rax
    mov rdi,r12; mov rsi,r15; mov edx,3; call rpf_math_slot; mov [rsp+24],rax
    mov rdi,r12; mov rsi,r15; mov edx,4; call rpf_math_slot; mov [rsp+32],rax
    # slot6 is a relation-local delta carrier used only when tolerance is active.
    mov rdi,r12; mov rsi,r15; mov edx,6; call rpf_math_slot; mov [rsp+48],rax
    mov ebp,[r13+RPF_PREC]; add ebp,4
.rpfsq_loop:
    test ebp,ebp; jz .rpfsq_cap
    # q=x/g
    mov rdi,[rsp+16]; mov rsi,r13; mov rdx,[rsp]; mov ecx,r14d; call rankn_fp_div; test eax,eax; jnz .rpfsq_bad
    # s=g+q
    mov rdi,[rsp+24]; mov rsi,[rsp]; mov rdx,[rsp+16]; mov ecx,r14d; call rankn_fp_add; test eax,eax; jnz .rpfsq_bad
    # next=s/2 exactly by exponent shift after one carrier clone.
    mov rdi,[rsp+32]; mov rsi,[rsp+24]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsq_bad
    mov rdi,[rsp+32]; call rpf_object_is_zero; test eax,eax; jnz .rpfsq_next_ready
    mov rax,[rsp+32]; dec qword ptr [rax+RPF_EXP]
.rpfsq_next_ready:
    # Newton gives next=(g+x/g)/2.  For positive x and g, |next-sqrt(x)| is
    # bounded by |next-g|.  A tolerant relation may therefore close early only
    # after that local delta itself is proved below the conservative ToleranceFact.
    test r11d,r11d; jnz .rpfsq_tol_check
.rpfsq_rep_silence:
    mov rdi,[rsp+32]; mov rsi,[rsp]; call rpf_value_equal; test eax,eax; jnz .rpfsq_use_next
    mov rdi,[rsp+32]; mov rsi,[rsp+8]; call rpf_value_equal; test eax,eax; jnz .rpfsq_cycle
    # prev2 <- g ; g <- next.  Until ValueFact/scratch are separated, keeping
    # the hot state in stable adjacent carriers is physically cheaper than
    # rotating identities across full private-scratch spans.
    mov rdi,[rsp+8]; mov rsi,[rsp]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsq_bad
    mov rdi,[rsp]; mov rsi,[rsp+32]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsq_bad
    dec ebp; jmp .rpfsq_loop
.rpfsq_tol_check:
    mov rdi,[rsp+48]; mov rsi,[rsp+32]; mov rdx,[rsp]; mov ecx,r14d; call rankn_fp_sub; test eax,eax; jnz .rpfsq_bad
    mov rdi,[rsp+48]; mov rsi,[rsp+48]; call rankn_fp_abs; test edx,edx; jnz .rpfsq_bad
    mov rdi,[rsp+48]; mov rsi,[rsp+40]; call rpf_abs_lt_pow2
    test eax,eax; jnz .rpfsq_use_next
    jmp .rpfsq_rep_silence
.rpfsq_cycle:
    # Two representable neighbours can form a Newton 2-cycle. Pick the one with
    # the smaller |g^2-x| evidence rather than inventing an epsilon.
    mov rdi,r12; mov rsi,r15; mov edx,6; call rpf_math_slot; mov [rsp+16],rax
    mov rdi,rax; mov rsi,[rsp]; mov rdx,[rsp]; mov ecx,r14d; call rankn_fp_mul; test eax,eax; jnz .rpfsq_bad
    mov rdi,r12; mov rsi,r15; mov edx,7; call rpf_math_slot; mov [rsp+24],rax
    mov rdi,rax; mov rsi,[rsp+32]; mov rdx,[rsp+32]; mov ecx,r14d; call rankn_fp_mul; test eax,eax; jnz .rpfsq_bad
    mov rdi,r12; mov rsi,r15; mov edx,8; call rpf_math_slot; mov [rsp+8],rax
    mov rdi,rax; mov rsi,[rsp+16]; mov rdx,r13; mov ecx,r14d; call rankn_fp_sub; test eax,eax; jnz .rpfsq_bad
    mov rdi,r12; mov rsi,r15; mov edx,9; call rpf_math_slot; mov [rsp+16],rax
    mov rdi,rax; mov rsi,[rsp+24]; mov rdx,r13; mov ecx,r14d; call rankn_fp_sub; test eax,eax; jnz .rpfsq_bad
    mov rdi,[rsp+8]; mov rsi,[rsp+8]; call rankn_fp_abs; test edx,edx; jnz .rpfsq_bad
    mov rdi,[rsp+16]; mov rsi,[rsp+16]; call rankn_fp_abs; test edx,edx; jnz .rpfsq_bad
    mov rdi,[rsp+16]; mov rsi,[rsp+8]; call rankn_fp_cmp
    cmp eax,0; jl .rpfsq_use_next
    jmp .rpfsq_use_g
.rpfsq_cap:
    jmp .rpfsq_use_g
.rpfsq_use_next:
    mov rdi,r12; mov rsi,[rsp+32]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsq_bad
    xor eax,eax; jmp .rpfsq_done
.rpfsq_use_g:
    mov rdi,r12; mov rsi,[rsp]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsq_bad
    xor eax,eax; jmp .rpfsq_done
.rpfsq_zero:
    mov rdi,r12; mov rsi,r13; mov edx,r14d; call rpf_copy_object; jmp .rpfsq_done
.rpfsq_bad: mov eax,1
.rpfsq_done:
    add rsp,64
    RPF_RESTORE
    ret

# rdi=workspace base,rsi=src,edx=type,r8d=tolerance-active,r9=tolerance exponent -> eax status.
.global rankn_fp_exp
rankn_fp_exp:
    RPF_SAVE
    sub rsp,96
    mov r12,rdi; mov r13,rsi; mov r14d,edx
    mov r11d,r8d
    mov [rsp+72],r9
    mov edi,r14d; call rpf_object_span; test rax,rax; jz .rpfex_bad
    mov r15,rax
    cmp dword ptr [r13+RPF_TYPE],r14d; jne .rpfex_bad
    mov rax,[r13+RPF_SIGN]; mov [rsp+56],rax
    # y = x / 2^m, with the minimal local contraction m=max(E,0).
    mov rdi,r12; mov rsi,r15; mov edx,1; call rpf_math_slot; mov [rsp],rax
    mov rdi,rax; mov rsi,r13; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfex_bad
    # Work on |x|.  Sign is a projection fact restored only at the end via exp(-a)=1/exp(a).
    mov rax,[rsp]
    mov qword ptr [rax+RPF_SIGN],0
    mov rbx,[r13+RPF_EXP]; test rbx,rbx; jg .rpfex_have_m
    xor ebx,ebx
.rpfex_have_m:
    mov [rsp+48],rbx
    # Series-tail proof uses a relative local budget.  y is contracted below 2,
    # and repeated squaring can amplify relative error by roughly 2^m; reserve
    # additional binary slack (and one more bit for reciprocal restoration).
    test r11d,r11d; jz .rpfex_tol_ready
    mov rax,[rsp+72]
    sub rax,rbx
    jo .rpfex_tol_disable
    sub rax,3
    jo .rpfex_tol_disable
    cmp qword ptr [rsp+56],0
    je .rpfex_tol_store
    dec rax
    jo .rpfex_tol_disable
.rpfex_tol_store:
    mov [rsp+80],rax
    jmp .rpfex_tol_ready
.rpfex_tol_disable:
    xor r11d,r11d
.rpfex_tol_ready:
    mov rdi,[rsp]; call rpf_object_is_zero; test eax,eax; jnz .rpfex_y_ready
    mov rax,[rsp]; sub qword ptr [rax+RPF_EXP],rbx
.rpfex_y_ready:
    # one, sum, term
    mov rdi,r12; mov rsi,r15; mov edx,2; call rpf_math_slot; mov [rsp+8],rax
    mov rdi,rax; mov esi,1; mov edx,r14d; call rankn_fp_from_u64; test edx,edx; jnz .rpfex_bad
    mov rdi,r12; mov rsi,r15; mov edx,3; call rpf_math_slot; mov [rsp+16],rax
    mov rdi,rax; mov rsi,[rsp+8]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfex_bad
    mov rdi,r12; mov rsi,r15; mov edx,4; call rpf_math_slot; mov [rsp+24],rax
    mov rdi,rax; mov rsi,[rsp+8]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfex_bad
    mov rdi,r12; mov rsi,r15; mov edx,5; call rpf_math_slot; mov [rsp+32],rax
    mov rdi,r12; mov rsi,r15; mov edx,7; call rpf_math_slot; mov [rsp+40],rax
    mov qword ptr [rsp+64],1
    mov ebp,[r13+RPF_PREC]; add ebp,16
.rpfex_series:
    test ebp,ebp; jz .rpfex_series_done
    # tmp=term*y
    mov rdi,[rsp+32]; mov rsi,[rsp+24]; mov rdx,[rsp]; mov ecx,r14d; call rankn_fp_mul; test eax,eax; jnz .rpfex_bad
    # term = tmp / n.  The local series index stays an integer fact; do not
    # materialize a full fpP denominator only to invoke big/big division.
    mov rdi,[rsp+24]; mov rsi,[rsp+32]; mov rdx,[rsp+64]; mov ecx,r14d; call rankn_fp_div_u64; test eax,eax; jnz .rpfex_bad
    # nextsum uses the alternate sum carrier; silence is checked before role rotation.
    mov rdi,[rsp+40]; mov rsi,[rsp+16]; mov rdx,[rsp+24]; mov ecx,r14d; call rankn_fp_add; test eax,eax; jnz .rpfex_bad
    # For y<2 and n>=3, the positive Taylor tail after term_n is smaller than
    # term_n.  Proving term_n/sum below the contracted relative ToleranceFact
    # therefore permits semantic closure without changing any arithmetic op.
    test r11d,r11d; jnz .rpfex_tol_check
.rpfex_rep_silence:
    mov rdi,[rsp+40]; mov rsi,[rsp+16]; call rpf_value_equal; test eax,eax; jnz .rpfex_series_done
    mov rdi,[rsp+16]; mov rsi,[rsp+40]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfex_bad
    inc qword ptr [rsp+64]
    dec ebp; jmp .rpfex_series
.rpfex_tol_check:
    cmp qword ptr [rsp+64],3; jb .rpfex_rep_silence
    mov rdi,[rsp+24]; mov rsi,[rsp+40]; mov rdx,[rsp+80]; call rpf_abs_ratio_lt_pow2
    test eax,eax; jnz .rpfex_accept_next
    jmp .rpfex_rep_silence
.rpfex_accept_next:
    mov rdi,[rsp+16]; mov rsi,[rsp+40]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfex_bad
.rpfex_series_done:
    mov rdi,r12; mov rsi,[rsp+16]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfex_bad
    # Undo local contraction by repeated squaring.
    mov rbp,[rsp+48]
.rpfex_square:
    test rbp,rbp; jz .rpfex_sign
    mov rdi,r12; mov rsi,r15; mov edx,8; call rpf_math_slot; mov rbx,rax
    mov rdi,rbx; mov rsi,r12; mov rdx,r12; mov ecx,r14d; call rankn_fp_mul; test eax,eax; jnz .rpfex_bad
    mov rdi,r12; mov rsi,rbx; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfex_bad
    dec rbp; jmp .rpfex_square
.rpfex_sign:
    cmp qword ptr [rsp+56],0; je .rpfex_ok
    # exp(-a)=1/exp(a)
    mov rdi,r12; mov rsi,r15; mov edx,9; call rpf_math_slot; mov rbx,rax
    mov rdi,rbx; mov esi,1; mov edx,r14d; call rankn_fp_from_u64; test edx,edx; jnz .rpfex_bad
    mov rdi,r12; mov rsi,r15; mov edx,10; call rpf_math_slot; mov rbp,rax
    mov rdi,rbp; mov rsi,rbx; mov rdx,r12; mov ecx,r14d; call rankn_fp_div; test eax,eax; jnz .rpfex_bad
    mov rdi,r12; mov rsi,rbp; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfex_bad
.rpfex_ok: xor eax,eax; jmp .rpfex_done
.rpfex_bad: mov eax,1
.rpfex_done:
    add rsp,96
    RPF_RESTORE
    ret

# rdi=workspace base,rsi=src,edx=type,r8d=tolerance-active,r9=tolerance exponent -> eax status.
.global rankn_fp_log
rankn_fp_log:
    RPF_SAVE
    sub rsp,128
    mov r12,rdi; mov r13,rsi; mov r14d,edx
    mov r11d,r8d
    mov [rsp+96],r9
    mov edi,r14d; call rpf_object_span; test rax,rax; jz .rpflg_bad
    mov r15,rax
    cmp dword ptr [r13+RPF_TYPE],r14d; jne .rpflg_bad
    mov rdi,r13; call rpf_object_is_zero; test eax,eax; jnz .rpflg_bad
    cmp qword ptr [r13+RPF_SIGN],0; jne .rpflg_bad
    # z=src slot1; one slot2
    mov rdi,r12; mov rsi,r15; mov edx,1; call rpf_math_slot; mov [rsp],rax
    mov rdi,rax; mov rsi,r13; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpflg_bad
    mov rdi,r12; mov rsi,r15; mov edx,2; call rpf_math_slot; mov [rsp+8],rax
    mov rdi,rax; mov esi,1; mov edx,r14d; call rankn_fp_from_u64; test edx,edx; jnz .rpflg_bad
    # The nested sqrt region is fixed for the whole contraction chain.
    mov rdi,r12; mov rsi,r15; mov edx,16; call rpf_math_slot; mov [rsp+64],rax
    xor ebx,ebx                         # number of local sqrt contractions
.rpflg_contract:
    mov rax,[rsp]; mov rcx,[rax+RPF_EXP]
    cmp rcx,0; jg .rpflg_do_sqrt
    cmp rcx,-1; jl .rpflg_do_sqrt
    jmp .rpflg_contract_done
.rpflg_do_sqrt:
    # Nested sqrt is an internal contraction, not an observable tolerance
    # boundary. Keep it strict so the outer log relation owns the sole error fact.
    xor r8d,r8d; xor r9d,r9d
    mov rdi,[rsp+64]; mov rsi,[rsp]; mov edx,r14d; call rankn_fp_sqrt; test eax,eax; jnz .rpflg_bad
    mov rdi,[rsp]; mov rsi,[rsp+64]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpflg_bad
    inc ebx; jmp .rpflg_contract
.rpflg_contract_done:
    mov [rsp+72],rbx
    # atanh(u) has |u|<=1/3 after contraction.  The tail after a retained odd
    # term is below term/8; restoring log(x) multiplies by 2^(contractions+1).
    # Therefore term < tolerance*2^(2-contractions) proves the final abs tail.
    test r11d,r11d; jz .rpflg_tol_ready
    mov rax,[rsp+96]
    sub rax,[rsp+72]
    jo .rpflg_tol_disable
    add rax,2
    jo .rpflg_tol_disable
    mov [rsp+104],rax
    jmp .rpflg_tol_ready
.rpflg_tol_disable:
    xor r11d,r11d
.rpflg_tol_ready:
    # u=(z-1)/(z+1)
    mov rdi,r12; mov rsi,r15; mov edx,3; call rpf_math_slot; mov [rsp+16],rax
    mov rdi,rax; mov rsi,[rsp]; mov rdx,[rsp+8]; mov ecx,r14d; call rankn_fp_sub; test eax,eax; jnz .rpflg_bad
    mov rdi,r12; mov rsi,r15; mov edx,4; call rpf_math_slot; mov [rsp+24],rax
    mov rdi,rax; mov rsi,[rsp]; mov rdx,[rsp+8]; mov ecx,r14d; call rankn_fp_add; test eax,eax; jnz .rpflg_bad
    mov rdi,r12; mov rsi,r15; mov edx,5; call rpf_math_slot; mov [rsp+32],rax
    mov rdi,rax; mov rsi,[rsp+16]; mov rdx,[rsp+24]; mov ecx,r14d; call rankn_fp_div; test eax,eax; jnz .rpflg_bad
    # u2 slot6, power slot7, sum slot8
    mov rdi,r12; mov rsi,r15; mov edx,6; call rpf_math_slot; mov [rsp+40],rax
    mov rdi,rax; mov rsi,[rsp+32]; mov rdx,[rsp+32]; mov ecx,r14d; call rankn_fp_mul; test eax,eax; jnz .rpflg_bad
    mov rdi,r12; mov rsi,r15; mov edx,7; call rpf_math_slot; mov [rsp+48],rax
    mov rdi,rax; mov rsi,[rsp+32]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpflg_bad
    mov rdi,r12; mov rsi,r15; mov edx,8; call rpf_math_slot; mov [rsp+56],rax
    mov rdi,rax; mov rsi,[rsp+32]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpflg_bad
    # Slots 3/4 are dead after u is formed; reuse their pointer cells for stable series scratch.
    mov rdi,r12; mov rsi,r15; mov edx,9; call rpf_math_slot; mov [rsp+16],rax
    mov rdi,r12; mov rsi,r15; mov edx,11; call rpf_math_slot; mov [rsp+24],rax
    mov rdi,r12; mov rsi,r15; mov edx,12; call rpf_math_slot; mov [rsp+88],rax
    mov qword ptr [rsp+80],3
    mov ebp,[r13+RPF_PREC]; add ebp,16
.rpflg_series:
    test ebp,ebp; jz .rpflg_series_done
    # power *= u2 into the alternate carrier, then rotate identities.
    mov rdi,[rsp+16]; mov rsi,[rsp+48]; mov rdx,[rsp+40]; mov ecx,r14d; call rankn_fp_mul; test eax,eax; jnz .rpflg_bad
    mov rdi,[rsp+48]; mov rsi,[rsp+16]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpflg_bad
    # fraction = power / odd_integer.  The denominator stays a scalar fact.
    mov rdi,[rsp+24]; mov rsi,[rsp+48]; mov rdx,[rsp+80]; mov ecx,r14d; call rankn_fp_div_u64; test eax,eax; jnz .rpflg_bad
    mov rdi,[rsp+88]; mov rsi,[rsp+56]; mov rdx,[rsp+24]; mov ecx,r14d; call rankn_fp_add; test eax,eax; jnz .rpflg_bad
    test r11d,r11d; jnz .rpflg_tol_check
.rpflg_rep_silence:
    mov rdi,[rsp+88]; mov rsi,[rsp+56]; call rpf_value_equal; test eax,eax; jnz .rpflg_series_done
    mov rdi,[rsp+56]; mov rsi,[rsp+88]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpflg_bad
    add qword ptr [rsp+80],2
    dec ebp; jmp .rpflg_series
.rpflg_tol_check:
    mov rdi,[rsp+24]; mov rsi,[rsp+104]; call rpf_abs_lt_pow2
    test eax,eax; jnz .rpflg_accept_next
    jmp .rpflg_rep_silence
.rpflg_accept_next:
    mov rdi,[rsp+56]; mov rsi,[rsp+88]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpflg_bad
.rpflg_series_done:
    mov rdi,r12; mov rsi,[rsp+56]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpflg_bad
    # log(x)=2^(k+1)*atanh(u). Exact power-of-two restoration only touches E.
    mov rdi,r12; call rpf_object_is_zero; test eax,eax; jnz .rpflg_ok
    mov rax,[rsp+72]; inc rax; add [r12+RPF_EXP],rax
.rpflg_ok: xor eax,eax; jmp .rpflg_done
.rpflg_bad: mov eax,1
.rpflg_done:
    add rsp,128
    RPF_RESTORE
    ret

# Shared local-propagation sine/cosine authority. ecx=0 sine,1 cosine.
rpf_sincos_core:
    RPF_SAVE
    sub rsp,160
    mov r12,rdi
    mov r13,rsi
    mov r14d,edx
    mov dword ptr [rsp+120],ecx
    mov r11d,r8d
    mov [rsp+128],r9
    mov edi,r14d
    call rpf_object_span
    test rax,rax
    jz .rpfsc_bad
    mov r15,rax
    cmp dword ptr [r13+RPF_TYPE],r14d
    jne .rpfsc_bad

    # y = x / 2^m, m=max(E,0).  The contraction follows the local
    # represented scale; it is not selected by a named precision family.
    mov rdi,r12; mov rsi,r15; mov edx,1; call rpf_math_slot; mov [rsp],rax
    mov rdi,rax; mov rsi,r13; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsc_bad
    mov rax,[r13+RPF_EXP]
    test rax,rax
    jg .rpfsc_have_m
    xor eax,eax
.rpfsc_have_m:
    mov [rsp+104],rax
    # The coupled double-angle map can amplify an absolute pair error.  A factor
    # of eight per restoration step is a conservative envelope for values inside
    # the unit pair, so the local series budget is tolerance/8^m with extra slack.
    test r11d,r11d; jz .rpfsc_tol_ready
    mov rax,[rsp+104]
    imul rax,rax,3
    jo .rpfsc_tol_disable
    mov rcx,[rsp+128]
    sub rcx,rax
    jo .rpfsc_tol_disable
    dec rcx
    jo .rpfsc_tol_disable
    mov [rsp+136],rcx
    jmp .rpfsc_tol_ready
.rpfsc_tol_disable:
    xor r11d,r11d
.rpfsc_tol_ready:
    mov rdi,[rsp]; call rpf_object_is_zero; test eax,eax; jnz .rpfsc_y_ready
    mov rax,[rsp]
    mov rcx,[rsp+104]
    sub qword ptr [rax+RPF_EXP],rcx
.rpfsc_y_ready:

    # Persistent local facts: y2, one, sin(sum,term), cos(sum,term).
    mov rdi,r12; mov rsi,r15; mov edx,2; call rpf_math_slot; mov [rsp+8],rax
    mov rdi,rax; mov rsi,[rsp]; mov rdx,[rsp]; mov ecx,r14d; call rankn_fp_mul; test eax,eax; jnz .rpfsc_bad
    mov rdi,r12; mov rsi,r15; mov edx,3; call rpf_math_slot; mov [rsp+16],rax
    mov rdi,rax; mov esi,1; mov edx,r14d; call rankn_fp_from_u64; test edx,edx; jnz .rpfsc_bad

    mov rdi,r12; mov rsi,r15; mov edx,4; call rpf_math_slot; mov [rsp+24],rax
    mov rdi,rax; mov rsi,[rsp]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsc_bad
    mov rdi,r12; mov rsi,r15; mov edx,5; call rpf_math_slot; mov [rsp+32],rax
    mov rdi,rax; mov rsi,[rsp]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsc_bad
    mov rdi,r12; mov rsi,r15; mov edx,6; call rpf_math_slot; mov [rsp+40],rax
    mov rdi,rax; mov rsi,[rsp+16]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsc_bad
    mov rdi,r12; mov rsi,r15; mov edx,7; call rpf_math_slot; mov [rsp+48],rax
    mov rdi,rax; mov rsi,[rsp+16]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsc_bad

    # Scratch facts use stable slot identities.  Keep every pointer in the
    # local frame so nested arithmetic cannot turn a caller-saved register into
    # hidden state.
    mov rdi,r12; mov rsi,r15; mov edx,8; call rpf_math_slot; mov [rsp+56],rax
    # slot9 is retained only as the double-angle output carrier; series negation
    # is an in-place sign fact and no longer copies into it.
    mov rdi,r12; mov rsi,r15; mov edx,9; call rpf_math_slot; mov [rsp+64],rax
    mov rdi,r12; mov rsi,r15; mov edx,10; call rpf_math_slot; mov [rsp+72],rax
    mov rdi,r12; mov rsi,r15; mov edx,11; call rpf_math_slot; mov [rsp+80],rax
    mov rdi,r12; mov rsi,r15; mov edx,12; call rpf_math_slot; mov [rsp+88],rax
    mov rdi,r12; mov rsi,r15; mov edx,13; call rpf_math_slot; mov [rsp+96],rax
    mov qword ptr [rsp+112],1
    mov ebp,[r13+RPF_PREC]
    add ebp,16

.rpfsc_series:
    test ebp,ebp
    jz .rpfsc_series_done

    # sin term_j = -term_{j-1}*y^2 / ((2j)(2j+1)).
    mov rdi,[rsp+56]; mov rsi,[rsp+32]; mov rdx,[rsp+8]; mov ecx,r14d; call rankn_fp_mul; test eax,eax; jnz .rpfsc_bad
    mov rax,[rsp+56]; xor qword ptr [rax+RPF_SIGN],1
    mov rax,[rsp+112]; lea rdx,[rax+rax]
    mov rdi,[rsp+80]; mov rsi,[rsp+56]; mov ecx,r14d; call rankn_fp_div_u64; test eax,eax; jnz .rpfsc_bad
    mov rax,[rsp+112]; lea rdx,[rax+rax+1]
    mov rdi,[rsp+32]; mov rsi,[rsp+80]; mov ecx,r14d; call rankn_fp_div_u64; test eax,eax; jnz .rpfsc_bad
    mov rdi,[rsp+88]; mov rsi,[rsp+24]; mov rdx,[rsp+32]; mov ecx,r14d; call rankn_fp_add; test eax,eax; jnz .rpfsc_bad

    # cos term_j = -term_{j-1}*y^2 / ((2j-1)(2j)).
    mov rdi,[rsp+56]; mov rsi,[rsp+48]; mov rdx,[rsp+8]; mov ecx,r14d; call rankn_fp_mul; test eax,eax; jnz .rpfsc_bad
    mov rax,[rsp+56]; xor qword ptr [rax+RPF_SIGN],1
    mov rax,[rsp+112]; lea rdx,[rax+rax-1]
    mov rdi,[rsp+80]; mov rsi,[rsp+56]; mov ecx,r14d; call rankn_fp_div_u64; test eax,eax; jnz .rpfsc_bad
    mov rax,[rsp+112]; lea rdx,[rax+rax]
    mov rdi,[rsp+48]; mov rsi,[rsp+80]; mov ecx,r14d; call rankn_fp_div_u64; test eax,eax; jnz .rpfsc_bad
    mov rdi,[rsp+96]; mov rsi,[rsp+40]; mov rdx,[rsp+48]; mov ecx,r14d; call rankn_fp_add; test eax,eax; jnz .rpfsc_bad

    # For |y|<2 the sine terms decrease from j=1 and cosine terms from j=2.
    # Once j>=2, each alternating Taylor tail is bounded by the retained term.
    # Only then may the coupled relation consume the conservative local budget.
    test r11d,r11d; jnz .rpfsc_tol_check
.rpfsc_rep_silence:
    # Representation-local termination: once neither sum changes in the
    # current P-bit representation, additional local propagation is silent.
    mov rdi,[rsp+88]; mov rsi,[rsp+24]; call rpf_value_equal; mov ebx,eax
    mov rdi,[rsp+96]; mov rsi,[rsp+40]; call rpf_value_equal; and eax,ebx
    test eax,eax
    jnz .rpfsc_series_done
    mov rdi,[rsp+24]; mov rsi,[rsp+88]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsc_bad
    mov rdi,[rsp+40]; mov rsi,[rsp+96]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsc_bad
    inc qword ptr [rsp+112]
    dec ebp
    jmp .rpfsc_series

.rpfsc_tol_check:
    cmp qword ptr [rsp+112],2; jb .rpfsc_rep_silence
    mov rdi,[rsp+32]; mov rsi,[rsp+136]; call rpf_abs_lt_pow2
    test eax,eax; jz .rpfsc_rep_silence
    mov rdi,[rsp+48]; mov rsi,[rsp+136]; call rpf_abs_lt_pow2
    test eax,eax; jnz .rpfsc_accept_next
    jmp .rpfsc_rep_silence
.rpfsc_accept_next:
    mov rdi,[rsp+24]; mov rsi,[rsp+88]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsc_bad
    mov rdi,[rsp+40]; mov rsi,[rsp+96]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsc_bad
.rpfsc_series_done:
    # Undo contraction by the coupled double-angle map.  The pair propagates
    # together, so no independent phase-reduction branch is introduced.
    mov rbp,[rsp+104]
.rpfsc_double:
    test rbp,rbp
    jz .rpfsc_output
    # newSin = 2*sin*cos.  Multiplication produces the exact binary product;
    # multiplication by two is only an exponent fact, never another fpP add.
    mov rdi,[rsp+64]; mov rsi,[rsp+24]; mov rdx,[rsp+40]; mov ecx,r14d; call rankn_fp_mul; test eax,eax; jnz .rpfsc_bad
    mov rdi,[rsp+64]; call rpf_object_is_zero; test eax,eax; jnz .rpfsc_newsin_ready
    mov rax,[rsp+64]; inc qword ptr [rax+RPF_EXP]
.rpfsc_newsin_ready:
    # newCos = cos^2 - sin^2.
    mov rdi,[rsp+72]; mov rsi,[rsp+40]; mov rdx,[rsp+40]; mov ecx,r14d; call rankn_fp_mul; test eax,eax; jnz .rpfsc_bad
    mov rdi,[rsp+80]; mov rsi,[rsp+24]; mov rdx,[rsp+24]; mov ecx,r14d; call rankn_fp_mul; test eax,eax; jnz .rpfsc_bad
    mov rdi,[rsp+88]; mov rsi,[rsp+72]; mov rdx,[rsp+80]; mov ecx,r14d; call rankn_fp_sub; test eax,eax; jnz .rpfsc_bad
    mov rdi,[rsp+24]; mov rsi,[rsp+64]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsc_bad
    mov rdi,[rsp+40]; mov rsi,[rsp+88]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsc_bad
    dec rbp
    jmp .rpfsc_double

.rpfsc_output:
    cmp dword ptr [rsp+120],0
    jne .rpfsc_out_cos
    mov rdi,r12; mov rsi,[rsp+24]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsc_bad
    xor eax,eax
    jmp .rpfsc_done
.rpfsc_out_cos:
    mov rdi,r12; mov rsi,[rsp+40]; mov edx,r14d; call rpf_copy_object; test eax,eax; jnz .rpfsc_bad
    xor eax,eax
    jmp .rpfsc_done
.rpfsc_bad:
    mov eax,1
.rpfsc_done:
    add rsp,160
    RPF_RESTORE
    ret

.global rankn_fp_sin
rankn_fp_sin:
    xor ecx,ecx
    jmp rpf_sincos_core
.global rankn_fp_cos
rankn_fp_cos:
    mov ecx,1
    jmp rpf_sincos_core

# rdi=src -> rax=f64 bits, edx status. Handles normal finite output and zero;
# subnormal/overflow are rounded to zero/inf boundaries deterministically.
.global rankn_fp_to_f64_bits
rankn_fp_to_f64_bits:
    RPF_SAVE
    sub rsp,32
    mov r12,rdi
    mov r13,[r12+RPF_PREC]; add r13,63; shr r13,6
    lea rdi,[r12+RPF_DATA]; mov ecx,r13d; call rpf_msb
    test eax,eax; js .rpftd_zero
    mov r14,[r12+RPF_EXP]
    cmp r14,1023; jg .rpftd_inf
    cmp r14,-1022; jl .rpftd_subzero
    # Extract top 53 bits with RNE.
    mov edx,[r12+RPF_PREC]; sub edx,53; mov [rsp],edx
    xor r15,r15
    # read bits [shift, shift+52] one by one; only 53 iterations.
    xor ebx,ebx
.rpftd_bits:
    cmp ebx,53; jae .rpftd_round
    mov edx,[rsp]; add edx,ebx
    lea rdi,[r12+RPF_DATA]; mov ecx,r13d; call rpf_test_bit
    test eax,eax; jz .rpftd_next
    bts r15,rbx
.rpftd_next: inc ebx; jmp .rpftd_bits
.rpftd_round:
    mov edx,[rsp]; test edx,edx; jle .rpftd_pack
    dec edx; lea rdi,[r12+RPF_DATA]; mov ecx,r13d; call rpf_test_bit; mov ebx,eax
    mov edx,[rsp]; dec edx; lea rdi,[r12+RPF_DATA]; mov ecx,r13d; call rpf_any_low_bits; mov ebp,eax
    test ebx,ebx; jz .rpftd_pack
    test ebp,ebp; jnz .rpftd_inc
    test r15,1; jz .rpftd_pack
.rpftd_inc:
    inc r15
    bt r15,53
    jnc .rpftd_pack
    shr r15,1; inc r14
    cmp r14,1023; jg .rpftd_inf
.rpftd_pack:
    mov rax,r15
    mov rcx,0x0007ffffffffffff
    and rax,rcx
    mov rcx,r14; add rcx,1023; shl rcx,52; or rax,rcx
    mov rcx,[r12+RPF_SIGN]; shl rcx,63; or rax,rcx
    xor edx,edx; jmp .rpftd_done
.rpftd_zero: xor eax,eax; xor edx,edx; jmp .rpftd_done
.rpftd_subzero: xor eax,eax; mov rcx,[r12+RPF_SIGN]; shl rcx,63; or rax,rcx; xor edx,edx; jmp .rpftd_done
.rpftd_inf: mov rax,0x7ff0000000000000; mov rcx,[r12+RPF_SIGN]; shl rcx,63; or rax,rcx; xor edx,edx
.rpftd_done: add rsp,32; RPF_RESTORE; ret
