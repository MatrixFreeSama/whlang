.intel_syntax noprefix
.include "compiler/general_runtime_capacity.inc"
# General scalar/control runtime image for the handwritten-assembly language compiler.
# The compiler patches instance descriptors; type vectors and direct native code
# live in one exact-sized read-only trailer. There is no interpreter, VM, libc, dynamic loader dependency, or
# user-program assembler/linker invocation.

.equ SYS_write, 1
.equ SYS_close, 3
.equ SYS_mmap, 9
.equ SYS_openat, 257
.equ SYS_exit_group, 231
.equ PROT_READ_WRITE, 3
.equ PROT_READ_EXEC, 5
.equ MAP_PRIVATE, 2
.equ MAP_PRIVATE_ANON_FIXED_NOREPLACE, 0x100022
.equ AT_FDCWD, -100
.equ SLOT_BYTES, 8
.equ TYPE_BOOL, 1
.equ TYPE_I64, 2
.equ TYPE_U64, 3
.equ TYPE_F32, 4
.equ TYPE_F64, 5
.equ TYPE_STRING, 6
.equ TYPE_STATIC_LAST, 102

# Parameterized >64-bit floating physical authority. Type identity is compact;
# its precision payload lives in the exact-sized read-only PrecisionFact trailer.
.include "runtime/rankn_precision_physical_x86_64.inc"

.section .text
.global _start
_start:
    mov r15,rsp
    # All mutable structures whose cardinality belongs to this program rather
    # than the runtime ABI live in one exact AOT-sized anonymous arena.  The
    # compiler patches only the required byte span; no state/fpP capacity table
    # is reserved in the ELF BSS.
    mov rsi,qword ptr [rip+dynamic_arena_bytes_patch]
    test rsi,rsi
    jz .arena_ready
    mov eax,SYS_mmap
    mov rdi,GENERAL_RUNTIME_DYNAMIC_ARENA_VA
    mov edx,PROT_READ_WRITE
    mov r10d,MAP_PRIVATE_ANON_FIXED_NOREPLACE
    mov r8,-1
    xor r9d,r9d
    syscall
    mov rdx,GENERAL_RUNTIME_DYNAMIC_ARENA_VA
    cmp rax,rdx
    jne .arena_fail
.arena_ready:
    # Generated type vectors and native code share one exact-sized read/execute
    # trailer.  Counts determine metadata extent; no template array owns program
    # cardinality.  Zero trailer size keeps the standalone template callable.
    lea rax,[rip+program_slot]
    mov qword ptr [rip+program_code_ptr],rax
    mov qword ptr [rip+input_type_ptr],0
    mov qword ptr [rip+output_type_ptr],0
    mov qword ptr [rip+rankn_physical_fact_ptr],0
    mov rsi,qword ptr [rip+program_trailer_size_patch]
    test rsi,rsi
    jz .program_ready
    mov eax,SYS_openat
    mov edi,AT_FDCWD
    lea rsi,[rip+self_exe_path]
    xor edx,edx
    xor r10d,r10d
    syscall
    test rax,rax
    js .arena_fail
    mov r12,rax
    xor edi,edi
    mov rsi,qword ptr [rip+program_trailer_size_patch]
    mov edx,PROT_READ_EXEC
    mov r10d,MAP_PRIVATE
    mov r8,r12
    mov r9,qword ptr [rip+program_trailer_file_offset_patch]
    mov eax,SYS_mmap
    syscall
    test rax,rax
    js .program_map_fail
    mov qword ptr [rip+input_type_ptr],rax
    mov ecx,dword ptr [rip+input_count_patch]
    lea rdx,[rax+rcx*4]
    mov qword ptr [rip+output_type_ptr],rdx
    mov ecx,dword ptr [rip+output_count_patch]
    lea rdx,[rdx+rcx*4]
    mov qword ptr [rip+rankn_physical_fact_ptr],rdx
    mov rcx,qword ptr [rip+program_code_rel_offset_patch]
    add rax,rcx
    jc .program_map_fail_mapped
    mov qword ptr [rip+program_code_ptr],rax
    mov eax,SYS_close
    mov rdi,r12
    syscall
    jmp .program_ready
.program_map_fail_mapped:
    # The mapping is process-lifetime and a failed descriptor is fatal; closing
    # the file is sufficient before rejection.
.program_map_fail:
    mov eax,SYS_close
    mov rdi,r12
    syscall
    jmp .arena_fail
.program_ready:
    mov rax,[r15]                  # argc
    mov ecx,dword ptr [rip+input_count_patch]
    lea rdx,[rcx+1]
    cmp rax,rdx
    jne .bad_args
    lea r12,[r15+16]               # argv[1]
    mov r13,qword ptr [rip+input_values_base_patch]
    mov r14,qword ptr [rip+input_type_ptr]
    mov rax,qword ptr [rip+rankn_input_base_patch]
    mov qword ptr [rip+rankn_input_cursor],rax
    xor ebx,ebx
.parse_inputs:
    # Decimal parsers use caller-saved RCX internally. Reload immutable input count.
    cmp ebx,dword ptr [rip+input_count_patch]
    jae .run
    mov rdi,[r12+rbx*8]
    mov eax,dword ptr [r14+rbx*4]
    cmp eax,TYPE_BOOL
    je .in_bool
    cmp eax,TYPE_I64
    je .in_i64
    cmp eax,TYPE_U64
    je .in_u64
    cmp eax,TYPE_F32
    je .in_f32
    cmp eax,TYPE_F64
    je .in_f64
    cmp eax,TYPE_STRING
    je .in_string
    push rdi
    mov edi,eax
    call rpf_precision_from_type
    pop rdi
    test rax,rax
    jnz .in_rankn_fp
    jmp .bad_args
.in_bool:
    call parse_bool
    test edx,edx
    jnz .bad_args
    mov [r13+rbx*SLOT_BYTES],rax
    jmp .in_next
.in_i64:
    call parse_i64
    test edx,edx
    jnz .bad_args
    mov [r13+rbx*SLOT_BYTES],rax
    jmp .in_next
.in_u64:
    call parse_u64
    test edx,edx
    jnz .bad_args
    mov [r13+rbx*SLOT_BYTES],rax
    jmp .in_next
.in_f32:
    call parse_f64
    test edx,edx
    jnz .bad_args
    movq xmm0,rax
    cvtsd2ss xmm0,xmm0
    movd eax,xmm0
    mov [r13+rbx*SLOT_BYTES],rax
    jmp .in_next
.in_f64:
    call parse_f64
    test edx,edx
    jnz .bad_args
    mov [r13+rbx*SLOT_BYTES],rax
    jmp .in_next
.in_rankn_fp:
    mov edx,dword ptr [r14+rbx*4]   # encoded fpP
    call parse_rankn_fp
    test edx,edx
    jnz .bad_args
    mov [r13+rbx*SLOT_BYTES],rax
    jmp .in_next
.in_string:
    mov [r13+rbx*SLOT_BYTES],rdi
    call cstrlen
    mov r10,qword ptr [rip+input_aux_base_patch]
    mov [r10+rbx*8],rax
.in_next:
    inc ebx
    jmp .parse_inputs

.run:
    mov rax,qword ptr [rip+program_code_ptr]
    call rax
    test eax,eax
    jnz .runtime_reject
    xor ebx,ebx
.print_loop:
    # Output helpers use rcx internally; compare directly against the patched
    # count so helper scratch state can never extend the output loop.
    cmp ebx,dword ptr [rip+output_count_patch]
    jae .ok
    mov r10,qword ptr [rip+output_type_ptr]
    mov eax,dword ptr [r10+rbx*4]
    cmp eax,TYPE_STRING
    je .print_string
    mov edi,eax
    call rpf_precision_from_type
    test rax,rax
    jnz .print_rankn_fp
    mov rax,rbx
    call make_out_index
    mov r10,qword ptr [rip+output_pages_base_patch]
    mov rax,rbx
    shl rax,12
    mov rax,[r10+rax]
    call print_bits_line
    inc ebx
    jmp .print_loop
.print_rankn_fp:
    mov rax,rbx
    call make_out_index
    mov r10,qword ptr [rip+output_pages_base_patch]
    mov rax,rbx
    shl rax,12
    mov rdi,[r10+rax]               # qword payload is wide-object address
    mov esi,ebx                     # output index
    call print_rankn_fp_line
    inc ebx
    jmp .print_loop
.print_string:
    mov rax,rbx
    call make_out_index
    mov eax,SYS_write
    mov edi,1
    lea rsi,[rip+out_string_prefix]
    mov edx,out_string_prefix_end-out_string_prefix
    syscall
    mov eax,SYS_write
    mov edi,1
    mov r10,qword ptr [rip+output_pages_base_patch]
    mov rax,rbx
    shl rax,12
    mov rsi,[r10+rax]
    mov r10,qword ptr [rip+output_aux_base_patch]
    mov rdx,[r10+rbx*8]
    syscall
    mov eax,SYS_write
    mov edi,1
    lea rsi,[rip+newline]
    mov edx,1
    syscall
    inc ebx
    jmp .print_loop
.ok:
    xor edi,edi
    mov eax,SYS_exit_group
    syscall
.runtime_reject:
    mov edi,65
    mov eax,SYS_exit_group
    syscall
.arena_fail:
    mov edi,65
    mov eax,SYS_exit_group
    syscall
.bad_args:
    mov edi,2
    mov eax,SYS_exit_group
    syscall

# Standalone-template fallback only.  Compiled programs execute the exact-sized
# trailer mapped above; no fixed executable slot participates in admission.
.p2align 6
.global program_slot
program_slot:
    xor eax,eax
    ret

# parse bool -> rax 0/1, edx err
parse_bool:
    cmp byte ptr [rdi],'0'
    jne 1f
    cmp byte ptr [rdi+1],0
    jne .pb_bad
    xor eax,eax; xor edx,edx; ret
1:  cmp byte ptr [rdi],'1'
    jne 2f
    cmp byte ptr [rdi+1],0
    jne .pb_bad
    mov eax,1; xor edx,edx; ret
2:  cmp dword ptr [rdi],0x65757274  # true
    jne 3f
    cmp byte ptr [rdi+4],0
    jne .pb_bad
    mov eax,1; xor edx,edx; ret
3:  cmp dword ptr [rdi],0x736c6166  # fals
    jne .pb_bad
    cmp byte ptr [rdi+4],'e'
    jne .pb_bad
    cmp byte ptr [rdi+5],0
    jne .pb_bad
    xor eax,eax; xor edx,edx; ret
.pb_bad: xor eax,eax; mov edx,1; ret

parse_u64:
    xor eax,eax
    xor edx,edx
    xor ecx,ecx
.pu_loop:
    movzx r8d,byte ptr [rdi]
    test r8b,r8b
    jz .pu_done
    cmp r8b,'0'; jb .pu_bad
    cmp r8b,'9'; ja .pu_bad
    mov r9,1844674407370955161
    cmp rax,r9; ja .pu_bad
    imul rax,rax,10
    sub r8d,'0'
    add rax,r8
    jc .pu_bad
    inc rdi; inc ecx; jmp .pu_loop
.pu_done:
    test ecx,ecx; jz .pu_bad
    xor edx,edx; ret
.pu_bad: xor eax,eax; mov edx,1; ret

parse_i64:
    xor r8d,r8d
    cmp byte ptr [rdi],'-'
    jne .pi_pos
    mov r8d,1
    inc rdi
.pi_pos:
    push r8
    call parse_u64
    pop r8
    test edx,edx
    jnz .pi_bad
    test r8d,r8d
    jz .pi_positive_range
    mov rcx,0x8000000000000000
    cmp rax,rcx
    ja .pi_bad
    neg rax
    xor edx,edx
    ret
.pi_positive_range:
    mov rcx,0x7fffffffffffffff
    cmp rax,rcx
    ja .pi_bad
    xor edx,edx
    ret
.pi_bad: xor eax,eax; mov edx,1; ret

# Restricted but deterministic decimal parser: [+/-]digits[.digits].
# Returns IEEE f64 bits in rax. Exponent syntax is rejected rather than guessed.
parse_f64:
    push rbx
    push r12
    xor r12d,r12d
    cmp byte ptr [rdi],'-'
    jne .pf_plus
    mov r12d,1
    inc rdi
    jmp .pf_start
.pf_plus:
    cmp byte ptr [rdi],'+'
    jne .pf_start
    inc rdi
.pf_start:
    xor rax,rax                    # integer numerator digits
    mov rbx,1                     # denominator
    xor r8d,r8d                    # seen digit
    xor r9d,r9d                    # after dot
.pf_loop:
    movzx ecx,byte ptr [rdi]
    test cl,cl
    jz .pf_done
    cmp cl,'.'
    jne .pf_digit
    test r9d,r9d
    jnz .pf_bad
    mov r9d,1
    inc rdi
    jmp .pf_loop
.pf_digit:
    cmp cl,'0'; jb .pf_bad
    cmp cl,'9'; ja .pf_bad
    imul rax,rax,10
    sub ecx,'0'
    add rax,rcx
    test r9d,r9d
    jz .pf_next
    imul rbx,rbx,10
.pf_next:
    mov r8d,1
    inc rdi
    jmp .pf_loop
.pf_done:
    test r8d,r8d
    jz .pf_bad
    cvtsi2sd xmm0,rax
    cmp rbx,1
    je .pf_sign
    cvtsi2sd xmm1,rbx
    divsd xmm0,xmm1
.pf_sign:
    test r12d,r12d
    jz .pf_bits
    mov rax,0x8000000000000000
    movq xmm1,rax
    xorpd xmm0,xmm1
.pf_bits:
    movq rax,xmm0
    xor edx,edx
    pop r12
    pop rbx
    ret
.pf_bad:
    xor eax,eax
    mov edx,1
    pop r12
    pop rbx
    ret

cstrlen:
    xor eax,eax
.cs: cmp byte ptr [rdi+rax],0; je .cs_done; inc rax; jmp .cs
.cs_done: ret

# rax=index. Patch the two decimal index bytes in shared prefixes.
make_out_index:
    xor edx,edx
    mov ecx,10
    div rcx
    add al,'0'
    add dl,'0'
    mov byte ptr [rip+out_bits_prefix+3],al
    mov byte ptr [rip+out_bits_prefix+4],dl
    mov byte ptr [rip+out_string_prefix+3],al
    mov byte ptr [rip+out_string_prefix+4],dl
    ret

# rax bits
print_bits_line:
    push rbx
    mov rbx,rax
    lea rdi,[rip+out_bits_prefix+13]
    mov ecx,16
.pb_hex:
    mov rdx,rbx
    shr rdx,60
    and edx,15
    cmp edx,9
    jbe .pb_digit
    add edx,'a'-10
    jmp .pb_store
.pb_digit: add edx,'0'
.pb_store:
    mov byte ptr [rdi],dl
    inc rdi
    shl rbx,4
    dec ecx
    jnz .pb_hex
    mov eax,SYS_write
    mov edi,1
    lea rsi,[rip+out_bits_prefix]
    mov edx,out_bits_prefix_end-out_bits_prefix
    syscall
    pop rbx
    ret

# parse_rankn_fp(rdi=cstr, edx=encoded fpP) -> rax=object, edx=0/1.
# Decimal ingress is one exact integer recurrence D=10D+d followed by one
# normalization (and one division only when a decimal denominator exists).
# Five P-derived carriers are sufficient: raw numerator, normalized numerator,
# raw denominator, normalized denominator, and result. No per-digit fpP multiply,
# conversion, or precision-specific path participates.
parse_rankn_fp:
    push rbx; push rbp; push r12; push r13; push r14; push r15
    sub rsp,64
    mov r12,rdi                       # cursor
    mov r13d,edx                      # encoded type
    mov edi,r13d; call rpf_precision_from_type
    test eax,eax; jz .prf_bad
    mov ebp,eax                       # P
    lea eax,[eax+63]; shr eax,6       # N
    mov dword ptr [rsp+56],eax
    mov edi,r13d
    call rpf_object_span
    test rax,rax
    jz .prf_bad
    mov rdx,rax                       # one shared exact physical-span authority
    mov [rsp+48],rdx
    mov r15,qword ptr [rip+rankn_input_cursor]
    mov rax,rdx
    imul rax,rax,5
    jo .prf_bad
    mov rcx,r15
    add rcx,rax
    jc .prf_bad
    cmp rcx,qword ptr [rip+rankn_input_end_patch]
    ja .prf_bad
    mov qword ptr [rip+rankn_input_cursor],rcx
    # Five equal P-derived carriers.
    mov [rsp],r15                    # raw numerator base
    mov rax,r15; add rax,rdx; mov [rsp+8],rax   # normalized numerator
    add rax,rdx; mov [rsp+16],rax                 # raw denominator base
    add rax,rdx; mov [rsp+24],rax                 # normalized denominator
    add rax,rdx; mov r15,rax                      # final result
    # sign
    xor r14d,r14d
    cmp byte ptr [r12],'-'; jne .prf_plus
    mov r14d,1; inc r12; jmp .prf_sign_done
.prf_plus:
    cmp byte ptr [r12],'+'; jne .prf_sign_done
    inc r12
.prf_sign_done:
    # decimal significant-digit capacity floor(P*log10(2)); permit one
    # syntactic leading zero in canonical 0.xxx form.
    mov eax,ebp; imul rax,rax,30103; xor edx,edx; mov ecx,100000; div rcx
    mov dword ptr [rsp+32],eax
    cmp byte ptr [r12],'0'; jne .prf_cap_ready
    cmp byte ptr [r12+1],'.'; jne .prf_cap_ready
    inc dword ptr [rsp+32]
.prf_cap_ready:
    # Raw numerator=0 and denominator=1. Each is written once, then evolved by
    # the exact decimal recurrence without entering floating arithmetic.
    mov rdi,[rsp]; add rdi,RPF_DATA; mov ecx,[rsp+56]; call rpf_zero_limbs
    mov rdi,[rsp+16]; add rdi,RPF_DATA; mov ecx,[rsp+56]; call rpf_zero_limbs
    mov rax,[rsp+16]; mov qword ptr [rax+RPF_DATA],1
    mov dword ptr [rsp+36],0          # raw digit count
    xor ebp,ebp                       # fractional digit count
    mov dword ptr [rsp+40],0          # seen dot
    mov dword ptr [rsp+44],0          # seen digit
.prf_loop:
    movzx eax,byte ptr [r12]
    test al,al; jz .prf_finish
    cmp al,'.'; jne .prf_digit
    cmp dword ptr [rsp+40],0; jne .prf_bad
    mov dword ptr [rsp+40],1; inc r12; jmp .prf_loop
.prf_digit:
    cmp al,'0'; jb .prf_bad
    cmp al,'9'; ja .prf_bad
    inc dword ptr [rsp+44]; inc dword ptr [rsp+36]
    mov eax,[rsp+36]; cmp eax,[rsp+32]; ja .prf_bad
    cmp dword ptr [rsp+40],0; je .prf_no_frac
    inc ebp
.prf_no_frac:
    movzx edx,byte ptr [r12]; sub edx,'0'
    mov rdi,[rsp]; add rdi,RPF_DATA; mov ecx,[rsp+56]; call rpf_raw_mul10_add
    test eax,eax; jnz .prf_bad
    cmp dword ptr [rsp+40],0; je .prf_next
    mov rdi,[rsp+16]; add rdi,RPF_DATA; mov ecx,[rsp+56]; xor edx,edx; call rpf_raw_mul10_add
    test eax,eax; jnz .prf_bad
.prf_next:
    inc r12; jmp .prf_loop
.prf_finish:
    cmp dword ptr [rsp+44],0; je .prf_bad
    test ebp,ebp; jz .prf_integer
    # Normalize numerator once.
    mov rdi,[rsp+8]
    mov rsi,[rsp]; add rsi,RPF_DATA
    mov edx,[rsp+56]
    xor ecx,ecx
    xor r8d,r8d
    mov r9d,r13d
    call rpf_round_from_integer
    test eax,eax; jnz .prf_bad
    # Normalize denominator once, then perform the sole fractional division.
    mov rdi,[rsp+24]
    mov rsi,[rsp+16]; add rsi,RPF_DATA
    mov edx,[rsp+56]
    xor ecx,ecx
    xor r8d,r8d
    mov r9d,r13d
    call rpf_round_from_integer
    test eax,eax; jnz .prf_bad
    mov rdi,r15; mov rsi,[rsp+8]; mov rdx,[rsp+24]; mov ecx,r13d; call rankn_fp_div
    test eax,eax; jnz .prf_bad
    jmp .prf_sign
.prf_integer:
    # Integer input needs no intermediate normalized object.
    mov rdi,r15
    mov rsi,[rsp]; add rsi,RPF_DATA
    mov edx,[rsp+56]
    mov ecx,r14d
    xor r8d,r8d
    mov r9d,r13d
    call rpf_round_from_integer
    test eax,eax; jnz .prf_bad
    jmp .prf_ok
.prf_sign:
    test r14d,r14d; jz .prf_ok
    mov qword ptr [r15+RPF_SIGN],1
.prf_ok:
    mov rax,r15; xor edx,edx; jmp .prf_done
.prf_bad:
    xor eax,eax; mov edx,1
.prf_done:
    add rsp,64
    pop r15; pop r14; pop r13; pop r12; pop rbp; pop rbx
    ret

# rax=value, ecx=hex digits, r14=buffer,r15d=cursor
prf_hex_fixed:
    push rbx
    lea rbx,[rip+hex_digits]
    mov r10d,ecx; shl r10d,2; sub r10d,4
.prfh_loop:
    mov rcx,r10; mov r11,rax; shr r11,cl; and r11d,15
    mov dl,[rbx+r11]; mov [r14+r15],dl; inc r15d
    sub r10d,4; jns .prfh_loop
    pop rbx; ret

# Exact canonical stream for arbitrary P.  No fixed-width name or fixed limb
# count appears in the protocol. Header: outNN_rankn_fp=0xPPPPPPPPPPPPPPPP:S:E:N:
# followed by N high-to-low 16-hex-digit limbs.
print_rankn_fp_line:
    push rbx; push rbp; push r12; push r13; push r14; push r15
    mov r12,rdi; mov r13d,esi
    lea r14,[rip+rankn_fp_line_buf]
    mov byte ptr [r14+0],'o'; mov byte ptr [r14+1],'u'; mov byte ptr [r14+2],'t'
    mov eax,r13d; xor edx,edx; mov ecx,10; div ecx
    add al,'0'; add dl,'0'; mov [r14+3],al; mov [r14+4],dl
    lea rsi,[rip+rankn_fp_label]; mov ecx,rankn_fp_label_end-rankn_fp_label
    lea rdi,[r14+5]; rep movsb
    mov r15d,5+(rankn_fp_label_end-rankn_fp_label)
    mov rax,[r12+RPF_PREC]; mov ecx,16; call prf_hex_fixed
    mov byte ptr [r14+r15],':'; inc r15d
    mov rax,[r12+RPF_SIGN]; mov ecx,1; call prf_hex_fixed
    mov byte ptr [r14+r15],':'; inc r15d
    mov rax,[r12+RPF_EXP]; mov ecx,16; call prf_hex_fixed
    mov byte ptr [r14+r15],':'; inc r15d
    mov rbp,[r12+RPF_PREC]; add rbp,63; shr rbp,6
    mov rax,rbp; mov ecx,16; call prf_hex_fixed
    mov byte ptr [r14+r15],':'; inc r15d
    mov eax,SYS_write; mov edi,1; mov rsi,r14; mov edx,r15d; syscall
.prfpl_limb:
    test ebp,ebp; jz .prfpl_nl
    dec ebp
    lea r14,[rip+rankn_fp_line_buf]; xor r15d,r15d
    mov rax,[r12+RPF_DATA+rbp*8]; mov ecx,16; call prf_hex_fixed
    mov eax,SYS_write; mov edi,1; lea rsi,[rip+rankn_fp_line_buf]; mov edx,16; syscall
    jmp .prfpl_limb
.prfpl_nl:
    mov eax,SYS_write; mov edi,1; lea rsi,[rip+newline]; mov edx,1; syscall
    pop r15; pop r14; pop r13; pop r12; pop rbp; pop rbx; ret


# Generic wrap-u64 Rank-N affine transition power.
# rdi=scratch, rsi=N, rdx=exponent, rcx=result lane -> rax=result.
# Scratch layout is derived only from N:
#   x[N] | A[N*N] | b[N] | tmp_x[N] | tmp_A[N*N] | tmp_b[N]
# The relation is x' = A*x + b mod 2^64.  One physical kernel covers every
# admitted dimension; there is no state-count dispatch or runtime selector.
.global rankn_affine_power_u64
rankn_affine_power_u64:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp,32
    mov r13,rdi                       # x
    mov rbx,rsi                       # N
    mov r12,rdx                       # remaining exponent
    mov [rsp+24],rcx                  # published dense lane
    lea r14,[r13+rbx*8]               # A
    mov rax,rbx
    imul rax,rbx                      # N*N
    lea r15,[r14+rax*8]               # b
    lea r8,[r15+rbx*8]                # tmp_x
    lea r9,[r8+rbx*8]                 # tmp_A
    lea r10,[r9+rax*8]                # tmp_b
    mov [rsp],r8
    mov [rsp+8],r9
    mov [rsp+16],r10

.rap_loop:
    test r12,r12
    jz .rap_return
    test r12,1
    jz .rap_after_apply

    # x <- A*x+b.  tmp_x prevents overwrite hazards for simultaneous state.
    xor r8d,r8d
.rap_apply_i:
    cmp r8,rbx
    jae .rap_apply_copy
    mov r10,[r15+r8*8]
    mov rax,r8
    imul rax,rbx
    lea rbp,[r14+rax*8]
    xor r11d,r11d
.rap_apply_j:
    cmp r11,rbx
    jae .rap_apply_store
    mov rax,[rbp+r11*8]
    imul rax,qword ptr [r13+r11*8]
    add r10,rax
    inc r11
    jmp .rap_apply_j
.rap_apply_store:
    mov rax,[rsp]
    mov [rax+r8*8],r10
    inc r8
    jmp .rap_apply_i
.rap_apply_copy:
    xor r8d,r8d
    mov r9,[rsp]
.rap_apply_copy_loop:
    cmp r8,rbx
    jae .rap_after_apply
    mov rax,[r9+r8*8]
    mov [r13+r8*8],rax
    inc r8
    jmp .rap_apply_copy_loop

.rap_after_apply:
    shr r12,1
    jz .rap_return

    # (A,b)^2 = (A*A, A*b+b).  Both products are formed from the old
    # transform before either destination becomes authoritative.
    xor r8d,r8d
.rap_square_i:
    cmp r8,rbx
    jae .rap_square_copy
    mov rax,r8
    imul rax,rbx
    lea rbp,[r14+rax*8]               # old A row i

    mov r10,[r15+r8*8]                # tmp_b[i] starts with b[i]
    xor r11d,r11d
.rap_square_b_k:
    cmp r11,rbx
    jae .rap_square_b_store
    mov rax,[rbp+r11*8]
    imul rax,qword ptr [r15+r11*8]
    add r10,rax
    inc r11
    jmp .rap_square_b_k
.rap_square_b_store:
    mov rax,[rsp+16]
    mov [rax+r8*8],r10

    xor ecx,ecx                       # j
.rap_square_j:
    cmp rcx,rbx
    jae .rap_square_next_i
    xor r10d,r10d                     # sum
    xor r11d,r11d                     # k
.rap_square_k:
    cmp r11,rbx
    jae .rap_square_store
    mov rax,r11
    imul rax,rbx
    add rax,rcx
    mov rax,[r14+rax*8]               # A[k,j]
    imul rax,qword ptr [rbp+r11*8]    # A[i,k] * A[k,j]
    add r10,rax
    inc r11
    jmp .rap_square_k
.rap_square_store:
    mov rax,r8
    imul rax,rbx
    add rax,rcx
    mov rdx,[rsp+8]
    mov [rdx+rax*8],r10
    inc rcx
    jmp .rap_square_j
.rap_square_next_i:
    inc r8
    jmp .rap_square_i

.rap_square_copy:
    mov rax,rbx
    imul rax,rbx
    xor ecx,ecx
    mov rdx,[rsp+8]
.rap_square_copy_a:
    cmp rcx,rax
    jae .rap_square_copy_b_begin
    mov r8,[rdx+rcx*8]
    mov [r14+rcx*8],r8
    inc rcx
    jmp .rap_square_copy_a
.rap_square_copy_b_begin:
    xor ecx,ecx
    mov rdx,[rsp+16]
.rap_square_copy_b:
    cmp rcx,rbx
    jae .rap_loop
    mov r8,[rdx+rcx*8]
    mov [r15+rcx*8],r8
    inc rcx
    jmp .rap_square_copy_b

.rap_return:
    mov rcx,[rsp+24]
    mov rax,[r13+rcx*8]
    add rsp,32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

.section .rodata
self_exe_path: .asciz "/proc/self/exe"

.section .data
.p2align 6
.global input_count_patch
input_count_patch: .long 0
.global output_count_patch
output_count_patch: .long 0
.p2align 3
.global dynamic_arena_bytes_patch
dynamic_arena_bytes_patch: .quad 0
.global program_trailer_file_offset_patch
program_trailer_file_offset_patch: .quad 0
.global program_trailer_size_patch
program_trailer_size_patch: .quad 0
.global program_code_rel_offset_patch
program_code_rel_offset_patch: .quad 0
program_code_ptr: .quad 0
input_type_ptr: .quad 0
output_type_ptr: .quad 0
rankn_physical_fact_ptr: .quad 0
.global rankn_type_count_patch
rankn_type_count_patch: .long 0
.p2align 3
.global input_values_base_patch
input_values_base_patch: .quad 0
.global input_aux_base_patch
input_aux_base_patch: .quad 0
.global rankn_input_base_patch
rankn_input_base_patch: .quad 0
.global rankn_input_end_patch
rankn_input_end_patch: .quad 0
rankn_input_cursor: .quad 0
.global output_pages_base_patch
output_pages_base_patch: .quad 0
.global output_aux_base_patch
output_aux_base_patch: .quad 0
out_bits_prefix: .ascii "out00_bits=0x0000000000000000\n"
out_bits_prefix_end:
out_string_prefix: .ascii "out00_string="
out_string_prefix_end:
newline: .byte 10
hex_digits: .ascii "0123456789abcdef"
rankn_fp_label: .ascii "_rankn_fp=0x"
rankn_fp_label_end:
rankn_fp_line_buf: .fill 128,1,0

.section .bss
.p2align 6
runtime_bss_sentinel: .skip 64
