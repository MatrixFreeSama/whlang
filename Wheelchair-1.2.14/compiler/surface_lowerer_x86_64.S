.intel_syntax noprefix

# Native WH/WHEX human-surface lowerer.
# Compile-time only: text -> canonical wheelchair.tensor/1 bytes in memory.
# It owns no runtime scheduling policy and never assigns a resource recipient.

.equ SBUF_INPUTS_CAP,262144
.equ SBUF_BINDINGS_CAP,4194304
.equ SBUF_OUTPUTS_CAP,262144
.equ SBUF_TESTS_CAP,262144
.equ SBUF_FINAL_CAP,6291456
.equ SAST_MAX,8192
.equ SAST_SIZE,64
.equ SCOPE_MAX,32
.equ RANK_MAX,16
.equ DECL_MAX,256
.equ DICT_MAX,16
.equ DICT_ENTRY_MAX,128
.equ NESTED_MAX,32
.equ CASCADE_GOAL_MAX,32

.equ SN_KIND,0
.equ SN_OP,4
.equ SN_PTR,8
.equ SN_LEN,16
.equ SN_A,24
.equ SN_B,32
.equ SN_C,40
.equ SN_NEXT,48
.equ SN_AUX,56

.equ NK_NUM,1
.equ NK_STRING,2
.equ NK_BOOL,3
.equ NK_VAR,4
.equ NK_AXIS,5
.equ NK_STATE,6
.equ NK_UNARY,7
.equ NK_BINARY,8
.equ NK_CAST,9
.equ NK_LOAD,10
.equ NK_IMM_U64,11
.equ NK_GOAL_RESULT,12

.equ OP_OR,1
.equ OP_AND,2
.equ OP_BIT_OR,3
.equ OP_BIT_XOR,4
.equ OP_BIT_AND,5
.equ OP_EQ,6
.equ OP_NE,7
.equ OP_LT,8
.equ OP_LE,9
.equ OP_GT,10
.equ OP_GE,11
.equ OP_SHL,12
.equ OP_SHR,13
.equ OP_ADD,14
.equ OP_SUB,15
.equ OP_MUL,16
.equ OP_DIV,17
.equ OP_MOD,18
.equ OP_NOT,19
.equ OP_BIT_NOT,20
.equ OP_NEG,21
.equ OP_SELECT,22
.equ OP_MIN,23
.equ OP_MAX,24
.equ OP_ABS,25
.equ OP_USHR,26
.equ KID_PROGRAM,1
.equ KID_CONTRACT,2
.equ KID_INPUT,3
.equ KID_RANGE,4
.equ KID_LET,5
.equ KID_TENSOR,6
.equ KID_REDUCE,7
.equ KID_SUM,8
.equ KID_ITERATE,9
.equ KID_LIMIT,10
.equ KID_STATE,11
.equ KID_WHILE,12
.equ KID_UPDATE,13
.equ KID_RESULT,14
.equ KID_RECORD,15
.equ KID_AXIS,16
.equ KID_PURE,17
.equ KID_GENERIC,18
.equ KID_FN,19
.equ KID_REGION,20
.equ KID_EFFECT,21
.equ KID_PARALLEL,22
.equ KID_FOR,23
.equ KID_IF,24
.equ KID_ELSE,25
.equ KID_TOLERANCE,26
.equ KID_STRICT,27
.equ KID_FIELD,28
.equ KID_IN,29
.equ KID_OUTPUT,30
.equ KID_PUBLISH,31
.equ KID_TEST,32
.equ KID_TRUE,33
.equ KID_FALSE,34
.equ KID_CAST,35
.equ KID_SELECT,36
.equ KID_MIN,37
.equ KID_MAX,38
.equ KID_ABS,39
.equ KID_PERIODIC,40
.equ KID_DICTIONARY,41
.equ KID_LOOKUP,42
.equ KID_DEFAULT,43
.equ KID_NESTED,44
.equ KID_NESTED_REDUCE,45
.equ KID_CASCADE,46
.equ KID_EXECUTORS,47
.equ KID_CHUNK,48
.equ KID_EVENTS,49
.equ KID_GOAL,50
.equ KID_WORK,51
.equ KID_RELATION,52
.equ KID_TO,53
.equ KID_GOAL_RESULT,54
.equ KID_EACH,55

.extern source_ptr
.extern source_length

.global surface_lower_to_json
.global surface_json_buffer
.global surface_json_length

# -----------------------------------------------------------------------------
# Output primitives
# -----------------------------------------------------------------------------
s_out_byte:
    # dil=byte
    mov rax,[rip+s_out_ptr]
    cmp rax,[rip+s_out_limit]
    jae .sob_fail
    mov [rax],dil
    inc rax
    mov [rip+s_out_ptr],rax
    xor eax,eax
    ret
.sob_fail:
    mov dword ptr [rip+s_error],1
    mov eax,1
    ret

s_out_span:
    # rdi=ptr, rsi=len
    mov rax,[rip+s_out_ptr]
    mov rcx,rax
    add rcx,rsi
    cmp rcx,[rip+s_out_limit]
    ja .sos_fail
    mov rdx,rdi
    mov rdi,rax
    mov rcx,rsi
    mov rsi,rdx
    rep movsb
    mov [rip+s_out_ptr],rdi
    xor eax,eax
    ret
.sos_fail:
    mov dword ptr [rip+s_error],1
    mov eax,1
    ret

s_out_cstr:
    # rdi=zero-terminated ASCII constant
    push rdi
    xor esi,esi
.soc_len:
    cmp byte ptr [rdi+rsi],0
    je .soc_go
    inc rsi
    jmp .soc_len
.soc_go:
    pop rdi
    jmp s_out_span

s_out_quote_span:
    # rdi=identifier/content ptr, rsi=len. Human identifiers may not contain quote/backslash.
    push rbx
    push r12
    mov rbx,rdi
    mov r12,rsi
    mov dil,'"'; call s_out_byte
    test eax,eax; jnz .soqs_fail
    xor rcx,rcx
.soqs_scan:
    cmp rcx,r12
    jae .soqs_body
    mov al,[rbx+rcx]
    cmp al,'"'; je .soqs_fail
    cmp al,'\\'; je .soqs_fail
    cmp al,0; je .soqs_fail
    inc rcx
    jmp .soqs_scan
.soqs_body:
    mov rdi,rbx; mov rsi,r12; call s_out_span
    test eax,eax; jnz .soqs_fail
    mov dil,'"'; call s_out_byte
    jmp .soqs_done
.soqs_fail:
    mov dword ptr [rip+s_error],1
    mov eax,1
.soqs_done:
    pop r12
    pop rbx
    ret

# -----------------------------------------------------------------------------
# Source cursor primitives
# -----------------------------------------------------------------------------
s_skip:
    mov rax,[rip+s_cur]
    mov rdx,[rip+s_end]
.ss_loop:
    cmp rax,rdx
    jae .ss_done
    mov cl,[rax]
    cmp cl,' '; je .ss_one
    cmp cl,9; je .ss_one
    cmp cl,10; je .ss_one
    cmp cl,13; je .ss_one
    cmp cl,'#'; je .ss_hash
    cmp cl,'/'; jne .ss_done
    lea rcx,[rax+1]
    cmp rcx,rdx; jae .ss_done
    mov cl,[rax+1]
    cmp cl,'/'; je .ss_slash
    cmp cl,'*'; je .ss_block
    jmp .ss_done
.ss_one:
    inc rax
    jmp .ss_loop
.ss_hash:
    inc rax
.ss_hash_loop:
    cmp rax,rdx; jae .ss_done
    cmp byte ptr [rax],10; je .ss_one
    inc rax; jmp .ss_hash_loop
.ss_slash:
    add rax,2
.ss_slash_loop:
    cmp rax,rdx; jae .ss_done
    cmp byte ptr [rax],10; je .ss_one
    inc rax; jmp .ss_slash_loop
.ss_block:
    add rax,2
.ss_block_loop:
    lea rcx,[rax+1]
    cmp rcx,rdx; jae .ss_bad
    cmp byte ptr [rax],'*'; jne .ss_block_next
    cmp byte ptr [rax+1],'/'; je .ss_block_close
.ss_block_next:
    inc rax; jmp .ss_block_loop
.ss_block_close:
    add rax,2
    jmp .ss_loop
.ss_bad:
    mov dword ptr [rip+s_error],1
.ss_done:
    mov [rip+s_cur],rax
    ret

s_is_ident_byte:
    # dil -> eax bool (ASCII letters/digits/_ or UTF-8 non-ASCII byte)
    movzx eax,dil
    cmp al,0x80; jae .siib_yes
    cmp al,'A'; jb .siib_low
    cmp al,'Z'; jbe .siib_yes
.siib_low:
    cmp al,'a'; jb .siib_digit
    cmp al,'z'; jbe .siib_yes
.siib_digit:
    cmp al,'0'; jb .siib_us
    cmp al,'9'; jbe .siib_yes
.siib_us:
    cmp al,'_'; je .siib_yes
    xor eax,eax; ret
.siib_yes:
    mov eax,1; ret

s_match_token:
    # rdi=literal ptr, esi=len, edx=boundary(1 keyword /0 operator). eax=1 consumed /0
    push rbx
    push r12
    push r13
    mov rbx,rdi; mov r12d,esi; mov r13d,edx
    call s_skip
    mov r8,[rip+s_cur]
    mov r9,r8
    add r9,r12
    cmp r9,[rip+s_end]
    ja .smt_no
    xor ecx,ecx
.smt_cmp:
    cmp ecx,r12d; jae .smt_boundary
    mov al,[r8+rcx]
    cmp al,[rbx+rcx]; jne .smt_no
    inc ecx; jmp .smt_cmp
.smt_boundary:
    test r13d,r13d; jz .smt_yes
    cmp r9,[rip+s_end]; jae .smt_yes
    mov dil,[r9]; call s_is_ident_byte
    test eax,eax; jnz .smt_no
.smt_yes:
    mov [rip+s_cur],r9
    mov eax,1
    jmp .smt_done
.smt_no:
    xor eax,eax
.smt_done:
    pop r13; pop r12; pop rbx; ret

s_expect_token:
    call s_match_token
    test eax,eax; jnz .set_ok
    mov dword ptr [rip+s_error],1
.set_ok:
    ret

s_match_kw_id:
    push rbx; push r12; push r13; push r14
    mov ebx,edi
    lea r12,[rip+s_kw_alias_table]
.smki_loop:
    mov rax,[r12]; test rax,rax; jz .smki_split
    cmp dword ptr [r12+12],ebx; jne .smki_next
    mov rdi,rax; mov esi,dword ptr [r12+8]; mov edx,1; call s_match_token
    test eax,eax; jnz .smki_yes
.smki_next: add r12,16; jmp .smki_loop
.smki_split:
    mov edi,ebx; call s_match_kw_split_id
    test eax,eax; jnz .smki_yes
    mov r14,[rip+s_cur]
    mov r13d,[rip+s_error]
    call s_parse_name
    test edx,edx; jnz .smki_restore
    mov rdi,rax; mov rsi,rcx; call s_keyword_edit_repair
    cmp eax,ebx; je .smki_yes
.smki_restore:
    mov [rip+s_cur],r14
    mov [rip+s_error],r13d
    xor eax,eax; jmp .smki_done
.smki_yes: mov eax,1
.smki_done: pop r14; pop r13; pop r12; pop rbx; ret

s_expect_kw_id:
    call s_match_kw_id
    test eax,eax; jnz .seki_ok
    mov dword ptr [rip+s_error],1
.seki_ok: ret

s_span_kw_id:
    push rbx; push r12; push r13; push r14
    mov rbx,rdi; mov r12,rsi; mov r13d,edx
    lea r14,[rip+s_kw_alias_table]
.sski_loop:
    mov rax,[r14]; test rax,rax; jz .sski_repair
    cmp dword ptr [r14+12],r13d; jne .sski_next
    mov rdi,rbx; mov rsi,r12; mov rdx,rax; mov ecx,dword ptr [r14+8]; call s_span_eq
    test eax,eax; jnz .sski_yes
.sski_next: add r14,16; jmp .sski_loop
.sski_repair:
    mov rdi,rbx; mov rsi,r12; call s_keyword_edit_repair
    cmp eax,r13d; sete al; movzx eax,al; jmp .sski_done
.sski_yes: mov eax,1
.sski_done: pop r14; pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Conservative English-only surface repair.
# These helpers never rewrite source bytes. They redirect a token only when the
# repair is unique. Chinese/mixed/emoji identifiers are exact-only.
# -----------------------------------------------------------------------------
s_span_ascii:
    xor ecx,ecx
.ssa_loop:
    cmp rcx,rsi; jae .ssa_yes
    cmp byte ptr [rdi+rcx],0x80; jae .ssa_no
    inc rcx; jmp .ssa_loop
.ssa_yes: mov eax,1; ret
.ssa_no: xor eax,eax; ret

s_edit1_ascii:
    # rdi=a,rsi=alen,rdx=b,rcx=blen -> eax exactly one insertion/deletion/substitution.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi; mov r13,rdx; mov r14,rcx
    mov rdi,rbx; mov rsi,r12; call s_span_ascii; test eax,eax; jz .se1_no
    mov rdi,r13; mov rsi,r14; call s_span_ascii; test eax,eax; jz .se1_no
    mov rax,r12; sub rax,r14
    cmp rax,1; je .se1_del_a
    cmp rax,-1; je .se1_del_b
    test rax,rax; jne .se1_no
    xor r15d,r15d; xor ecx,ecx
.se1_sub_loop:
    cmp rcx,r12; jae .se1_sub_done
    mov al,[rbx+rcx]; cmp al,[r13+rcx]; je .se1_sub_next
    inc r15d; cmp r15d,1; ja .se1_no
.se1_sub_next: inc rcx; jmp .se1_sub_loop
.se1_sub_done: cmp r15d,1; sete al; movzx eax,al; jmp .se1_done
.se1_del_a:
    xor ecx,ecx; xor r15d,r15d; xor r8d,r8d
.se1_da_loop:
    cmp r8,r14; jae .se1_da_tail
    mov al,[rbx+rcx]; cmp al,[r13+r8]; je .se1_da_eq
    inc r15d; cmp r15d,1; ja .se1_no
    inc rcx; jmp .se1_da_loop
.se1_da_eq: inc rcx; inc r8; jmp .se1_da_loop
.se1_da_tail:
    mov rax,r12; sub rax,rcx; add r15d,eax
    cmp r15d,1; sete al; movzx eax,al; jmp .se1_done
.se1_del_b:
    xor ecx,ecx; xor r15d,r15d; xor r8d,r8d
.se1_db_loop:
    cmp rcx,r12; jae .se1_db_tail
    mov al,[rbx+rcx]; cmp al,[r13+r8]; je .se1_db_eq
    inc r15d; cmp r15d,1; ja .se1_no
    inc r8; jmp .se1_db_loop
.se1_db_eq: inc rcx; inc r8; jmp .se1_db_loop
.se1_db_tail:
    mov rax,r14; sub rax,r8; add r15d,eax
    cmp r15d,1; sete al; movzx eax,al; jmp .se1_done
.se1_no: xor eax,eax
.se1_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_decl_add:
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.sda_scan:
    cmp r13d,dword ptr [rip+s_decl_count]; jae .sda_new
    lea rax,[rip+s_decl_ptrs]; mov rdi,[rax+r13*8]
    lea rax,[rip+s_decl_lens]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .sda_ok
    inc r13d; jmp .sda_scan
.sda_new:
    cmp r13d,DECL_MAX; jae .sda_fail
    lea rax,[rip+s_decl_ptrs]; mov [rax+r13*8],rbx
    lea rax,[rip+s_decl_lens]; mov [rax+r13*8],r12
    inc dword ptr [rip+s_decl_count]
.sda_ok: xor eax,eax; jmp .sda_done
.sda_fail: mov dword ptr [rip+s_error],1; mov eax,1
.sda_done: pop r13; pop r12; pop rbx; ret

s_try_decl_repair:
    # rdi=parsed ptr,rsi=len; current cursor is immediately after first token.
    # Returns rax=canonical ptr,rcx=len; edx=1 only when repaired.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi
    xor r13d,r13d
.stdr_exact:
    cmp r13d,dword ptr [rip+s_decl_count]; jae .stdr_split
    lea rax,[rip+s_decl_ptrs]; mov rdi,[rax+r13*8]
    lea rax,[rip+s_decl_lens]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .stdr_exact_yes
    inc r13d; jmp .stdr_exact
.stdr_exact_yes:
    lea rax,[rip+s_decl_ptrs]; mov rax,[rax+r13*8]
    lea rcx,[rip+s_decl_lens]; mov rcx,[rcx+r13*8]
    xor edx,edx; jmp .stdr_done

.stdr_split:
    mov r14,[rip+s_cur]; mov r15,r14
    cmp r15,[rip+s_end]; jae .stdr_edit
    cmp byte ptr [r15],13; jne .stdr_split_lf
    inc r15; cmp r15,[rip+s_end]; jae .stdr_edit
    cmp byte ptr [r15],10; jne .stdr_edit
    inc r15; jmp .stdr_split_scan
.stdr_split_lf:
    cmp byte ptr [r15],10; jne .stdr_edit
    inc r15
.stdr_split_scan:
    mov r8,r15
.stdr_split_tail:
    cmp r8,[rip+s_end]; jae .stdr_split_have
    mov dil,[r8]; call s_is_ident_byte; test eax,eax; jz .stdr_split_have
    inc r8; jmp .stdr_split_tail
.stdr_split_have:
    cmp r8,r15; je .stdr_edit
    mov r9,r8; sub r9,r15
    mov [rip+s_repair_split_end],r8
    mov [rip+s_repair_split_len],r9
    xor r13d,r13d; mov r10d,-1; xor r11d,r11d
.stdr_split_candidates:
    cmp r13d,dword ptr [rip+s_decl_count]; jae .stdr_split_decide
    lea rax,[rip+s_decl_lens]; mov rcx,[rax+r13*8]
    mov rax,r12; add rax,[rip+s_repair_split_len]; cmp rcx,rax; jne .stdr_split_next
    lea rax,[rip+s_decl_ptrs]; mov rdx,[rax+r13*8]
    mov rdi,rbx; mov rsi,r12; mov rcx,r12; call s_span_eq; test eax,eax; jz .stdr_split_next
    lea rax,[rip+s_decl_ptrs]; mov rdx,[rax+r13*8]; add rdx,r12
    mov rdi,r15; mov rsi,[rip+s_repair_split_len]; mov rcx,rsi; call s_span_eq; test eax,eax; jz .stdr_split_next
    mov r10d,r13d; inc r11d
.stdr_split_next: inc r13d; jmp .stdr_split_candidates
.stdr_split_decide:
    cmp r11d,1; jne .stdr_edit
    mov rax,[rip+s_repair_split_end]; mov [rip+s_cur],rax
    lea rax,[rip+s_decl_ptrs]; mov rax,[rax+r10*8]
    lea rcx,[rip+s_decl_lens]; mov rcx,[rcx+r10*8]
    mov edx,1; jmp .stdr_done

.stdr_edit:
    mov rdi,rbx; mov rsi,r12; call s_span_ascii; test eax,eax; jz .stdr_orig
    xor r13d,r13d; mov r14d,-1; xor r15d,r15d
.stdr_edit_loop:
    cmp r13d,dword ptr [rip+s_decl_count]; jae .stdr_edit_decide
    lea rax,[rip+s_decl_ptrs]; mov rdx,[rax+r13*8]
    lea rax,[rip+s_decl_lens]; mov rcx,[rax+r13*8]
    mov rdi,rbx; mov rsi,r12; call s_edit1_ascii
    test eax,eax; jz .stdr_edit_next
    mov r14d,r13d; inc r15d
.stdr_edit_next: inc r13d; jmp .stdr_edit_loop
.stdr_edit_decide:
    cmp r15d,1; je .stdr_repaired
    cmp r15d,1; jbe .stdr_orig
    mov dword ptr [rip+s_error],1
    jmp .stdr_orig
.stdr_repaired:
    lea rax,[rip+s_decl_ptrs]; mov rax,[rax+r14*8]
    lea rcx,[rip+s_decl_lens]; mov rcx,[rcx+r14*8]
    mov edx,1; jmp .stdr_done
.stdr_orig: mov rax,rbx; mov rcx,r12; xor edx,edx
.stdr_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_keyword_edit_repair:
    # rdi=token ptr,rsi=len -> eax unique KID or 0. English aliases only.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi
    mov rdi,rbx; mov rsi,r12; call s_span_ascii; test eax,eax; jz .sker_no
    lea r13,[rip+s_kw_alias_table]; xor r14d,r14d; xor r15d,r15d
.sker_loop:
    mov rax,[r13]; test rax,rax; jz .sker_decide
    mov rdi,rax; mov esi,dword ptr [r13+8]; call s_span_ascii; test eax,eax; jz .sker_next
    mov rdi,rbx; mov rsi,r12; mov rdx,[r13]; mov ecx,dword ptr [r13+8]; call s_edit1_ascii
    test eax,eax; jz .sker_next
    mov r14d,dword ptr [r13+12]; inc r15d
.sker_next: add r13,16; jmp .sker_loop
.sker_decide:
    cmp r15d,1; jne .sker_no
    mov eax,r14d; jmp .sker_done
.sker_no: xor eax,eax
.sker_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_match_kw_split_id:
    # edi=KID -> eax=1 if an ASCII canonical alias is split by exactly one CR/LF.
    push rbx; push r12; push r13; push r14; push r15
    mov ebx,edi; call s_skip; mov r12,[rip+s_cur]
    lea r13,[rip+s_kw_alias_table]
.smksi_alias:
    mov rax,[r13]; test rax,rax; jz .smksi_no
    cmp dword ptr [r13+12],ebx; jne .smksi_next
    mov rdi,rax; mov esi,dword ptr [r13+8]; call s_span_ascii; test eax,eax; jz .smksi_next
    mov r14,[r13]; mov r15d,dword ptr [r13+8]
    xor ecx,ecx; mov r8,r12; xor r9d,r9d
.smksi_cmp:
    cmp ecx,r15d; jae .smksi_end
    cmp r8,[rip+s_end]; jae .smksi_next
    mov al,[r8]
    cmp al,13; je .smksi_cr
    cmp al,10; je .smksi_lf
    cmp al,[r14+rcx]; jne .smksi_next
    inc r8; inc ecx; jmp .smksi_cmp
.smksi_cr:
    test r9d,r9d; jnz .smksi_next
    inc r8; cmp r8,[rip+s_end]; jae .smksi_next
    cmp byte ptr [r8],10; jne .smksi_next
    inc r8; mov r9d,1; jmp .smksi_cmp
.smksi_lf:
    test r9d,r9d; jnz .smksi_next
    inc r8; mov r9d,1; jmp .smksi_cmp
.smksi_end:
    test r9d,r9d; jz .smksi_next
    cmp r8,[rip+s_end]; jae .smksi_yes
    mov dil,[r8]; call s_is_ident_byte; test eax,eax; jnz .smksi_next
.smksi_yes: mov [rip+s_cur],r8; mov eax,1; jmp .smksi_done
.smksi_next: add r13,16; jmp .smksi_alias
.smksi_no: xor eax,eax
.smksi_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret


s_builtin_repair:
    # rdi=ASCII callable typo,rsi=len -> eax=OP_*, edx=arity, or eax=0.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi
    mov rdi,rbx; mov rsi,r12; call s_span_ascii; test eax,eax; jz .sbr_no
    lea r13,[rip+s_builtin_repair_table]; xor r14d,r14d; xor r15d,r15d
    xor r9d,r9d
.sbr_loop:
    mov rax,[r13]; test rax,rax; jz .sbr_decide
    mov rdi,rbx; mov rsi,r12; mov rdx,rax; mov ecx,dword ptr [r13+8]; call s_edit1_ascii
    test eax,eax; jz .sbr_next
    mov r14d,dword ptr [r13+12]
    mov r9d,dword ptr [r13+16]
    inc r15d
.sbr_next: add r13,24; jmp .sbr_loop
.sbr_decide:
    cmp r15d,1; jne .sbr_no
    mov eax,r14d; mov edx,r9d; jmp .sbr_done
.sbr_no: xor eax,eax; xor edx,edx
.sbr_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_parse_name:
    # rax=ptr, rcx=len, edx=0 success. Numeric-leading UTF-8 names and quoted
    # identifiers are first-class; no Python normalization layer is required.
    call s_skip
    mov r8,[rip+s_cur]
    cmp r8,[rip+s_end]; jae .spn_fail
    mov al,[r8]
    cmp al,'`'; je .spn_quoted
    # A run of ASCII digits is a legal numeric identifier. If it is followed by
    # another identifier byte (e.g. 123🔥输入), continue as one UTF-8 name.
    cmp al,'0'; jb .spn_ident
    cmp al,'9'; ja .spn_ident
    mov r9,r8
.spn_numloop:
    cmp r9,[rip+s_end]; jae .spn_done
    mov al,[r9]; cmp al,'0'; jb .spn_num_tail; cmp al,'9'; ja .spn_num_tail
    inc r9; jmp .spn_numloop
.spn_num_tail:
    mov dil,[r9]; call s_is_ident_byte
    test eax,eax; jnz .spn_loop
    jmp .spn_done
.spn_ident:
    mov dil,[r8]; call s_is_ident_byte
    test eax,eax; jz .spn_fail
    mov r9,r8
.spn_loop:
    cmp r9,[rip+s_end]; jae .spn_done
    mov dil,[r9]; call s_is_ident_byte
    test eax,eax; jz .spn_done
    inc r9; jmp .spn_loop
.spn_quoted:
    lea r9,[r8+1]
    mov r10,r9
.spn_qloop:
    cmp r10,[rip+s_end]; jae .spn_fail
    mov al,[r10]
    cmp al,'`'; je .spn_qdone
    cmp al,10; je .spn_fail
    cmp al,13; je .spn_fail
    cmp al,'\\'; je .spn_fail       # escaping is rejected rather than guessed
    inc r10; jmp .spn_qloop
.spn_qdone:
    lea r11,[r10+1]
    mov [rip+s_cur],r11
    mov rax,r9
    mov rcx,r10; sub rcx,r9
    xor edx,edx
    ret
.spn_done:
    mov [rip+s_cur],r9
    mov rax,r8
    mov rcx,r9
    sub rcx,r8
    xor edx,edx
    ret
.spn_fail:
    xor eax,eax; xor ecx,ecx; mov edx,1
    mov dword ptr [rip+s_error],1
    ret

s_parse_number_span:
    # unsigned number token, including 0x/0b/decimal/fraction/exponent. rax ptr rcx len edx err
    call s_skip
    mov r8,[rip+s_cur]
    mov r9,r8
    cmp r9,[rip+s_end]; jae .spns_fail
    cmp byte ptr [r9],'0'; jne .spns_dec
    lea r10,[r9+2]; cmp r10,[rip+s_end]; ja .spns_dec
    mov al,[r9+1]
    cmp al,'x'; je .spns_hex
    cmp al,'X'; je .spns_hex
    cmp al,'b'; je .spns_bin
    cmp al,'B'; je .spns_bin
.spns_dec:
    xor r10d,r10d
.spns_digs:
    cmp r9,[rip+s_end]; jae .spns_frac
    mov al,[r9]; cmp al,'0'; jb .spns_frac; cmp al,'9'; ja .spns_frac
    inc r9; inc r10d; jmp .spns_digs
.spns_frac:
    test r10d,r10d; jz .spns_fail
    cmp r9,[rip+s_end]; jae .spns_done
    cmp byte ptr [r9],'.'; jne .spns_exp
    # '..' is a range operator, not a decimal point.
    lea r10,[r9+1]; cmp r10,[rip+s_end]; jae .spns_done
    cmp byte ptr [r9+1],'.'; je .spns_done
    inc r9
    xor r10d,r10d
.spns_fdigs:
    cmp r9,[rip+s_end]; jae .spns_done
    mov al,[r9]; cmp al,'0'; jb .spns_exp2; cmp al,'9'; ja .spns_exp2
    inc r9; inc r10d; jmp .spns_fdigs
.spns_exp2:
    test r10d,r10d; jz .spns_fail
.spns_exp:
    cmp r9,[rip+s_end]; jae .spns_done
    mov al,[r9]; cmp al,'e'; je .spns_expgo; cmp al,'E'; jne .spns_done
.spns_expgo:
    inc r9
    cmp r9,[rip+s_end]; jae .spns_fail
    mov al,[r9]; cmp al,'+'; je .spns_expsign; cmp al,'-'; jne .spns_edigs0
.spns_expsign: inc r9
.spns_edigs0:
    xor r10d,r10d
.spns_edigs:
    cmp r9,[rip+s_end]; jae .spns_edone
    mov al,[r9]; cmp al,'0'; jb .spns_edone; cmp al,'9'; ja .spns_edone
    inc r9; inc r10d; jmp .spns_edigs
.spns_edone:
    test r10d,r10d; jz .spns_fail
    jmp .spns_done
.spns_hex:
    add r9,2; xor r10d,r10d
.spns_hloop:
    cmp r9,[rip+s_end]; jae .spns_basedone
    mov al,[r9]
    cmp al,'0'; jb .spns_basedone; cmp al,'9'; jbe .spns_hok
    cmp al,'A'; jb .spns_hlow; cmp al,'F'; jbe .spns_hok
.spns_hlow: cmp al,'a'; jb .spns_basedone; cmp al,'f'; ja .spns_basedone
.spns_hok: inc r9; inc r10d; jmp .spns_hloop
.spns_bin:
    add r9,2; xor r10d,r10d
.spns_bloop:
    cmp r9,[rip+s_end]; jae .spns_basedone
    mov al,[r9]; cmp al,'0'; je .spns_bok; cmp al,'1'; jne .spns_basedone
.spns_bok: inc r9; inc r10d; jmp .spns_bloop
.spns_basedone:
    test r10d,r10d; jz .spns_fail
.spns_done:
    mov [rip+s_cur],r9
    mov rax,r8; mov rcx,r9; sub rcx,r8; xor edx,edx; ret
.spns_fail:
    xor eax,eax; xor ecx,ecx; mov edx,1
    mov dword ptr [rip+s_error],1
    ret

# -----------------------------------------------------------------------------
# AST allocation/scopes
# -----------------------------------------------------------------------------
s_new_ast:
    mov eax,dword ptr [rip+s_ast_count]
    cmp eax,SAST_MAX
    jae .sna_fail
    mov ecx,eax
    shl rcx,6
    lea rax,[rip+s_ast_nodes]
    add rax,rcx
    inc dword ptr [rip+s_ast_count]
    pxor xmm0,xmm0
    movdqu [rax],xmm0; movdqu [rax+16],xmm0; movdqu [rax+32],xmm0; movdqu [rax+48],xmm0
    ret
.sna_fail:
    mov dword ptr [rip+s_error],1
    xor eax,eax; ret

s_span_eq:
    # rdi ptr,rsi len,rdx ptr,rcx len -> eax bool
    cmp rsi,rcx; jne .sseq_no
    xor r8d,r8d
.sseq_loop:
    cmp r8,rcx; jae .sseq_yes
    mov al,[rdi+r8]; cmp al,[rdx+r8]; jne .sseq_no
    inc r8; jmp .sseq_loop
.sseq_yes: mov eax,1; ret
.sseq_no: xor eax,eax; ret

s_classify_ref:
    # rdi=name ptr,rsi=len -> eax NK_VAR/NK_AXIS/NK_STATE
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi
    mov ecx,dword ptr [rip+s_state_count]
    test ecx,ecx; jz .scr_axis
    dec ecx
.scr_state_loop:
    lea rax,[rip+s_state_ptrs]; mov rdi,[rax+rcx*8]
    lea rax,[rip+s_state_lens]; mov rsi,[rax+rcx*8]
    mov rdx,rbx; mov r13,rcx; mov rcx,r12; call s_span_eq
    mov rcx,r13
    test eax,eax; jnz .scr_state_yes
    test ecx,ecx; jz .scr_axis
    dec ecx; jmp .scr_state_loop
.scr_state_yes: mov eax,NK_STATE; jmp .scr_done
.scr_axis:
    mov ecx,dword ptr [rip+s_axis_count]
    test ecx,ecx; jz .scr_var
    dec ecx
.scr_axis_loop:
    lea rax,[rip+s_axis_ptrs]; mov rdi,[rax+rcx*8]
    lea rax,[rip+s_axis_lens]; mov rsi,[rax+rcx*8]
    mov rdx,rbx; mov r13,rcx; mov rcx,r12; call s_span_eq
    mov rcx,r13
    test eax,eax; jnz .scr_axis_yes
    test ecx,ecx; jz .scr_var
    dec ecx; jmp .scr_axis_loop
.scr_axis_yes: mov eax,NK_AXIS; jmp .scr_done
.scr_var: mov eax,NK_VAR
.scr_done:
    pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Expression parser
# -----------------------------------------------------------------------------
s_peek_binop:
    # eax=op code, edx=precedence, ecx=token bytes, 0 if none. Does not consume.
    call s_skip
    mov r8,[rip+s_cur]; cmp r8,[rip+s_end]; jae .spb_none
    mov r10b,[r8]
    # two-byte first. Never use AH here: r8 addressing requires a REX prefix.
    lea r9,[r8+1]; cmp r9,[rip+s_end]; jae .spb_one
    mov r11b,[r8+1]
    # One newline may split a multi-character operator in the human shell.
    # The repair is lexical only; canonical AST still sees one operator.
    cmp r11b,10; je .spb_split_lf
    cmp r11b,13; je .spb_split_cr
    jmp .spb_contiguous2
.spb_split_lf:
    lea r9,[r8+2]; cmp r9,[rip+s_end]; jae .spb_one
    mov r11b,[r9]; mov ecx,3; jmp .spb_split_eval
.spb_split_cr:
    lea r9,[r8+2]; cmp r9,[rip+s_end]; jae .spb_one
    cmp byte ptr [r9],10; jne .spb_one
    lea r9,[r8+3]; cmp r9,[rip+s_end]; jae .spb_one
    mov r11b,[r9]; mov ecx,4
.spb_split_eval:
    cmp r10b,'|'; jne .spbs1; cmp r11b,'|'; jne .spbs1; mov eax,OP_OR; mov edx,1; ret
.spbs1: cmp r10b,'&'; jne .spbs2; cmp r11b,'&'; jne .spbs2; mov eax,OP_AND; mov edx,2; ret
.spbs2: cmp r10b,'='; jne .spbs3; cmp r11b,'='; jne .spbs3; mov eax,OP_EQ; mov edx,6; ret
.spbs3: cmp r10b,'!'; jne .spbs4; cmp r11b,'='; jne .spbs4; mov eax,OP_NE; mov edx,6; ret
.spbs4: cmp r10b,'<'; jne .spbs5; cmp r11b,'='; jne .spbs4sh; mov eax,OP_LE; mov edx,7; ret
.spbs4sh: cmp r11b,'<'; jne .spbs5; mov eax,OP_SHL; mov edx,8; ret
.spbs5: cmp r10b,'>'; jne .spb_one; cmp r11b,'='; jne .spbs5sh; mov eax,OP_GE; mov edx,7; ret
.spbs5sh: cmp r11b,'>'; jne .spb_one; mov eax,OP_SHR; mov edx,8; ret
.spb_contiguous2:
    cmp r10b,'|'; jne 1f; cmp r11b,'|'; je .spb_or
1:  cmp r10b,'&'; jne 2f; cmp r11b,'&'; je .spb_and
2:  cmp r10b,'='; jne 3f; cmp r11b,'='; je .spb_eq
3:  cmp r10b,'!'; jne 4f; cmp r11b,'='; je .spb_ne
4:  cmp r10b,'<'; jne 5f; cmp r11b,'='; je .spb_le; cmp r11b,'<'; je .spb_shl
5:  cmp r10b,'>'; jne .spb_one; cmp r11b,'='; je .spb_ge; cmp r11b,'>'; je .spb_shr
.spb_one:
    mov r10b,[r8]
    cmp r10b,'|'; je .spb_bitor
    cmp r10b,'^'; je .spb_bitxor
    cmp r10b,'&'; je .spb_bitand
    cmp r10b,'<'; je .spb_lt
    cmp r10b,'>'; je .spb_gt
    cmp r10b,'+'; je .spb_add
    cmp r10b,'-'; je .spb_sub
    cmp r10b,'*'; je .spb_mul
    cmp r10b,'/'; je .spb_div
    cmp r10b,'%'; je .spb_mod
    jmp .spb_none
.spb_or: mov eax,OP_OR; mov edx,1; mov ecx,2; ret
.spb_and: mov eax,OP_AND; mov edx,2; mov ecx,2; ret
.spb_bitor: mov eax,OP_BIT_OR; mov edx,3; mov ecx,1; ret
.spb_bitxor: mov eax,OP_BIT_XOR; mov edx,4; mov ecx,1; ret
.spb_bitand: mov eax,OP_BIT_AND; mov edx,5; mov ecx,1; ret
.spb_eq: mov eax,OP_EQ; mov edx,6; mov ecx,2; ret
.spb_ne: mov eax,OP_NE; mov edx,6; mov ecx,2; ret
.spb_lt: mov eax,OP_LT; mov edx,7; mov ecx,1; ret
.spb_le: mov eax,OP_LE; mov edx,7; mov ecx,2; ret
.spb_gt: mov eax,OP_GT; mov edx,7; mov ecx,1; ret
.spb_ge: mov eax,OP_GE; mov edx,7; mov ecx,2; ret
.spb_shl: mov eax,OP_SHL; mov edx,8; mov ecx,2; ret
.spb_shr: mov eax,OP_SHR; mov edx,8; mov ecx,2; ret
.spb_add: mov eax,OP_ADD; mov edx,9; mov ecx,1; ret
.spb_sub: mov eax,OP_SUB; mov edx,9; mov ecx,1; ret
.spb_mul: mov eax,OP_MUL; mov edx,10; mov ecx,1; ret
.spb_div: mov eax,OP_DIV; mov edx,10; mov ecx,1; ret
.spb_mod: mov eax,OP_MOD; mov edx,10; mov ecx,1; ret
.spb_none: xor eax,eax; xor edx,edx; xor ecx,ecx; ret

s_parse_expr:
    # edi=min precedence -> rax AST/0
    push rbx; push r12; push r13; push r14; push r15
    mov r15d,edi
    call s_parse_unary
    test rax,rax; jz .spe_fail
    mov r12,rax
.spe_loop:
    call s_peek_binop
    test eax,eax; jz .spe_ok
    cmp edx,r15d; jb .spe_ok
    mov r13d,eax; mov r14d,edx
    add qword ptr [rip+s_cur],rcx
    lea edi,[r14d+1]
    call s_parse_expr
    test rax,rax; jz .spe_fail
    mov rbx,rax
    call s_new_ast
    test rax,rax; jz .spe_fail
    mov dword ptr [rax+SN_KIND],NK_BINARY
    mov dword ptr [rax+SN_OP],r13d
    mov [rax+SN_A],r12
    mov [rax+SN_B],rbx
    mov r12,rax
    jmp .spe_loop
.spe_ok: mov rax,r12; jmp .spe_done
.spe_fail: xor eax,eax
.spe_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_parse_unary:
    push rbx
    lea rdi,[rip+tok_bang]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spu_not
    lea rdi,[rip+tok_tilde]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spu_bitnot
    lea rdi,[rip+tok_minus]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spu_neg
    call s_parse_postfix
    pop rbx; ret
.spu_not: mov ebx,OP_NOT; jmp .spu_make
.spu_bitnot: mov ebx,OP_BIT_NOT; jmp .spu_make
.spu_neg: mov ebx,OP_NEG
.spu_make:
    call s_parse_unary
    test rax,rax; jz .spu_fail
    # Canonical negative numeric literals stay literals. Do not manufacture an
    # extra runtime negation node merely because the human surface used '-'.
    cmp ebx,OP_NEG; jne .spu_make_node
    cmp dword ptr [rax+SN_KIND],NK_NUM; jne .spu_make_node
    cmp qword ptr [rax+SN_AUX],0; jne .spu_make_node
    mov qword ptr [rax+SN_AUX],1
    pop rbx; ret
.spu_make_node:
    push rax
    call s_new_ast
    pop rcx
    test rax,rax; jz .spu_fail
    mov dword ptr [rax+SN_KIND],NK_UNARY
    mov dword ptr [rax+SN_OP],ebx
    mov [rax+SN_A],rcx
    pop rbx; ret
.spu_fail: xor eax,eax; pop rbx; ret

s_parse_postfix:
    push rbx; push r12; push r13
    call s_parse_primary
    test rax,rax; jz .spp_fail
    mov r12,rax
.spp_loop:
    lea rdi,[rip+tok_dot]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spp_field
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spp_done
    cmp dword ptr [r12+SN_KIND],NK_VAR
    jne .spp_fail
    xor r13d,r13d
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spp_index_done
.spp_index_loop:
    xor edi,edi; call s_parse_expr
    test rax,rax; jz .spp_fail
    mov qword ptr [rax+SN_NEXT],0
    test r13,r13; jz .spp_first_idx
    mov [rbx+SN_NEXT],rax; jmp .spp_idx_linked
.spp_first_idx: mov r13,rax
.spp_idx_linked: mov rbx,rax
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spp_index_loop
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .spp_fail
.spp_index_done:
    call s_new_ast
    test rax,rax; jz .spp_fail
    mov dword ptr [rax+SN_KIND],NK_LOAD
    mov rcx,[r12+SN_PTR]; mov [rax+SN_PTR],rcx
    mov rcx,[r12+SN_LEN]; mov [rax+SN_LEN],rcx
    mov [rax+SN_A],r13
    mov r12,rax
    jmp .spp_loop
.spp_field:
    cmp dword ptr [r12+SN_KIND],NK_VAR; jne .spp_fail
    call s_parse_name; test edx,edx; jnz .spp_fail
    mov rdx,rax; mov rcx,rcx
    mov rdi,[r12+SN_PTR]; mov rsi,[r12+SN_LEN]; call s_record_lookup
    test rax,rax; jz .spp_fail
    mov r12,rax; jmp .spp_loop
.spp_done: mov rax,r12; jmp .spp_exit
.spp_fail: xor eax,eax
.spp_exit: pop r13; pop r12; pop rbx; ret

# Parse function name helpers by exact ASCII identifier spans.
s_ident_eq_const:
    # rdi ptr,rsi len,rdx const,ecx len -> eax
    jmp s_span_eq

s_parse_primary:
    push rbx; push r12; push r13; push r14; push r15
    call s_skip
    mov r8,[rip+s_cur]
    cmp r8,[rip+s_end]; jae .sppp_fail
    mov al,[r8]
    cmp al,'('; je .sppp_group
    cmp al,'"'; je .sppp_string
    cmp al,'0'; jb .sppp_word
    cmp al,'9'; jbe .sppp_number
.sppp_word:
    call s_parse_name
    test edx,edx; jnz .sppp_fail
    mov r12,rax; mov r13,rcx
    # WH structural if cond { yes } else { no } is a dataflow select, never
    # permission to emit a runtime branch object.
    mov rdi,r12; mov rsi,r13; mov edx,KID_IF; call s_span_kw_id
    test eax,eax; jnz .sppp_if
    # true/false
    mov rdi,r12; mov rsi,r13; mov edx,KID_TRUE; call s_span_kw_id
    test eax,eax; jnz .sppp_true
    mov rdi,r12; mov rsi,r13; mov edx,KID_FALSE; call s_span_kw_id
    test eax,eax; jnz .sppp_false
    # Lexical repair must never rewrite an exact axis/state identity.  Axis names
    # are intentionally short (i/j/k/...), so edit-distance repair against
    # ordinary declarations would otherwise fabricate ambiguity or silently turn
    # an axis into a tensor/variable name.  Scope identity therefore outranks the
    # optional human-shell typo repair.
    mov rdi,r12; mov rsi,r13; call s_classify_ref
    cmp eax,NK_AXIS; je .sppp_scoped_ref
    cmp eax,NK_STATE; je .sppp_scoped_ref
    # Resolve declared-name typo/newline repair before any lookahead can consume
    # the separating newline. Non-declared function names are left unchanged.
    mov rdi,r12; mov rsi,r13; call s_try_decl_repair
    mov r12,rax; mov r13,rcx
    cmp dword ptr [rip+s_error],0; jne .sppp_fail
    # Function call?
    lea rdi,[rip+tok_lparen]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sppp_call
    # bare ref. Any conservative declared-name repair has already happened
    # before lookahead, so whitespace/newline state cannot hide it.
    mov rdi,r12; mov rsi,r13; call s_classify_ref
    mov ebx,eax
    jmp .sppp_make_ref
.sppp_scoped_ref:
    mov ebx,eax
.sppp_make_ref:
    call s_new_ast
    test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],ebx
    mov [rax+SN_PTR],r12; mov [rax+SN_LEN],r13
    jmp .sppp_done
.sppp_if:
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r12,rax
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r13,rax
    call s_optional_semicolon
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_expect_token
    mov edi,KID_ELSE; call s_expect_kw_id
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r15,rax
    call s_optional_semicolon
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_expect_token
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_BINARY; mov dword ptr [rax+SN_OP],OP_SELECT
    mov [rax+SN_A],r12; mov [rax+SN_B],r13; mov [rax+SN_C],r15
    jmp .sppp_done
.sppp_true: mov ebx,1; jmp .sppp_bool
.sppp_false: xor ebx,ebx
.sppp_bool:
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_BOOL; mov dword ptr [rax+SN_AUX],ebx
    jmp .sppp_done
.sppp_number:
    # A digit-leading UTF-8 identifier (e.g. 123🔥输入) is a name, not a
    # numeric literal. Scan only the initial decimal run to disambiguate.
    mov r9,[rip+s_cur]
.sppp_num_probe:
    cmp r9,[rip+s_end]; jae .sppp_number_real
    mov al,[r9]; cmp al,'0'; jb .sppp_num_tail; cmp al,'9'; ja .sppp_num_tail
    inc r9; jmp .sppp_num_probe
.sppp_num_tail:
    mov dil,[r9]; call s_is_ident_byte
    test eax,eax; jnz .sppp_word
.sppp_number_real:
    call s_parse_number_span
    test edx,edx; jnz .sppp_fail
    mov r12,rax; mov r13,rcx
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_NUM; mov [rax+SN_PTR],r12; mov [rax+SN_LEN],r13
    jmp .sppp_done
.sppp_string:
    mov r12,r8
    inc r8
.sppp_str_loop:
    cmp r8,[rip+s_end]; jae .sppp_fail
    mov al,[r8]
    cmp al,'\\'; je .sppp_str_escape
    cmp al,'"'; je .sppp_str_close
    cmp al,10; je .sppp_fail
    inc r8; jmp .sppp_str_loop
.sppp_str_escape:
    add r8,2; jmp .sppp_str_loop
.sppp_str_close:
    inc r8
    mov [rip+s_cur],r8
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_STRING
    lea rcx,[r12+1]; mov [rax+SN_PTR],rcx
    mov rcx,r8; sub rcx,r12; sub rcx,2; mov [rax+SN_LEN],rcx
    jmp .sppp_done
.sppp_group:
    lea rdi,[rip+tok_lparen]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr
    mov r12,rax
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    mov rax,r12
    jmp .sppp_done
.sppp_call:
    # cast(type,expr)
    mov rdi,r12; mov rsi,r13; mov edx,KID_CAST; call s_span_kw_id
    test eax,eax; jnz .sppp_cast
    mov rdi,r12; mov rsi,r13; mov edx,KID_GOAL_RESULT; call s_span_kw_id
    test eax,eax; jnz .sppp_goal_result
    # Determine supported function opcode/arity. periodic(x,n) is the
    # canonical ring normalization mod(x,n), not a runtime helper.
    xor ebx,ebx; xor r14d,r14d
    mov rdi,r12; mov rsi,r13; mov edx,KID_PERIODIC; call s_span_kw_id
    test eax,eax; jz 0f; mov ebx,OP_MOD; mov r14d,2; jmp .sppp_call_args
0:  mov rdi,r12; mov rsi,r13; mov edx,KID_SELECT; call s_span_kw_id
    test eax,eax; jz 1f; mov ebx,OP_SELECT; mov r14d,3; jmp .sppp_call_args
1:  mov rdi,r12; mov rsi,r13; mov edx,KID_MIN; call s_span_kw_id
    test eax,eax; jz 2f; mov ebx,OP_MIN; mov r14d,2; jmp .sppp_call_args
2:  mov rdi,r12; mov rsi,r13; mov edx,KID_MAX; call s_span_kw_id
    test eax,eax; jz 3f; mov ebx,OP_MAX; mov r14d,2; jmp .sppp_call_args
3:  mov rdi,r12; mov rsi,r13; mov edx,KID_ABS; call s_span_kw_id
    test eax,eax; jz 4f; mov ebx,OP_ABS; mov r14d,1; jmp .sppp_call_args
4:  mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_xor]; mov ecx,3; call s_span_eq
    test eax,eax; jz 5f; mov ebx,OP_BIT_XOR; mov r14d,2; jmp .sppp_call_args
5:  mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_bit_and]; mov ecx,7; call s_span_eq
    test eax,eax; jz 6f; mov ebx,OP_BIT_AND; mov r14d,2; jmp .sppp_call_args
6:  mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_bit_or]; mov ecx,6; call s_span_eq
    test eax,eax; jz 7f; mov ebx,OP_BIT_OR; mov r14d,2; jmp .sppp_call_args
7:  mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_bit_xor]; mov ecx,7; call s_span_eq
    test eax,eax; jz 8f; mov ebx,OP_BIT_XOR; mov r14d,2; jmp .sppp_call_args
8:  mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_shl]; mov ecx,3; call s_span_eq
    test eax,eax; jz 9f; mov ebx,OP_SHL; mov r14d,2; jmp .sppp_call_args
9:  mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_shr]; mov ecx,3; call s_span_eq
    test eax,eax; jnz .sppp_shr_builtin
    # Built-in English callables use the same unique one-edit repair rule.
    mov rdi,r12; mov rsi,r13; call s_builtin_repair
    test eax,eax; jz .sppp_pure_lookup
    mov ebx,eax; mov r14d,edx; jmp .sppp_call_args
.sppp_pure_lookup:
    # Compile-time pure function expansion. Current sovereign semantic slice
    # accepts one parameter; the call vanishes before canonical emission.
    mov rdi,r12; mov rsi,r13; call s_function_lookup
    cmp eax,-1; je .sppp_fail
    mov ebx,eax
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r15,rax
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    lea rdx,[rip+s_function_param_ptr]; mov rsi,[rdx+rbx*8]
    lea rdx,[rip+s_function_param_len]; mov rdx,[rdx+rbx*8]
    lea rcx,[rip+s_function_expr_ast]; mov rdi,[rcx+rbx*8]
    mov rcx,r15; call s_clone_subst
    test rax,rax; jz .sppp_fail
    jmp .sppp_done
.sppp_goal_result:
    # Closed-cascade dependency reference. It is a compile-time-only AST kind
    # and is never serialised into the runtime graph.
    call s_parse_name; test edx,edx; jnz .sppp_fail
    mov r12,rax; mov r13,rcx
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_GOAL_RESULT
    mov [rax+SN_PTR],r12; mov [rax+SN_LEN],r13
    jmp .sppp_done
.sppp_shr_builtin:
    mov ebx,OP_SHR; mov r14d,2
.sppp_call_args:
    xor r15d,r15d
    xor r12d,r12d
    # up to three args in stack locals via registers r12/r13/r15.
    cmp r14d,0; je .sppp_fail
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r12,rax
    cmp r14d,1; je .sppp_call_close
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r13,rax
    cmp r14d,2; je .sppp_call_close
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail; mov r15,rax
.sppp_call_close:
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_BINARY
    mov dword ptr [rax+SN_OP],ebx
    mov [rax+SN_A],r12; mov [rax+SN_B],r13; mov [rax+SN_C],r15
    jmp .sppp_done
.sppp_cast:
    call s_parse_name
    test edx,edx; jnz .sppp_fail
    mov r12,rax; mov r13,rcx
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppp_fail
    mov r14,rax
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    call s_new_ast; test rax,rax; jz .sppp_fail
    mov dword ptr [rax+SN_KIND],NK_CAST
    mov [rax+SN_PTR],r12; mov [rax+SN_LEN],r13; mov [rax+SN_A],r14
    jmp .sppp_done
.sppp_fail:
    mov dword ptr [rip+s_error],1
    xor eax,eax
.sppp_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# AST serializer and Rank-N expression transform helpers
# -----------------------------------------------------------------------------
s_op_name:
    # edi op -> rax ptr, ecx len
    lea rax,[rip+op_or]; mov ecx,2; cmp edi,OP_OR; je .son_ret
    lea rax,[rip+op_and]; mov ecx,3; cmp edi,OP_AND; je .son_ret
    lea rax,[rip+op_bit_or]; mov ecx,6; cmp edi,OP_BIT_OR; je .son_ret
    lea rax,[rip+op_bit_xor]; mov ecx,7; cmp edi,OP_BIT_XOR; je .son_ret
    lea rax,[rip+op_bit_and]; mov ecx,7; cmp edi,OP_BIT_AND; je .son_ret
    lea rax,[rip+op_eq]; mov ecx,2; cmp edi,OP_EQ; je .son_ret
    lea rax,[rip+op_ne]; mov ecx,2; cmp edi,OP_NE; je .son_ret
    lea rax,[rip+op_lt]; mov ecx,2; cmp edi,OP_LT; je .son_ret
    lea rax,[rip+op_le]; mov ecx,2; cmp edi,OP_LE; je .son_ret
    lea rax,[rip+op_gt]; mov ecx,2; cmp edi,OP_GT; je .son_ret
    lea rax,[rip+op_ge]; mov ecx,2; cmp edi,OP_GE; je .son_ret
    lea rax,[rip+op_shl]; mov ecx,3; cmp edi,OP_SHL; je .son_ret
    lea rax,[rip+op_shr]; mov ecx,3; cmp edi,OP_SHR; je .son_ret
    lea rax,[rip+op_add]; mov ecx,3; cmp edi,OP_ADD; je .son_ret
    lea rax,[rip+op_sub]; mov ecx,3; cmp edi,OP_SUB; je .son_ret
    lea rax,[rip+op_mul]; mov ecx,3; cmp edi,OP_MUL; je .son_ret
    lea rax,[rip+op_div]; mov ecx,3; cmp edi,OP_DIV; je .son_ret
    lea rax,[rip+op_mod]; mov ecx,3; cmp edi,OP_MOD; je .son_ret
    lea rax,[rip+op_not]; mov ecx,3; cmp edi,OP_NOT; je .son_ret
    lea rax,[rip+op_bit_not]; mov ecx,7; cmp edi,OP_BIT_NOT; je .son_ret
    lea rax,[rip+op_neg]; mov ecx,3; cmp edi,OP_NEG; je .son_ret
    lea rax,[rip+op_select]; mov ecx,6; cmp edi,OP_SELECT; je .son_ret
    lea rax,[rip+op_min]; mov ecx,3; cmp edi,OP_MIN; je .son_ret
    lea rax,[rip+op_max]; mov ecx,3; cmp edi,OP_MAX; je .son_ret
    lea rax,[rip+op_abs]; mov ecx,3; cmp edi,OP_ABS; je .son_ret
    lea rax,[rip+op_ushr]; mov ecx,4; cmp edi,OP_USHR; je .son_ret
    xor eax,eax; xor ecx,ecx
.son_ret: ret

s_emit_ast:
    # rdi=node
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    test rbx,rbx; jz .sea_fail
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_NUM; je .sea_num
    cmp eax,NK_STRING; je .sea_string
    cmp eax,NK_BOOL; je .sea_bool
    cmp eax,NK_VAR; je .sea_var
    cmp eax,NK_AXIS; je .sea_axis
    cmp eax,NK_STATE; je .sea_state
    cmp eax,NK_UNARY; je .sea_op
    cmp eax,NK_BINARY; je .sea_op
    cmp eax,NK_CAST; je .sea_cast
    cmp eax,NK_LOAD; je .sea_load
    cmp eax,NK_IMM_U64; je .sea_imm_u64
    jmp .sea_fail
.sea_imm_u64:
    lea rdi,[rip+js_lit_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_AUX]; call s_emit_u64_decimal
    lea rdi,[rip+js_type_mid]; call s_out_cstr
    lea rdi,[rip+ty_u64]; mov esi,3; call s_out_quote_span
    jmp .sea_close
.sea_num:
    lea rdi,[rip+js_lit_prefix]; call s_out_cstr
    cmp qword ptr [rbx+SN_AUX],0; je .sea_num_unsigned
    mov dil,'-'; call s_out_byte
.sea_num_unsigned:
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_span
    lea rdi,[rip+js_type_mid]; call s_out_cstr
    # Decimal point/e/E -> f64. Otherwise u64 (negative is represented by unary neg in human AST).
    mov r12,[rbx+SN_PTR]; mov r13,[rbx+SN_LEN]; xor r14d,r14d; xor r15d,r15d
.sea_numscan:
    cmp r15,r13; jae .sea_numtype
    mov al,[r12+r15]; cmp al,'.'; je .sea_isf; cmp al,'e'; je .sea_isf; cmp al,'E'; je .sea_isf
    inc r15; jmp .sea_numscan
.sea_isf: mov r14d,1
.sea_numtype:
    test r14d,r14d; jz .sea_u64
    lea rdi,[rip+ty_f64]; mov esi,3; call s_out_quote_span; jmp .sea_close
.sea_u64: lea rdi,[rip+ty_u64]; mov esi,3; call s_out_quote_span; jmp .sea_close
.sea_string:
    lea rdi,[rip+js_lit_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_quote_span
    lea rdi,[rip+js_type_mid]; call s_out_cstr
    lea rdi,[rip+ty_string]; mov esi,6; call s_out_quote_span; jmp .sea_close
.sea_bool:
    lea rdi,[rip+js_lit_prefix]; call s_out_cstr
    cmp dword ptr [rbx+SN_AUX],0; je .sea_bool_false
    lea rdi,[rip+lit_true]; call s_out_cstr; jmp .sea_bool_type
.sea_bool_false: lea rdi,[rip+lit_false]; call s_out_cstr
.sea_bool_type:
    lea rdi,[rip+js_type_mid]; call s_out_cstr
    lea rdi,[rip+ty_bool]; mov esi,4; call s_out_quote_span; jmp .sea_close
.sea_var:
    lea rdi,[rip+js_var_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_quote_span; jmp .sea_close
.sea_axis:
    lea rdi,[rip+js_axis_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_quote_span; jmp .sea_close
.sea_state:
    lea rdi,[rip+js_state_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_quote_span; jmp .sea_close
.sea_op:
    lea rdi,[rip+js_op_prefix]; call s_out_cstr
    mov edi,dword ptr [rbx+SN_OP]; call s_op_name
    test rax,rax; jz .sea_fail
    mov rdi,rax; mov rsi,rcx; call s_out_quote_span
    lea rdi,[rip+js_args_mid]; call s_out_cstr
    mov rdi,[rbx+SN_A]; call s_emit_ast; test eax,eax; jnz .sea_fail
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_UNARY; je .sea_args_close
    mov eax,dword ptr [rbx+SN_OP]
    cmp eax,OP_ABS; je .sea_args_close
    mov dil,','; call s_out_byte
    mov rdi,[rbx+SN_B]; call s_emit_ast; test eax,eax; jnz .sea_fail
    mov eax,dword ptr [rbx+SN_OP]
    cmp eax,OP_SELECT; jne .sea_args_close
    mov dil,','; call s_out_byte
    mov rdi,[rbx+SN_C]; call s_emit_ast; test eax,eax; jnz .sea_fail
.sea_args_close:
    lea rdi,[rip+js_arr_obj_close]; call s_out_cstr
    jmp .sea_ok
.sea_cast:
    lea rdi,[rip+js_cast_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_quote_span
    lea rdi,[rip+js_cast_mid]; call s_out_cstr
    mov rdi,[rbx+SN_A]; call s_emit_ast; test eax,eax; jnz .sea_fail
    lea rdi,[rip+js_arr_obj_close]; call s_out_cstr
    jmp .sea_ok
.sea_load:
    lea rdi,[rip+js_load_prefix]; call s_out_cstr
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_out_quote_span
    lea rdi,[rip+js_indices_mid]; call s_out_cstr
    mov r12,[rbx+SN_A]; xor r13d,r13d
.sea_idx_loop:
    test r12,r12; jz .sea_idx_done
    test r13d,r13d; jz .sea_idx_no_comma
    mov dil,','; call s_out_byte
.sea_idx_no_comma:
    mov rdi,r12; call s_emit_ast; test eax,eax; jnz .sea_fail
    mov r12,[r12+SN_NEXT]; mov r13d,1; jmp .sea_idx_loop
.sea_idx_done:
    lea rdi,[rip+js_arr_obj_close]; call s_out_cstr
    jmp .sea_ok
.sea_close:
    mov dil,'}'; call s_out_byte
.sea_ok:
    xor eax,eax; jmp .sea_done
.sea_fail:
    mov dword ptr [rip+s_error],1; mov eax,1
.sea_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# Create literal-u64 AST from immediate rdi.
s_ast_u64_imm:
    # Native immediate AST owns the numeric value. It never aliases mutable text
    # scratch, so multiple Rank-N coordinates remain independent until emission.
    push rbx
    mov rbx,rdi
    call s_new_ast
    test rax,rax; jz .saui_done
    mov dword ptr [rax+SN_KIND],NK_IMM_U64
    mov [rax+SN_AUX],rbx
.saui_done:
    pop rbx
    ret

s_ast_binary_new:
    # edi=op,rsi=a,rdx=b -> rax
    push rbx; push r12; push r13
    mov ebx,edi; mov r12,rsi; mov r13,rdx
    call s_new_ast; test rax,rax; jz .sabn_done
    mov dword ptr [rax+SN_KIND],NK_BINARY; mov dword ptr [rax+SN_OP],ebx
    mov [rax+SN_A],r12; mov [rax+SN_B],r13
.sabn_done: pop r13; pop r12; pop rbx; ret

s_rankn_rewrite:
    # rdi=node -> rax rewritten node. Current reduction rank layout globals.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi
    test rbx,rbx; jz .srw_done
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_AXIS; je .srw_axis
    cmp eax,NK_VAR; je .srw_var
    cmp eax,NK_UNARY; je .srw_unary
    cmp eax,NK_BINARY; je .srw_binary
    cmp eax,NK_CAST; je .srw_cast
    cmp eax,NK_LOAD; je .srw_load
    mov rax,rbx; jmp .srw_done
.srw_var:
    # source-level n inside a product expression is logical n = physical_n >> static_bits
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; lea rdx,[rip+name_n]; mov ecx,1; call s_span_eq
    test eax,eax; jz .srw_same
    cmp dword ptr [rip+s_rank_static_bits],0; je .srw_same
    mov r12,rbx
    mov edi,dword ptr [rip+s_rank_static_bits]; call s_ast_u64_imm; mov r13,rax
    mov edi,OP_USHR; mov rsi,r12; mov rdx,r13; call s_ast_binary_new
    jmp .srw_done
.srw_axis:
    xor r12d,r12d
.srw_axis_scan:
    cmp r12d,dword ptr [rip+s_rank_count]; jae .srw_same
    lea rax,[rip+s_rank_axis_ptrs]; mov rdi,[rax+r12*8]
    lea rax,[rip+s_rank_axis_lens]; mov rsi,[rax+r12*8]
    mov rdx,[rbx+SN_PTR]; mov rcx,[rbx+SN_LEN]; call s_span_eq
    test eax,eax; jnz .srw_axis_found
    inc r12d; jmp .srw_axis_scan
.srw_axis_found:
    # q axis node
    call s_new_ast; test rax,rax; jz .srw_fail
    mov dword ptr [rax+SN_KIND],NK_AXIS
    lea rcx,[rip+rank_q_name]; mov [rax+SN_PTR],rcx; mov qword ptr [rax+SN_LEN],11
    mov r13,rax
    lea rax,[rip+s_rank_dynamic]; cmp dword ptr [rax+r12*4],0; je .srw_static_axis
    mov eax,dword ptr [rip+s_rank_static_bits]; test eax,eax; jz .srw_q_direct
    mov edi,eax; call s_ast_u64_imm; mov r14,rax
    mov edi,OP_USHR; mov rsi,r13; mov rdx,r14; call s_ast_binary_new; jmp .srw_done
.srw_q_direct: mov rax,r13; jmp .srw_done
.srw_static_axis:
    lea rax,[rip+s_rank_low_bit]; mov edi,[rax+r12*4]
    test edi,edi; jz .srw_after_shift
    call s_ast_u64_imm; mov r14,rax
    mov edi,OP_USHR; mov rsi,r13; mov rdx,r14; call s_ast_binary_new; mov r13,rax
.srw_after_shift:
    lea rax,[rip+s_rank_extent]; mov edi,[rax+r12*8]
    cmp edi,1; je .srw_zero
    call s_ast_u64_imm; mov r14,rax
    mov edi,OP_MOD; mov rsi,r13; mov rdx,r14; call s_ast_binary_new; jmp .srw_done
.srw_zero: xor edi,edi; call s_ast_u64_imm; jmp .srw_done
.srw_unary:
    mov rdi,[rbx+SN_A]; call s_rankn_rewrite; mov [rbx+SN_A],rax; mov rax,rbx; jmp .srw_done
.srw_binary:
    mov rdi,[rbx+SN_A]; call s_rankn_rewrite; mov [rbx+SN_A],rax
    mov rdi,[rbx+SN_B]; call s_rankn_rewrite; mov [rbx+SN_B],rax
    mov rdi,[rbx+SN_C]; test rdi,rdi; jz 1f; call s_rankn_rewrite; mov [rbx+SN_C],rax
1:  mov rax,rbx; jmp .srw_done
.srw_cast:
    mov rdi,[rbx+SN_A]; call s_rankn_rewrite; mov [rbx+SN_A],rax; mov rax,rbx; jmp .srw_done
.srw_load:
    mov r12,[rbx+SN_A]
    test r12,r12; jz .srw_same
    cmp dword ptr [rip+s_rank_count],1; jbe .srw_load_rank1
    # A tuple load x[i,j,...] over the same proved Rank-N episode is exactly the
    # current product coordinate q. Collapse the tuple structurally; no nested
    # serial indexing loop is emitted. More complex affine tuple indices reject.
    xor r13d,r13d
.srw_load_tuple_loop:
    cmp r13d,dword ptr [rip+s_rank_count]; jae .srw_load_tuple_end
    test r12,r12; jz .srw_fail
    cmp dword ptr [r12+SN_KIND],NK_AXIS; jne .srw_fail
    lea rax,[rip+s_rank_axis_ptrs]; mov rdi,[rax+r13*8]
    lea rax,[rip+s_rank_axis_lens]; mov rsi,[rax+r13*8]
    mov rdx,[r12+SN_PTR]; mov rcx,[r12+SN_LEN]; call s_span_eq
    test eax,eax; jz .srw_fail
    mov r12,[r12+SN_NEXT]
    inc r13d; jmp .srw_load_tuple_loop
.srw_load_tuple_end:
    test r12,r12; jnz .srw_fail
    call s_new_ast; test rax,rax; jz .srw_fail
    mov dword ptr [rax+SN_KIND],NK_AXIS
    lea rcx,[rip+rank_q_name]; mov [rax+SN_PTR],rcx; mov qword ptr [rax+SN_LEN],11
    mov qword ptr [rax+SN_NEXT],0
    mov [rbx+SN_A],rax
    mov rax,rbx; jmp .srw_done
.srw_load_rank1:
    cmp qword ptr [r12+SN_NEXT],0; jne .srw_fail
    mov rdi,r12; call s_rankn_rewrite; mov [rbx+SN_A],rax; mov rax,rbx; jmp .srw_done
.srw_same: mov rax,rbx; jmp .srw_done
.srw_fail: mov dword ptr [rip+s_error],1; xor eax,eax
.srw_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Stream selection and item prefix
# -----------------------------------------------------------------------------
s_stream_inputs:
    lea rax,[rip+s_inputs_end]; mov rax,[rax]; mov [rip+s_out_ptr],rax
    lea rax,[rip+s_inputs_buf+SBUF_INPUTS_CAP]; mov [rip+s_out_limit],rax; ret
s_stream_bindings:
    lea rax,[rip+s_bindings_end]; mov rax,[rax]; mov [rip+s_out_ptr],rax
    lea rax,[rip+s_bindings_buf+SBUF_BINDINGS_CAP]; mov [rip+s_out_limit],rax; ret
s_stream_outputs:
    lea rax,[rip+s_outputs_end]; mov rax,[rax]; mov [rip+s_out_ptr],rax
    lea rax,[rip+s_outputs_buf+SBUF_OUTPUTS_CAP]; mov [rip+s_out_limit],rax; ret
s_stream_tests:
    lea rax,[rip+s_tests_end]; mov rax,[rax]; mov [rip+s_out_ptr],rax
    lea rax,[rip+s_tests_buf+SBUF_TESTS_CAP]; mov [rip+s_out_limit],rax; ret
s_commit_inputs: mov rax,[rip+s_out_ptr]; mov [rip+s_inputs_end],rax; ret
s_commit_bindings: mov rax,[rip+s_out_ptr]; mov [rip+s_bindings_end],rax; ret
s_commit_outputs: mov rax,[rip+s_out_ptr]; mov [rip+s_outputs_end],rax; ret
s_commit_tests: mov rax,[rip+s_out_ptr]; mov [rip+s_tests_end],rax; ret

s_item_prefix:
    # rdi=&count. emits comma when count>0, increments.
    mov eax,[rdi]
    test eax,eax; jz .sip_inc
    push rdi; mov dil,','; call s_out_byte; pop rdi
.sip_inc: inc dword ptr [rdi]; ret

# -----------------------------------------------------------------------------
# Type parser/serializer
# -----------------------------------------------------------------------------
s_parse_type_emit:
    # output JSON type representation; eax type code 1 bool,2 i64,3 u64,4 f32,5 f64,6 string, 0 fail
    push rbx; push r12
    call s_parse_name
    test edx,edx; jnz .spte_fail
    mov r12,rax; mov rbx,rcx
    xor r10d,r10d
    mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_bool]; mov ecx,4; call s_span_eq; test eax,eax; jz 1f; mov r10d,1; jmp .spte_base
1:  mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_i64]; mov ecx,3; call s_span_eq; test eax,eax; jz 2f; mov r10d,2; jmp .spte_base
2:  mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_u64]; mov ecx,3; call s_span_eq; test eax,eax; jz 3f; mov r10d,3; jmp .spte_base
3:  mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_f32]; mov ecx,3; call s_span_eq; test eax,eax; jz 4f; mov r10d,4; jmp .spte_base
4:  mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_f64]; mov ecx,3; call s_span_eq; test eax,eax; jz 5f; mov r10d,5; jmp .spte_base
5:  mov rdi,r12; mov rsi,rbx; lea rdx,[rip+ty_string]; mov ecx,6; call s_span_eq; test eax,eax; jz .spte_fail; mov r10d,6
.spte_base:
    # tolerant suffix is currently accepted only for floating point.
    lea rdi,[rip+tok_tilde]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spte_simple
    cmp r10d,4; jb .spte_fail
    lea rdi,[rip+js_type_obj_base]; call s_out_cstr
    mov rdi,r12; mov rsi,rbx; call s_out_quote_span
    lea rdi,[rip+js_tol_mid_abs]; call s_out_cstr
    # parse ~(abs=num,rel=num), preserving source numerics
    lea rdi,[rip+tok_lparen]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .spte_fail
    # field name must abs
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+kw_abs]; mov ecx,3; call s_span_eq; test eax,eax; jz .spte_fail
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_number_span; test edx,edx; jnz .spte_fail
    mov rdi,rax; mov rsi,rcx; call s_out_span
    lea rdi,[rip+js_tol_mid_rel]; call s_out_cstr
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .spte_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+kw_rel]; mov ecx,3; call s_span_eq; test eax,eax; jz .spte_fail
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_number_span; test edx,edx; jnz .spte_fail
    mov rdi,rax; mov rsi,rcx; call s_out_span
    mov dil,'}'; call s_out_byte
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    mov eax,r10d; jmp .spte_done
.spte_simple:
    mov rdi,r12; mov rsi,rbx; call s_out_quote_span
    mov eax,r10d; jmp .spte_done
.spte_fail: mov dword ptr [rip+s_error],1; xor eax,eax
.spte_done: pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Axis list parsers
# -----------------------------------------------------------------------------
s_axis_scope_clear:
    mov dword ptr [rip+s_axis_count],0
    ret
s_state_scope_clear:
    mov dword ptr [rip+s_state_count],0
    ret

s_axis_add:
    # rdi ptr,rsi len. eax index/ -1
    mov eax,dword ptr [rip+s_axis_count]; cmp eax,SCOPE_MAX; jae .saa_fail
    lea rdx,[rip+s_axis_ptrs]; mov [rdx+rax*8],rdi
    lea rdx,[rip+s_axis_lens]; mov [rdx+rax*8],rsi
    inc dword ptr [rip+s_axis_count]
    ret
.saa_fail: mov dword ptr [rip+s_error],1; mov eax,-1; ret

s_state_add:
    mov eax,dword ptr [rip+s_state_count]; cmp eax,SCOPE_MAX; jae .ssa_fail
    lea rdx,[rip+s_state_ptrs]; mov [rdx+rax*8],rdi
    lea rdx,[rip+s_state_lens]; mov [rdx+rax*8],rsi
    inc dword ptr [rip+s_state_count]
    ret
.ssa_fail: mov dword ptr [rip+s_error],1; mov eax,-1; ret

# Parse WH axis list [name:extent,...], emit canonical axes array and install scope.
s_parse_wh_axes_emit:
    call s_axis_scope_clear
    mov dil,'['; call s_out_byte
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_expect_token
    xor ebx,ebx
.spwa_loop:
    call s_parse_name; test edx,edx; jnz .spwa_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_axis_add
    test ebx,ebx; jz .spwa_nocomma
    mov dil,','; call s_out_byte
.spwa_nocomma:
    lea rdi,[rip+js_axis_obj_name]; call s_out_cstr
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_extent_mid]; call s_out_cstr
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spwa_fail
    mov rdi,rax; call s_emit_ast
    mov dil,'}'; call s_out_byte
    inc ebx
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spwa_loop
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
    mov dil,']'; call s_out_byte
    xor eax,eax; ret
.spwa_fail: mov eax,1; ret

# WHEX axes [i in n,j in 2,...]. Records rank layout for optional Rank-N physicalization.
s_parse_whex_axes_record:
    call s_axis_scope_clear
    mov dword ptr [rip+s_rank_count],0
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_expect_token
.spwx_loop:
    call s_parse_name; test edx,edx; jnz .spwx_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_axis_add
    mov ebx,dword ptr [rip+s_rank_count]; cmp ebx,RANK_MAX; jae .spwx_fail
    lea rax,[rip+s_rank_axis_ptrs]; mov [rax+rbx*8],r12
    lea rax,[rip+s_rank_axis_lens]; mov [rax+rbx*8],r13
    mov edi,KID_IN; call s_expect_kw_id
    call s_skip
    # Extent must be name n or positive decimal literal for native WHEX lane.
    mov r8,[rip+s_cur]; cmp r8,[rip+s_end]; jae .spwx_fail
    mov al,[r8]; cmp al,'0'; jb .spwx_extent_name; cmp al,'9'; jbe .spwx_extent_num
.spwx_extent_name:
    call s_parse_name; test edx,edx; jnz .spwx_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+name_n]; mov ecx,1; call s_span_eq; test eax,eax; jz .spwx_fail
    lea rax,[rip+s_rank_dynamic]; mov dword ptr [rax+rbx*4],1
    lea rax,[rip+s_rank_extent]; mov qword ptr [rax+rbx*8],0
    jmp .spwx_extent_done
.spwx_extent_num:
    call s_parse_number_span; test edx,edx; jnz .spwx_fail
    # decimal integer -> u64
    xor r14,r14; xor r15d,r15d
.spwx_numconv:
    cmp r15,rcx; jae .spwx_numok
    movzx edx,byte ptr [rax+r15]; cmp dl,'0'; jb .spwx_fail; cmp dl,'9'; ja .spwx_fail
    imul r14,r14,10; sub edx,'0'; add r14,rdx; inc r15; jmp .spwx_numconv
.spwx_numok:
    test r14,r14; jz .spwx_fail
    mov rdx,r14; dec rdx; test r14,rdx; jnz .spwx_fail
    lea rdx,[rip+s_rank_dynamic]; mov dword ptr [rdx+rbx*4],0
    lea rdx,[rip+s_rank_extent]; mov [rdx+rbx*8],r14
.spwx_extent_done:
    inc dword ptr [rip+s_rank_count]
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spwx_loop
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
    xor eax,eax; ret
.spwx_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_prepare_rankn_layout:
    # rank>1: exactly one dynamic n, static power-of-two extents. Computes factor/bits/lowbits.
    mov eax,dword ptr [rip+s_rank_count]
    cmp eax,1; jbe .sprl_rank1
    xor ebx,ebx; xor r12d,r12d; mov r13,1; xor r14d,r14d
.sprl_scan:
    cmp ebx,dword ptr [rip+s_rank_count]; jae .sprl_scan_done
    lea rax,[rip+s_rank_dynamic]; cmp dword ptr [rax+rbx*4],0; je .sprl_static
    inc r12d; jmp .sprl_next
.sprl_static:
    lea rax,[rip+s_rank_extent]; mov r15,[rax+rbx*8]
    imul r13,r15
    # bit count log2
    bsf rcx,r15
    add r14d,ecx
.sprl_next: inc ebx; jmp .sprl_scan
.sprl_scan_done:
    cmp r12d,1; jne .sprl_fail
    mov [rip+s_rank_static_factor],r13
    mov [rip+s_rank_static_bits],r14d
    # low bits assigned from rightmost static axis.
    xor r14d,r14d
    mov ebx,dword ptr [rip+s_rank_count]
.sprl_low:
    test ebx,ebx; jz .sprl_ok
    dec ebx
    lea rax,[rip+s_rank_dynamic]; cmp dword ptr [rax+rbx*4],0; jne .sprl_low
    lea rax,[rip+s_rank_low_bit]; mov [rax+rbx*4],r14d
    lea rax,[rip+s_rank_extent]; mov r15,[rax+rbx*8]; bsf rcx,r15; add r14d,ecx
    jmp .sprl_low
.sprl_ok: mov eax,1; ret
.sprl_rank1:
    mov qword ptr [rip+s_rank_static_factor],1
    mov dword ptr [rip+s_rank_static_bits],0
    xor eax,eax; ret
.sprl_fail: mov dword ptr [rip+s_error],1; mov eax,-1; ret

# -----------------------------------------------------------------------------
# Top-level WH declarations
# -----------------------------------------------------------------------------
s_parse_program_decl:
    call s_parse_name; test edx,edx; jnz .spd_fail
    mov [rip+s_program_ptr],rax; mov [rip+s_program_len],rcx
    call s_optional_semicolon
    xor eax,eax; ret
.spd_fail: mov eax,1; ret

s_optional_semicolon:
    lea rdi,[rip+tok_semicolon]; mov esi,1; xor edx,edx; call s_match_token; ret

s_parse_contract_decl:
    call s_parse_name; test edx,edx; jnz .spcd_fail
    mov r12,rax; mov r13,rcx
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    # integer_overflow=trap/wrap and deterministic=true/false are compile-significant.
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+ck_integer_overflow]; mov ecx,16; call s_span_eq
    test eax,eax; jnz .spcd_overflow
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+ck_deterministic]; mov ecx,13; call s_span_eq
    test eax,eax; jnz .spcd_det
    # generic value consume as name/number/string, ignored by current native contract.
    call s_skip
    mov r8,[rip+s_cur]; cmp r8,[rip+s_end]; jae .spcd_fail
    mov al,[r8]; cmp al,'"'; je .spcd_skipstr; cmp al,'0'; jb .spcd_skipname; cmp al,'9'; jbe .spcd_skipnum
.spcd_skipname: call s_parse_name; jmp .spcd_done
.spcd_skipnum: call s_parse_number_span; jmp .spcd_done
.spcd_skipstr:
    inc r8
.spcd_strloop: cmp r8,[rip+s_end]; jae .spcd_fail; cmp byte ptr [r8],'"'; je .spcd_strdone; inc r8; jmp .spcd_strloop
.spcd_strdone: inc r8; mov [rip+s_cur],r8; jmp .spcd_done
.spcd_overflow:
    call s_parse_name; test edx,edx; jnz .spcd_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+cv_wrap]; mov ecx,4; call s_span_eq; test eax,eax; jz .spcd_trytrap
    mov dword ptr [rip+s_overflow_wrap],1; jmp .spcd_done
.spcd_trytrap:
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+cv_trap]; mov ecx,4; call s_span_eq; test eax,eax; jz .spcd_fail
    mov dword ptr [rip+s_overflow_wrap],0; jmp .spcd_done
.spcd_det:
    call s_parse_name; test edx,edx; jnz .spcd_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+kw_true]; mov ecx,4; call s_span_eq; test eax,eax; jz .spcd_detfalse
    mov dword ptr [rip+s_deterministic],1; jmp .spcd_done
.spcd_detfalse:
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+kw_false]; mov ecx,5; call s_span_eq; test eax,eax; jz .spcd_fail
    mov dword ptr [rip+s_deterministic],0
.spcd_done: call s_optional_semicolon; xor eax,eax; ret
.spcd_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_input_decl:
    call s_stream_inputs
    lea rdi,[rip+s_input_count]; call s_item_prefix
    mov dil,'{'; call s_out_byte
    lea rdi,[rip+js_name_key]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .spid_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spid_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_type_key]; call s_out_cstr
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_type_emit; test eax,eax; jz .spid_fail
    # optional range
    mov edi,KID_RANGE; call s_match_kw_id
    test eax,eax; jz .spid_close
    lea rdi,[rip+js_min_key]; call s_out_cstr
    call s_parse_signed_literal_emit; test eax,eax; jnz .spid_fail
    lea rdi,[rip+tok_dotdot]; mov esi,2; xor edx,edx; call s_expect_token
    lea rdi,[rip+js_max_key]; call s_out_cstr
    call s_parse_signed_literal_emit; test eax,eax; jnz .spid_fail
.spid_close:
    mov dil,'}'; call s_out_byte; call s_commit_inputs; call s_optional_semicolon; xor eax,eax; ret
.spid_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_signed_literal_emit:
    # emits JSON scalar literal (numbers/bool/string) without typed expression wrapper.
    lea rdi,[rip+tok_minus]; mov esi,1; xor edx,edx; call s_match_token
    mov r12d,eax
    call s_skip
    mov r8,[rip+s_cur]; cmp r8,[rip+s_end]; jae .spsle_fail
    mov al,[r8]; cmp al,'"'; je .spsle_str
    cmp al,'0'; jb .spsle_name
    cmp al,'9'; ja .spsle_name
    test r12d,r12d; jz .spsle_num
    mov dil,'-'; call s_out_byte
.spsle_num:
    call s_parse_number_span; test edx,edx; jnz .spsle_fail
    mov rdi,rax; mov rsi,rcx; call s_out_span; xor eax,eax; ret
.spsle_name:
    test r12d,r12d; jnz .spsle_fail
    call s_parse_name; test edx,edx; jnz .spsle_fail
    mov r10,rax; mov r11,rcx
    mov rdi,r10; mov rsi,r11; mov edx,KID_TRUE; call s_span_kw_id; test eax,eax; jnz .spsle_true
    mov rdi,r10; mov rsi,r11; mov edx,KID_FALSE; call s_span_kw_id; test eax,eax; jnz .spsle_false
    jmp .spsle_fail
.spsle_true: lea rdi,[rip+lit_true]; call s_out_cstr; xor eax,eax; ret
.spsle_false: lea rdi,[rip+lit_false]; call s_out_cstr; xor eax,eax; ret
.spsle_str:
    test r12d,r12d; jnz .spsle_fail
    # reuse primary string AST then serialize literal value only is inconvenient; copy raw JSON string span.
    mov r9,r8; inc r9
.spsle_sloop: cmp r9,[rip+s_end]; jae .spsle_fail; cmp byte ptr [r9],'"'; je .spsle_sdone; cmp byte ptr [r9],'\\'; je .spsle_esc; inc r9; jmp .spsle_sloop
.spsle_esc: add r9,2; jmp .spsle_sloop
.spsle_sdone: inc r9; mov [rip+s_cur],r9; mov rdi,r8; mov rsi,r9; sub rsi,r8; call s_out_span; xor eax,eax; ret
.spsle_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_let_decl:
    mov dword ptr [rip+s_general_lane],1
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .spld_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spld_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_compute_prefix]; call s_out_cstr
    # Explicit types are metadata, not a different execution path. Emit them
    # directly into the same canonical binding before the expression.
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spld_expr_key
    lea rdi,[rip+js_type_key]; call s_out_cstr
    call s_parse_type_emit; test eax,eax; jz .spld_fail
.spld_expr_key:
    lea rdi,[rip+js_expr_key]; call s_out_cstr
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spld_fail
    mov rdi,rax; call s_emit_ast; test eax,eax; jnz .spld_fail
    mov dil,'}'; call s_out_byte; call s_commit_bindings; call s_optional_semicolon; xor eax,eax; ret
.spld_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_output_decl:
    call s_stream_outputs; lea rdi,[rip+s_output_count]; call s_item_prefix
    lea rdi,[rip+js_output_label]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .spod_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_try_decl_repair
    mov r12,rax; mov r13,rcx
    cmp dword ptr [rip+s_error],0; jne .spod_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_output_expr_mid]; call s_out_cstr
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spod_bare
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spod_fail
    mov rdi,rax; call s_emit_ast; jmp .spod_close
.spod_bare:
    # bare output/publish name -> var reference
    call s_new_ast; test rax,rax; jz .spod_fail
    mov dword ptr [rax+SN_KIND],NK_VAR; mov [rax+SN_PTR],r12; mov [rax+SN_LEN],r13
    mov rdi,rax; call s_emit_ast
.spod_close:
    mov dil,'}'; call s_out_byte; call s_commit_outputs; call s_optional_semicolon; xor eax,eax; ret
.spod_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_test_decl:
    call s_stream_tests; lea rdi,[rip+s_test_count]; call s_item_prefix
    lea rdi,[rip+js_test_args]; call s_out_cstr
    lea rdi,[rip+tok_lparen]; mov esi,1; xor edx,edx; call s_expect_token
    xor ebx,ebx
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sptd_args_done
.sptd_arg_loop:
    test ebx,ebx; jz .sptd_arg_nocomma
    mov dil,','; call s_out_byte
.sptd_arg_nocomma:
    call s_parse_signed_literal_emit; test eax,eax; jnz .sptd_fail
    inc ebx
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sptd_arg_loop
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
.sptd_args_done:
    lea rdi,[rip+js_expected_mid]; call s_out_cstr
    lea rdi,[rip+tok_arrowfat]; mov esi,2; xor edx,edx; call s_expect_token
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
    xor ebx,ebx
.sptd_exp_loop:
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sptd_close
    test ebx,ebx; jz .sptd_exp_nocomma
    mov dil,','; call s_out_byte
.sptd_exp_nocomma:
    call s_parse_name; test edx,edx; jnz .sptd_fail
    mov rdi,rax; mov rsi,rcx; call s_try_decl_repair
    cmp dword ptr [rip+s_error],0; jne .sptd_fail
    mov rdi,rax; mov rsi,rcx; call s_out_quote_span
    mov dil,':'; call s_out_byte
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_signed_literal_emit; test eax,eax; jnz .sptd_fail
    inc ebx
    # Expected fields accept either comma or semicolon separators, matching the
    # human WH/WHEX surface. JSON commas are emitted structurally next iteration.
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sptd_exp_loop
    lea rdi,[rip+tok_semicolon]; mov esi,1; xor edx,edx; call s_match_token
    jmp .sptd_exp_loop
.sptd_close:
    lea rdi,[rip+js_test_close]; call s_out_cstr
    call s_commit_tests; call s_optional_semicolon; xor eax,eax; ret
.sptd_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_iterate_decl:
    mov dword ptr [rip+s_general_lane],1
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .spit_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spit_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_iterate_mid]; call s_out_cstr
    mov edi,KID_LIMIT; call s_expect_kw_id
    # max_iterations is emitted later, so parse AST and retain.
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spit_fail
    mov [rip+s_iter_limit_ast],rax
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
    call s_state_scope_clear
    xor ebx,ebx                    # state count
    mov qword ptr [rip+s_iter_condition_ast],0
    mov qword ptr [rip+s_iter_result_ptr],0
    mov dword ptr [rip+s_iter_update_count],0
    # Emit states array immediately.
.spit_member:
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spit_members_done
    mov edi,KID_STATE; call s_match_kw_id
    test eax,eax; jnz .spit_state
    mov edi,KID_WHILE; call s_match_kw_id
    test eax,eax; jnz .spit_while
    mov edi,KID_UPDATE; call s_match_kw_id
    test eax,eax; jnz .spit_update
    mov edi,KID_RESULT; call s_match_kw_id
    test eax,eax; jnz .spit_result
    jmp .spit_fail
.spit_state:
    cmp ebx,SCOPE_MAX; jae .spit_fail
    call s_parse_name; test edx,edx; jnz .spit_fail
    mov r14,rax; mov r15,rcx
    lea rax,[rip+s_iter_state_name_ptr]; mov [rax+rbx*8],r14
    lea rax,[rip+s_iter_state_name_len]; mov [rax+rbx*8],r15
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    # Type span is constrained scalar; remember by parsing name directly.
    call s_parse_name; test edx,edx; jnz .spit_fail
    lea r10,[rip+s_iter_state_type_ptr]; mov [r10+rbx*8],rax
    lea r10,[rip+s_iter_state_type_len]; mov [r10+rbx*8],rcx
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spit_fail
    lea r10,[rip+s_iter_state_init_ast]; mov [r10+rbx*8],rax
    # State becomes visible after its initializer, matching current surface semantics.
    mov rdi,r14; mov rsi,r15; call s_state_add
    inc ebx; call s_optional_semicolon; jmp .spit_member
.spit_while:
    cmp qword ptr [rip+s_iter_condition_ast],0; jne .spit_fail
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spit_fail
    mov [rip+s_iter_condition_ast],rax; call s_optional_semicolon; jmp .spit_member
.spit_update:
    mov eax,dword ptr [rip+s_iter_update_count]; cmp eax,SCOPE_MAX; jae .spit_fail
    call s_parse_name; test edx,edx; jnz .spit_fail
    mov r14,rax; mov r15,rcx
    mov eax,dword ptr [rip+s_iter_update_count]
    lea r10,[rip+s_iter_update_name_ptr]; mov [r10+rax*8],r14
    lea r10,[rip+s_iter_update_name_len]; mov [r10+rax*8],r15
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spit_fail
    mov ecx,dword ptr [rip+s_iter_update_count]
    lea r10,[rip+s_iter_update_ast]; mov [r10+rcx*8],rax
    inc dword ptr [rip+s_iter_update_count]
    call s_optional_semicolon; jmp .spit_member
.spit_result:
    cmp qword ptr [rip+s_iter_result_ptr],0; jne .spit_fail
    call s_parse_name; test edx,edx; jnz .spit_fail
    mov [rip+s_iter_result_ptr],rax; mov [rip+s_iter_result_len],rcx
    call s_optional_semicolon; jmp .spit_member
.spit_members_done:
    test ebx,ebx; jz .spit_fail
    cmp qword ptr [rip+s_iter_condition_ast],0; je .spit_fail
    cmp qword ptr [rip+s_iter_result_ptr],0; je .spit_fail
    # Emit collected iterate object fields.
    xor r14d,r14d
.spit_emit_states:
    cmp r14d,ebx; jae .spit_states_done
    test r14d,r14d; jz .spit_state_nocomma2
    mov dil,','; call s_out_byte
.spit_state_nocomma2:
    lea rdi,[rip+js_state_obj_name]; call s_out_cstr
    lea rax,[rip+s_iter_state_name_ptr]; mov rdi,[rax+r14*8]
    lea rax,[rip+s_iter_state_name_len]; mov rsi,[rax+r14*8]; call s_out_quote_span
    lea rdi,[rip+js_type_key]; call s_out_cstr
    lea rax,[rip+s_iter_state_type_ptr]; mov rdi,[rax+r14*8]
    lea rax,[rip+s_iter_state_type_len]; mov rsi,[rax+r14*8]; call s_out_quote_span
    lea rdi,[rip+js_init_key]; call s_out_cstr
    lea rax,[rip+s_iter_state_init_ast]; mov rdi,[rax+r14*8]; call s_emit_ast
    mov dil,'}'; call s_out_byte
    inc r14d; jmp .spit_emit_states
.spit_states_done:
    lea rdi,[rip+js_condition_mid]; call s_out_cstr
    mov rdi,[rip+s_iter_condition_ast]; call s_emit_ast
    lea rdi,[rip+js_update_mid]; call s_out_cstr
    xor r14d,r14d
.spit_emit_updates:
    cmp r14d,dword ptr [rip+s_iter_update_count]; jae .spit_updates_done
    test r14d,r14d; jz .spit_up_nocomma
    mov dil,','; call s_out_byte
.spit_up_nocomma:
    lea rax,[rip+s_iter_update_name_ptr]; mov rdi,[rax+r14*8]
    lea rax,[rip+s_iter_update_name_len]; mov rsi,[rax+r14*8]; call s_out_quote_span
    mov dil,':'; call s_out_byte
    lea rax,[rip+s_iter_update_ast]; mov rdi,[rax+r14*8]; call s_emit_ast
    inc r14d; jmp .spit_emit_updates
.spit_updates_done:
    lea rdi,[rip+js_result_mid]; call s_out_cstr
    mov rdi,[rip+s_iter_result_ptr]; mov rsi,[rip+s_iter_result_len]; call s_out_quote_span
    lea rdi,[rip+js_maxiter_mid]; call s_out_cstr
    mov rdi,[rip+s_iter_limit_ast]; call s_emit_ast
    mov dil,'}'; call s_out_byte
    call s_commit_bindings; call s_state_scope_clear; call s_optional_semicolon; xor eax,eax; ret
.spit_fail:
    mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_tensor_decl:
    # Legacy WH tensor/reduce surface remains in the sovereign general lane;
    # structural WH `for` is the explicit topology-recovery spelling.
    mov dword ptr [rip+s_general_lane],1
    # WH tensor map.
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .sptn_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .sptn_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_map_mid_axes]; call s_out_cstr
    call s_parse_wh_axes_emit; test eax,eax; jnz .sptn_fail
    lea rdi,[rip+js_type_key]; call s_out_cstr
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_type_emit; test eax,eax; jz .sptn_fail
    lea rdi,[rip+js_expr_key]; call s_out_cstr
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sptn_fail
    mov rdi,rax; call s_emit_ast
    mov dil,'}'; call s_out_byte; call s_commit_bindings; call s_axis_scope_clear; call s_optional_semicolon; xor eax,eax; ret
.sptn_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_reduce_decl:
    mov dword ptr [rip+s_general_lane],1
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .sprd_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .sprd_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_reduce_mid_axes]; call s_out_cstr
    call s_parse_wh_axes_emit; test eax,eax; jnz .sprd_fail
    lea rdi,[rip+js_acc_key]; call s_out_cstr
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_type_emit; test eax,eax; jz .sprd_fail
    lea rdi,[rip+js_reduce_kind_mid]; call s_out_cstr
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sprd_fail
    mov rdi,rax; mov rsi,rcx; mov edx,KID_SUM; call s_span_kw_id; test eax,eax; jz .sprd_fail
    lea rdi,[rip+kw_sum]; mov esi,3; call s_out_quote_span
    lea rdi,[rip+js_expr_key]; call s_out_cstr
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sprd_fail
    mov rdi,rax; call s_emit_ast
    mov dil,'}'; call s_out_byte; call s_commit_bindings; call s_axis_scope_clear; call s_optional_semicolon; xor eax,eax; ret
.sprd_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

# -----------------------------------------------------------------------------
# WHEX declarations (field/sum/tolerance)
# -----------------------------------------------------------------------------
s_parse_tolerance_decl:
    call s_parse_number_span; test edx,edx; jnz .sptol_fail
    mov [rip+s_tol_ptr],rax; mov [rip+s_tol_len],rcx
    mov dword ptr [rip+s_fp_tolerant],1
    call s_optional_semicolon; xor eax,eax; ret
.sptol_fail: mov eax,1; ret

s_parse_strict_decl:
    mov dword ptr [rip+s_fp_tolerant],0
    mov qword ptr [rip+s_tol_ptr],0; mov qword ptr [rip+s_tol_len],0
    call s_optional_semicolon; xor eax,eax; ret

s_parse_whex_field:
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .spwf_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spwf_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_map_mid_axes]; call s_out_cstr
    call s_parse_whex_axes_record; test eax,eax; jnz .spwf_fail
    call s_prepare_rankn_layout
    cmp eax,-1; je .spwf_fail
    mov r14d,eax
    # Rank-N is materialized as one product axis. This is dimensional
    # dataization, never nested sequential loops.
    mov dil,'['; call s_out_byte; lea rdi,[rip+js_axis_obj_name]; call s_out_cstr
    test r14d,r14d; jz .spwf_rank1_axis
    lea rdi,[rip+rank_q_name]; mov esi,11; call s_out_quote_span; jmp .spwf_axis_extent
.spwf_rank1_axis:
    lea rax,[rip+s_rank_axis_ptrs]; mov rdi,[rax]; lea rax,[rip+s_rank_axis_lens]; mov rsi,[rax]; call s_out_quote_span
.spwf_axis_extent:
    lea rdi,[rip+js_extent_var_n]; call s_out_cstr
    lea rdi,[rip+js_type_key]; call s_out_cstr
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_type_emit; cmp eax,5; jne .spwf_fail
    lea rdi,[rip+js_expr_key]; call s_out_cstr
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spwf_fail
    test r14d,r14d; jz .spwf_emit_expr
    mov rdi,rax; call s_rankn_rewrite; test rax,rax; jz .spwf_fail
.spwf_emit_expr:
    mov rdi,rax; call s_emit_ast; test eax,eax; jnz .spwf_fail
    mov dil,'}'; call s_out_byte; call s_commit_bindings
    test r14d,r14d; jz .spwf_no_rankmeta
    mov dword ptr [rip+s_rankn_active],1
    mov eax,dword ptr [rip+s_rank_count]; mov [rip+s_rankn_source_rank],eax
    mov rax,[rip+s_rank_static_factor]; mov [rip+s_rankn_product],rax
.spwf_no_rankmeta:
    call s_axis_scope_clear; call s_optional_semicolon; xor eax,eax; ret
.spwf_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

# WHEX `each i in n { name: type = expr }` is structural map spelling only.
# It lowers to the same map node as `field`; no loop object survives.
s_parse_whex_each:
    call s_axis_scope_clear
    mov dword ptr [rip+s_rank_count],0
.spwe_axis_loop:
    call s_parse_name; test edx,edx; jnz .spwe_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_axis_add
    mov ebx,dword ptr [rip+s_rank_count]; cmp ebx,RANK_MAX; jae .spwe_fail
    lea rax,[rip+s_rank_axis_ptrs]; mov [rax+rbx*8],r12
    lea rax,[rip+s_rank_axis_lens]; mov [rax+rbx*8],r13
    mov edi,KID_IN; call s_expect_kw_id
    call s_skip
    mov r8,[rip+s_cur]; cmp r8,[rip+s_end]; jae .spwe_fail
    mov al,[r8]; cmp al,'0'; jb .spwe_extent_name; cmp al,'9'; jbe .spwe_extent_num
.spwe_extent_name:
    call s_parse_name; test edx,edx; jnz .spwe_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+name_n]; mov ecx,1; call s_span_eq; test eax,eax; jz .spwe_fail
    lea rax,[rip+s_rank_dynamic]; mov dword ptr [rax+rbx*4],1
    lea rax,[rip+s_rank_extent]; mov qword ptr [rax+rbx*8],0
    jmp .spwe_extent_done
.spwe_extent_num:
    call s_parse_number_span; test edx,edx; jnz .spwe_fail
    xor r14,r14; xor r15d,r15d
.spwe_numconv:
    cmp r15,rcx; jae .spwe_numok
    movzx edx,byte ptr [rax+r15]; cmp dl,'0'; jb .spwe_fail; cmp dl,'9'; ja .spwe_fail
    imul r14,r14,10; sub edx,'0'; add r14,rdx; inc r15; jmp .spwe_numconv
.spwe_numok:
    test r14,r14; jz .spwe_fail
    mov rdx,r14; dec rdx; test r14,rdx; jnz .spwe_fail
    lea rdx,[rip+s_rank_dynamic]; mov dword ptr [rdx+rbx*4],0
    lea rdx,[rip+s_rank_extent]; mov [rdx+rbx*8],r14
.spwe_extent_done:
    inc dword ptr [rip+s_rank_count]
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spwe_axis_loop
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
    cmp dword ptr [rip+s_error],0; jne .spwe_fail
    call s_prepare_rankn_layout; cmp eax,-1; je .spwe_fail
    mov r14d,eax
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .spwe_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spwe_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_map_mid_axes]; call s_out_cstr
    mov dil,'['; call s_out_byte; lea rdi,[rip+js_axis_obj_name]; call s_out_cstr
    test r14d,r14d; jz .spwe_rank1_axis
    lea rdi,[rip+rank_q_name]; mov esi,11; call s_out_quote_span; jmp .spwe_axis_extent
.spwe_rank1_axis:
    lea rax,[rip+s_rank_axis_ptrs]; mov rdi,[rax]; lea rax,[rip+s_rank_axis_lens]; mov rsi,[rax]; call s_out_quote_span
.spwe_axis_extent:
    lea rdi,[rip+js_extent_var_n]; call s_out_cstr
    lea rdi,[rip+js_type_key]; call s_out_cstr
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_type_emit; cmp eax,5; jne .spwe_fail
    lea rdi,[rip+js_expr_key]; call s_out_cstr
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spwe_fail
    test r14d,r14d; jz .spwe_emit_expr
    mov rdi,rax; call s_rankn_rewrite; test rax,rax; jz .spwe_fail
.spwe_emit_expr:
    mov rdi,rax; call s_emit_ast; test eax,eax; jnz .spwe_fail
    mov dil,'}'; call s_out_byte; call s_commit_bindings
    test r14d,r14d; jz .spwe_no_rankmeta
    mov dword ptr [rip+s_rankn_active],1
    mov eax,dword ptr [rip+s_rank_count]; mov [rip+s_rankn_source_rank],eax
    mov rax,[rip+s_rank_static_factor]; mov [rip+s_rankn_product],rax
.spwe_no_rankmeta:
    call s_optional_semicolon
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_expect_token
    call s_optional_semicolon
    call s_axis_scope_clear
    cmp dword ptr [rip+s_error],0; jne .spwe_fail
    xor eax,eax; ret
.spwe_fail:
    mov dword ptr [rip+s_error],1; mov eax,1; ret

s_emit_whex_accumulator:
    lea rdi,[rip+js_acc_tol_prefix]; call s_out_cstr
    cmp dword ptr [rip+s_fp_tolerant],0; je .sewa_zero
    mov rdi,[rip+s_tol_ptr]; mov rsi,[rip+s_tol_len]; test rdi,rdi; jz .sewa_zero
    call s_out_span; jmp .sewa_rel
.sewa_zero: lea rdi,[rip+num_zero_float]; call s_out_cstr
.sewa_rel:
    lea rdi,[rip+js_acc_tol_rel]; call s_out_cstr
    cmp dword ptr [rip+s_fp_tolerant],0; je .sewa_zero2
    mov rdi,[rip+s_tol_ptr]; mov rsi,[rip+s_tol_len]; test rdi,rdi; jz .sewa_zero2
    call s_out_span; jmp .sewa_close
.sewa_zero2: lea rdi,[rip+num_zero_float]; call s_out_cstr
.sewa_close: mov dil,'}'; call s_out_byte; ret

s_parse_whex_sum:
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    call s_parse_name; test edx,edx; jnz .spws_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spws_fail
    mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_reduce_mid_axes]; call s_out_cstr
    call s_parse_whex_axes_record; test eax,eax; jnz .spws_fail
    call s_prepare_rankn_layout
    cmp eax,-1; je .spws_fail
    mov r14d,eax                    # 1 rank-N, 0 rank1
    # Emit physical axis list.
    mov dil,'['; call s_out_byte; lea rdi,[rip+js_axis_obj_name]; call s_out_cstr
    test r14d,r14d; jz .spws_rank1_axis
    lea rdi,[rip+rank_q_name]; mov esi,11; call s_out_quote_span; jmp .spws_axis_extent
.spws_rank1_axis:
    lea rax,[rip+s_rank_axis_ptrs]; mov rdi,[rax]; lea rax,[rip+s_rank_axis_lens]; mov rsi,[rax]; call s_out_quote_span
.spws_axis_extent:
    lea rdi,[rip+js_extent_var_n]; call s_out_cstr
    lea rdi,[rip+js_acc_key]; call s_out_cstr
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    # WHEX native sum requires f64 source spelling.
    call s_parse_name; test edx,edx; jnz .spws_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+ty_f64]; mov ecx,3; call s_span_eq; test eax,eax; jz .spws_fail
    call s_emit_whex_accumulator
    lea rdi,[rip+js_reduce_sum_expr]; call s_out_cstr
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spws_fail
    test r14d,r14d; jz .spws_emit_expr
    mov rdi,rax; call s_rankn_rewrite; test rax,rax; jz .spws_fail
.spws_emit_expr:
    mov rdi,rax; call s_emit_ast; test eax,eax; jnz .spws_fail
    mov dil,'}'; call s_out_byte; call s_commit_bindings
    test r14d,r14d; jz .spws_no_rankmeta
    mov dword ptr [rip+s_rankn_active],1
    mov eax,dword ptr [rip+s_rank_count]; mov [rip+s_rankn_source_rank],eax
    mov rax,[rip+s_rank_static_factor]; mov [rip+s_rankn_product],rax
.spws_no_rankmeta:
    call s_axis_scope_clear; call s_optional_semicolon; xor eax,eax; ret
.spws_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret



# WH structural `for` lowers directly into tensor/reduction data axes. No loop
# object survives into the canonical graph.
s_parse_for_axes_record:
    call s_axis_scope_clear
    mov dword ptr [rip+s_rank_count],0
.spfa_loop:
    call s_parse_name; test edx,edx; jnz .spfa_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_axis_add
    mov ebx,dword ptr [rip+s_rank_count]; cmp ebx,RANK_MAX; jae .spfa_fail
    lea rax,[rip+s_rank_axis_ptrs]; mov [rax+rbx*8],r12
    lea rax,[rip+s_rank_axis_lens]; mov [rax+rbx*8],r13
    mov edi,KID_IN; call s_expect_kw_id
    call s_skip
    # optional zero-based half-open 0..extent
    mov r8,[rip+s_cur]
    cmp r8,[rip+s_end]; jae .spfa_fail
    cmp byte ptr [r8],'0'; jne .spfa_extent
    lea r9,[r8+1]; cmp r9,[rip+s_end]; jae .spfa_extent
    cmp byte ptr [r8+1],'.'; jne .spfa_extent
    lea r9,[r8+2]; cmp r9,[rip+s_end]; jae .spfa_extent
    cmp byte ptr [r8+2],'.'; jne .spfa_extent
    add qword ptr [rip+s_cur],3
.spfa_extent:
    call s_skip
    mov r8,[rip+s_cur]; cmp r8,[rip+s_end]; jae .spfa_fail
    mov al,[r8]; cmp al,'0'; jb .spfa_extent_name; cmp al,'9'; jbe .spfa_extent_num
.spfa_extent_name:
    call s_parse_name; test edx,edx; jnz .spfa_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+name_n]; mov ecx,1; call s_span_eq
    test eax,eax; jz .spfa_fail
    lea rax,[rip+s_rank_dynamic]; mov dword ptr [rax+rbx*4],1
    lea rax,[rip+s_rank_extent]; mov qword ptr [rax+rbx*8],0
    jmp .spfa_extent_done
.spfa_extent_num:
    call s_parse_number_span; test edx,edx; jnz .spfa_fail
    xor r14,r14; xor r15d,r15d
.spfa_numconv:
    cmp r15,rcx; jae .spfa_numok
    movzx edx,byte ptr [rax+r15]; cmp dl,'0'; jb .spfa_fail; cmp dl,'9'; ja .spfa_fail
    imul r14,r14,10; sub edx,'0'; add r14,rdx; inc r15; jmp .spfa_numconv
.spfa_numok:
    test r14,r14; jz .spfa_fail
    mov rdx,r14; dec rdx; test r14,rdx; jnz .spfa_fail
    lea rdx,[rip+s_rank_dynamic]; mov dword ptr [rdx+rbx*4],0
    lea rdx,[rip+s_rank_extent]; mov [rdx+rbx*8],r14
.spfa_extent_done:
    inc dword ptr [rip+s_rank_count]
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spfa_loop
    xor eax,eax; ret
.spfa_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

# Verify [i,j,...] exactly names the declared for axes.
s_expect_for_index_tuple:
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_expect_token
    xor ebx,ebx
.sefit_loop:
    cmp ebx,dword ptr [rip+s_rank_count]; jae .sefit_close
    call s_parse_name; test edx,edx; jnz .sefit_fail
    lea rdx,[rip+s_rank_axis_ptrs]; mov rdi,[rdx+rbx*8]
    lea rdx,[rip+s_rank_axis_lens]; mov rsi,[rdx+rbx*8]
    mov rdx,rax; call s_span_eq; test eax,eax; jz .sefit_fail
    inc ebx
    cmp ebx,dword ptr [rip+s_rank_count]; jae .sefit_close
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    jmp .sefit_loop
.sefit_close:
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
    xor eax,eax; ret
.sefit_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_emit_for_physical_axis:
    # r14d=rankn flag. Emits one physical axis, productized when rank>1.
    mov dil,'['; call s_out_byte; lea rdi,[rip+js_axis_obj_name]; call s_out_cstr
    test r14d,r14d; jz .sefpa_rank1
    lea rdi,[rip+rank_q_name]; mov esi,11; call s_out_quote_span; jmp .sefpa_extent
.sefpa_rank1:
    lea rax,[rip+s_rank_axis_ptrs]; mov rdi,[rax]; lea rax,[rip+s_rank_axis_lens]; mov rsi,[rax]; call s_out_quote_span
.sefpa_extent:
    lea rdi,[rip+js_extent_var_n]; call s_out_cstr
    ret

s_mark_rankn_metadata:
    test r14d,r14d; jz .smrm_done
    mov dword ptr [rip+s_rankn_active],1
    mov eax,dword ptr [rip+s_rank_count]; mov [rip+s_rankn_source_rank],eax
    mov rax,[rip+s_rank_static_factor]; mov [rip+s_rankn_product],rax
.smrm_done: ret

s_parse_wh_for:
    call s_parse_for_axes_record; test eax,eax; jnz .spfor_fail
    call s_prepare_rankn_layout; cmp eax,-1; je .spfor_fail; mov r14d,eax
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
    # optional familiar let
    mov edi,KID_LET; call s_match_kw_id
    call s_parse_name; test edx,edx; jnz .spfor_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spfor_fail
    # Element assignment if an index tuple follows the target.
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spfor_reduce
    # opening '[' already consumed, validate tuple manually.
    xor ebx,ebx
.spfor_idx_loop:
    cmp ebx,dword ptr [rip+s_rank_count]; jae .spfor_idx_close
    call s_parse_name; test edx,edx; jnz .spfor_fail
    lea rdx,[rip+s_rank_axis_ptrs]; mov rdi,[rdx+rbx*8]
    lea rdx,[rip+s_rank_axis_lens]; mov rsi,[rdx+rbx*8]
    mov rdx,rax; call s_span_eq; test eax,eax; jz .spfor_fail
    inc ebx
    cmp ebx,dword ptr [rip+s_rank_count]; jae .spfor_idx_close
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_expect_token
    jmp .spfor_idx_loop
.spfor_idx_close:
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .spfor_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+ty_f64]; mov ecx,3; call s_span_eq; test eax,eax; jz .spfor_fail
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spfor_fail
    test r14d,r14d; jz .spfor_map_ast
    mov rdi,rax; call s_rankn_rewrite; test rax,rax; jz .spfor_fail
.spfor_map_ast: mov r15,rax
    call s_optional_semicolon
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_expect_token
    # emit map after parsing body
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr; mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_map_mid_axes]; call s_out_cstr; call s_emit_for_physical_axis
    lea rdi,[rip+js_type_key]; call s_out_cstr; lea rdi,[rip+ty_f64]; mov esi,3; call s_out_quote_span
    lea rdi,[rip+js_expr_key]; call s_out_cstr; mov rdi,r15; call s_emit_ast
    mov dil,'}'; call s_out_byte; call s_commit_bindings; call s_mark_rankn_metadata
    call s_axis_scope_clear; call s_optional_semicolon; xor eax,eax; ret
.spfor_reduce:
    # Optional explicit f64 accumulator.
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spfor_plus
    call s_parse_name; test edx,edx; jnz .spfor_fail
    mov rdi,rax; mov rsi,rcx; lea rdx,[rip+ty_f64]; mov ecx,3; call s_span_eq; test eax,eax; jz .spfor_fail
.spfor_plus:
    lea rdi,[rip+tok_plus]; mov esi,1; xor edx,edx; call s_expect_token
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spfor_fail
    test r14d,r14d; jz .spfor_red_ast
    mov rdi,rax; call s_rankn_rewrite; test rax,rax; jz .spfor_fail
.spfor_red_ast: mov r15,rax
    call s_optional_semicolon
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_expect_token
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr; mov rdi,r12; mov rsi,r13; call s_out_quote_span
    lea rdi,[rip+js_reduce_mid_axes]; call s_out_cstr; call s_emit_for_physical_axis
    lea rdi,[rip+js_acc_key]; call s_out_cstr; call s_emit_whex_accumulator
    lea rdi,[rip+js_reduce_sum_expr]; call s_out_cstr; mov rdi,r15; call s_emit_ast
    mov dil,'}'; call s_out_byte; call s_commit_bindings; call s_mark_rankn_metadata
    call s_axis_scope_clear; call s_optional_semicolon; xor eax,eax; ret
.spfor_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_wh_region:
    call s_parse_name; test edx,edx; jnz .spwhr_fail
    mov edi,KID_EFFECT; call s_expect_kw_id
    call s_parse_name; test edx,edx; jnz .spwhr_fail
    mov rdi,rax; mov rsi,rcx; mov edx,KID_PURE; call s_span_kw_id; test eax,eax; jz .spwhr_fail
    mov edi,KID_PARALLEL; call s_expect_kw_id
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
.spwhr_loop:
    call s_skip
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spwhr_done
    mov edi,KID_FOR; call s_match_kw_id; test eax,eax; jnz .spwhr_for
    mov edi,KID_FIELD; call s_match_kw_id; test eax,eax; jnz .spwhr_field
    mov edi,KID_SUM; call s_match_kw_id; test eax,eax; jnz .spwhr_sum
    mov edi,KID_WHILE; call s_match_kw_id; test eax,eax; jnz .spwhr_fail
    jmp .spwhr_fail
.spwhr_for: call s_parse_wh_for; test eax,eax; jnz .spwhr_fail; jmp .spwhr_loop
.spwhr_field: call s_parse_whex_field; test eax,eax; jnz .spwhr_fail; jmp .spwhr_loop
.spwhr_sum: call s_parse_whex_sum; test eax,eax; jnz .spwhr_fail; jmp .spwhr_loop
.spwhr_done: call s_optional_semicolon; xor eax,eax; ret
.spwhr_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

# WHEX semantic wrappers are compile-time topology declarations. They carry no
# execution resource ownership and therefore erase before native physicalization.
s_parse_whex_axis_decl:
    call s_parse_name; test edx,edx; jnz .spwad_fail
    mov edi,KID_IN; call s_expect_kw_id
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spwad_fail
    call s_optional_semicolon
    xor eax,eax; ret
.spwad_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_whex_region:
    # region NAME effect pure parallel { field/sum ... }
    call s_parse_name; test edx,edx; jnz .spwr_fail
    mov edi,KID_EFFECT; call s_expect_kw_id
    call s_parse_name; test edx,edx; jnz .spwr_fail
    mov rdi,rax; mov rsi,rcx; mov edx,KID_PURE; call s_span_kw_id
    test eax,eax; jz .spwr_fail
    mov edi,KID_PARALLEL; call s_expect_kw_id
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
.spwr_loop:
    call s_skip
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spwr_done
    mov edi,KID_FIELD; call s_match_kw_id; test eax,eax; jnz .spwr_field
    mov edi,KID_SUM; call s_match_kw_id; test eax,eax; jnz .spwr_sum
    jmp .spwr_fail
.spwr_field: call s_parse_whex_field; test eax,eax; jnz .spwr_fail; jmp .spwr_loop
.spwr_sum: call s_parse_whex_sum; test eax,eax; jnz .spwr_fail; jmp .spwr_loop
.spwr_done: call s_optional_semicolon; xor eax,eax; ret
.spwr_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

# -----------------------------------------------------------------------------
# Compile-time semantic abstraction tables: records and pure functions.
# Nothing here survives into runtime machine code.
# -----------------------------------------------------------------------------
s_record_lookup:
    # rdi=record ptr,rsi=len,rdx=field ptr,rcx=len -> rax AST/0
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi; mov r13,rdx; mov r14,rcx; xor r15d,r15d
.srl_loop:
    cmp r15d,dword ptr [rip+s_record_field_count]; jae .srl_no
    lea rax,[rip+s_record_name_ptr]; mov rdi,[rax+r15*8]
    lea rax,[rip+s_record_name_len]; mov rsi,[rax+r15*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jz .srl_next
    lea rax,[rip+s_record_field_ptr]; mov rdi,[rax+r15*8]
    lea rax,[rip+s_record_field_len]; mov rsi,[rax+r15*8]
    mov rdx,r13; mov rcx,r14; call s_span_eq; test eax,eax; jz .srl_next
    lea rax,[rip+s_record_value_ast]; mov rax,[rax+r15*8]; jmp .srl_done
.srl_next: inc r15d; jmp .srl_loop
.srl_no: xor eax,eax
.srl_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_function_lookup:
    # rdi=name,rsi=len -> eax index or -1
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.sfl_loop:
    cmp r13d,dword ptr [rip+s_function_count]; jae .sfl_no
    lea rax,[rip+s_function_name_ptr]; mov rdi,[rax+r13*8]
    lea rax,[rip+s_function_name_len]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .sfl_yes
    inc r13d; jmp .sfl_loop
.sfl_yes: mov eax,r13d; jmp .sfl_done
.sfl_no: mov eax,-1
.sfl_done: pop r13; pop r12; pop rbx; ret

s_clone_subst:
    # rdi=node,rsi=param ptr,rdx=param len,rcx=argument AST -> rax clone/arg
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; mov r12,rsi; mov r13,rdx; mov r14,rcx
    test rbx,rbx; jz .scs_null
    cmp dword ptr [rbx+SN_KIND],NK_VAR; jne .scs_clone
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; mov rdx,r12; mov rcx,r13; call s_span_eq
    test eax,eax; jnz .scs_arg
.scs_clone:
    call s_new_ast; test rax,rax; jz .scs_null
    mov r15,rax
    movdqu xmm0,[rbx]; movdqu [r15],xmm0
    movdqu xmm0,[rbx+16]; movdqu [r15+16],xmm0
    movdqu xmm0,[rbx+32]; movdqu [r15+32],xmm0
    movdqu xmm0,[rbx+48]; movdqu [r15+48],xmm0
    mov rdi,[rbx+SN_A]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst; mov [r15+SN_A],rax
    mov rdi,[rbx+SN_B]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst; mov [r15+SN_B],rax
    mov rdi,[rbx+SN_C]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst; mov [r15+SN_C],rax
    mov rdi,[rbx+SN_NEXT]; mov rsi,r12; mov rdx,r13; mov rcx,r14; call s_clone_subst; mov [r15+SN_NEXT],rax
    mov rax,r15; jmp .scs_done
.scs_arg: mov rax,r14; jmp .scs_done
.scs_null: xor eax,eax
.scs_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_parse_record_decl:
    # record NAME { FIELD = compile_time_expr ... }
    call s_parse_name; test edx,edx; jnz .sprc_fail
    mov r12,rax; mov r13,rcx
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
.sprc_loop:
    call s_skip
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sprc_done
    call s_parse_name; test edx,edx; jnz .sprc_fail
    mov r14,rax; mov r15,rcx
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sprc_fail
    mov ebx,dword ptr [rip+s_record_field_count]; cmp ebx,64; jae .sprc_fail
    lea rdx,[rip+s_record_name_ptr]; mov [rdx+rbx*8],r12
    lea rdx,[rip+s_record_name_len]; mov [rdx+rbx*8],r13
    lea rdx,[rip+s_record_field_ptr]; mov [rdx+rbx*8],r14
    lea rdx,[rip+s_record_field_len]; mov [rdx+rbx*8],r15
    lea rdx,[rip+s_record_value_ast]; mov [rdx+rbx*8],rax
    inc dword ptr [rip+s_record_field_count]
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .sprc_loop
    call s_optional_semicolon
    jmp .sprc_loop
.sprc_done: call s_optional_semicolon; xor eax,eax; ret
.sprc_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_pure_function:
    # pure [generic] fn NAME(PARAM: TYPE) -> TYPE = EXPR
    mov edi,KID_GENERIC; call s_match_kw_id
    mov edi,KID_FN; call s_match_kw_id; test eax,eax; jz .sppf_fail
    call s_parse_name; test edx,edx; jnz .sppf_fail
    mov r12,rax; mov r13,rcx
    lea rdi,[rip+tok_lparen]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sppf_fail
    mov r14,rax; mov r15,rcx
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sppf_fail  # parameter type validated by native backend after expansion
    lea rdi,[rip+tok_rparen]; mov esi,1; xor edx,edx; call s_expect_token
    lea rdi,[rip+tok_arrowthin]; mov esi,2; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .sppf_fail  # return type
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .sppf_fail
    mov ebx,dword ptr [rip+s_function_count]; cmp ebx,16; jae .sppf_fail
    lea rdx,[rip+s_function_name_ptr]; mov [rdx+rbx*8],r12
    lea rdx,[rip+s_function_name_len]; mov [rdx+rbx*8],r13
    lea rdx,[rip+s_function_param_ptr]; mov [rdx+rbx*8],r14
    lea rdx,[rip+s_function_param_len]; mov [rdx+rbx*8],r15
    lea rdx,[rip+s_function_expr_ast]; mov [rdx+rbx*8],rax
    inc dword ptr [rip+s_function_count]
    call s_optional_semicolon; xor eax,eax; ret
.sppf_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret


# -----------------------------------------------------------------------------
# Closed static abstractions: dictionary / nested / cascade.
# These structures exist only while compiling. They never become runtime
# objects, queues, schedulers, hash tables, or resource owners.
# -----------------------------------------------------------------------------
s_ast_closed:
    # rdi=node -> eax=1 iff no runtime reference occurs anywhere below it.
    push rbx
    mov rbx,rdi
    test rbx,rbx; jz .sac_no
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_NUM; je .sac_yes
    cmp eax,NK_STRING; je .sac_yes
    cmp eax,NK_BOOL; je .sac_yes
    cmp eax,NK_IMM_U64; je .sac_yes
    cmp eax,NK_VAR; je .sac_no
    cmp eax,NK_AXIS; je .sac_no
    cmp eax,NK_STATE; je .sac_no
    cmp eax,NK_LOAD; je .sac_no
    cmp eax,NK_GOAL_RESULT; je .sac_no
    cmp eax,NK_CAST; je .sac_one
    cmp eax,NK_UNARY; je .sac_one
    cmp eax,NK_BINARY; jne .sac_no
    mov rdi,[rbx+SN_A]; call s_ast_closed; test eax,eax; jz .sac_no
    mov rdi,[rbx+SN_B]; call s_ast_closed; test eax,eax; jz .sac_no
    mov rdi,[rbx+SN_C]; test rdi,rdi; jz .sac_yes
    call s_ast_closed; test eax,eax; jz .sac_no
    jmp .sac_yes
.sac_one:
    mov rdi,[rbx+SN_A]; call s_ast_closed; test eax,eax; jz .sac_no
.sac_yes: mov eax,1; pop rbx; ret
.sac_no: xor eax,eax; pop rbx; ret

s_emit_compute_ast:
    # rdi=name ptr,rsi=len,rdx=AST. Emits an ordinary compute binding.
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; mov r13,rdx
    mov dword ptr [rip+s_general_lane],1
    mov rdi,rbx; mov rsi,r12; call s_decl_add; test eax,eax; jnz .seca_fail
    call s_stream_bindings; lea rdi,[rip+s_binding_count]; call s_item_prefix
    lea rdi,[rip+js_binding_name]; call s_out_cstr
    mov rdi,rbx; mov rsi,r12; call s_out_quote_span
    lea rdi,[rip+js_compute_prefix]; call s_out_cstr
    lea rdi,[rip+js_expr_key]; call s_out_cstr
    mov rdi,r13; call s_emit_ast; test eax,eax; jnz .seca_fail
    mov dil,'}'; call s_out_byte; call s_commit_bindings
    xor eax,eax; jmp .seca_done
.seca_fail: mov dword ptr [rip+s_error],1; mov eax,1
.seca_done: pop r13; pop r12; pop rbx; ret

s_static_key_equal:
    # rdi=a AST,rsi=b AST -> eax bool. Only literal keys are comparable.
    push rbx; push r12
    mov rbx,rdi; mov r12,rsi
    test rbx,rbx; jz .sske_no
    test r12,r12; jz .sske_no
    mov eax,dword ptr [rbx+SN_KIND]; cmp eax,dword ptr [r12+SN_KIND]; jne .sske_no
    cmp eax,NK_BOOL; je .sske_aux
    cmp eax,NK_IMM_U64; je .sske_aux
    cmp eax,NK_NUM; je .sske_span_aux
    cmp eax,NK_STRING; je .sske_span
    jmp .sske_no
.sske_aux:
    mov rax,[rbx+SN_AUX]; cmp rax,[r12+SN_AUX]; sete al; movzx eax,al; jmp .sske_done
.sske_span_aux:
    mov rax,[rbx+SN_AUX]; cmp rax,[r12+SN_AUX]; jne .sske_no
.sske_span:
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]
    mov rdx,[r12+SN_PTR]; mov rcx,[r12+SN_LEN]; call s_span_eq; jmp .sske_done
.sske_no: xor eax,eax
.sske_done: pop r12; pop rbx; ret

s_dictionary_find:
    # rdi=name,rsi=len -> eax index or -1
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.sdf_loop:
    cmp r13d,dword ptr [rip+s_dictionary_count]; jae .sdf_no
    lea rax,[rip+s_dictionary_name_ptr]; mov rdi,[rax+r13*8]
    lea rax,[rip+s_dictionary_name_len]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .sdf_yes
    inc r13d; jmp .sdf_loop
.sdf_yes: mov eax,r13d; jmp .sdf_done
.sdf_no: mov eax,-1
.sdf_done: pop r13; pop r12; pop rbx; ret

s_parse_dictionary_decl:
    # dictionary name: key_type -> value_type { literal = closed_expr, ... }
    push rbx; push r12; push r13; push r14; push r15
    call s_parse_name; test edx,edx; jnz .spdd_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spdd_fail
    mov ebx,dword ptr [rip+s_dictionary_count]; cmp ebx,DICT_MAX; jae .spdd_fail
    lea rax,[rip+s_dictionary_name_ptr]; mov [rax+rbx*8],r12
    lea rax,[rip+s_dictionary_name_len]; mov [rax+rbx*8],r13
    inc dword ptr [rip+s_dictionary_count]
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .spdd_fail        # key type
    lea rdi,[rip+tok_arrowthin]; mov esi,2; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .spdd_fail        # value type
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
.spdd_loop:
    call s_skip
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spdd_done
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spdd_fail
    mov r14,rax
    mov eax,dword ptr [r14+SN_KIND]
    cmp eax,NK_STRING; je .spdd_key_ok
    cmp eax,NK_NUM; je .spdd_key_ok
    cmp eax,NK_BOOL; je .spdd_key_ok
    cmp eax,NK_IMM_U64; jne .spdd_fail
.spdd_key_ok:
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spdd_fail
    mov r15,rax; mov rdi,r15; call s_ast_closed; test eax,eax; jz .spdd_fail
    mov eax,dword ptr [rip+s_dictionary_entry_count]; cmp eax,DICT_ENTRY_MAX; jae .spdd_fail
    lea rdx,[rip+s_dictionary_entry_dict]; mov [rdx+rax*4],ebx
    lea rdx,[rip+s_dictionary_entry_key]; mov [rdx+rax*8],r14
    lea rdx,[rip+s_dictionary_entry_value]; mov [rdx+rax*8],r15
    inc dword ptr [rip+s_dictionary_entry_count]
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    call s_optional_semicolon
    jmp .spdd_loop
.spdd_done: call s_optional_semicolon; xor eax,eax; jmp .spdd_exit
.spdd_fail: mov dword ptr [rip+s_error],1; mov eax,1
.spdd_exit: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_parse_lookup_decl:
    # lookup result = dictionary[literal] default closed_expr
    push rbx; push r12; push r13; push r14; push r15
    call s_parse_name; test edx,edx; jnz .splu_fail
    mov r12,rax; mov r13,rcx
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .splu_fail
    mov rdi,rax; mov rsi,rcx; call s_dictionary_find; cmp eax,-1; je .splu_fail
    mov ebx,eax
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .splu_fail
    mov r14,rax
    mov eax,dword ptr [r14+SN_KIND]
    cmp eax,NK_STRING; je .splu_key_ok
    cmp eax,NK_NUM; je .splu_key_ok
    cmp eax,NK_BOOL; je .splu_key_ok
    cmp eax,NK_IMM_U64; jne .splu_fail
.splu_key_ok:
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
    mov edi,KID_DEFAULT; call s_expect_kw_id
    xor edi,edi; call s_parse_expr; test rax,rax; jz .splu_fail
    mov r15,rax; mov rdi,r15; call s_ast_closed; test eax,eax; jz .splu_fail
    xor ecx,ecx
.splu_scan:
    cmp ecx,dword ptr [rip+s_dictionary_entry_count]; jae .splu_emit_default
    lea rax,[rip+s_dictionary_entry_dict]; cmp dword ptr [rax+rcx*4],ebx; jne .splu_next
    push rcx
    lea rax,[rip+s_dictionary_entry_key]; mov rdi,[rax+rcx*8]; mov rsi,r14; call s_static_key_equal
    pop rcx
    test eax,eax; jnz .splu_chosen
.splu_next: inc ecx; jmp .splu_scan
.splu_chosen:
    lea rax,[rip+s_dictionary_entry_value]; mov r15,[rax+rcx*8]
.splu_emit_default:
    mov rdi,r12; mov rsi,r13; mov rdx,r15; call s_emit_compute_ast
    test eax,eax; jnz .splu_fail
    call s_optional_semicolon; xor eax,eax; jmp .splu_exit
.splu_fail: mov dword ptr [rip+s_error],1; mov eax,1
.splu_exit: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_nested_find:
    # rdi=name,rsi=len -> eax index or -1
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.snf_loop:
    cmp r13d,dword ptr [rip+s_nested_count]; jae .snf_no
    lea rax,[rip+s_nested_name_ptr]; mov rdi,[rax+r13*8]
    lea rax,[rip+s_nested_name_len]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .snf_yes
    inc r13d; jmp .snf_loop
.snf_yes: mov eax,r13d; jmp .snf_done
.snf_no: mov eax,-1
.snf_done: pop r13; pop r12; pop rbx; ret

s_parse_nested_decl:
    # nested name: type = [[closed,...], ...]
    push rbx; push r12; push r13; push r14; push r15
    call s_parse_name; test edx,edx; jnz .spnd_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spnd_fail
    mov ebx,dword ptr [rip+s_nested_count]; cmp ebx,NESTED_MAX; jae .spnd_fail
    lea rax,[rip+s_nested_name_ptr]; mov [rax+rbx*8],r12
    lea rax,[rip+s_nested_name_len]; mov [rax+rbx*8],r13
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_expect_token
    call s_parse_name; test edx,edx; jnz .spnd_fail
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_expect_token
    xor r14d,r14d                         # count
    xor r15d,r15d                         # segments
    mov qword ptr [rip+s_nested_build_sum],0
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spnd_store
.spnd_seg:
    lea rdi,[rip+tok_lbrack]; mov esi,1; xor edx,edx; call s_expect_token
    inc r15d
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spnd_seg_done
.spnd_item:
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spnd_fail
    mov [rip+s_nested_item_ast],rax
    mov rdi,rax; call s_ast_closed; test eax,eax; jz .spnd_fail
    mov r11,[rip+s_nested_item_ast]
    inc r14d
    mov r10,[rip+s_nested_build_sum]; test r10,r10; jz .spnd_first
    mov edi,OP_ADD; mov rsi,r10; mov rdx,r11; call s_ast_binary_new
    test rax,rax; jz .spnd_fail
    mov [rip+s_nested_build_sum],rax; jmp .spnd_after_add
.spnd_first: mov [rip+s_nested_build_sum],r11
.spnd_after_add:
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spnd_item
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
.spnd_seg_done:
    lea rdi,[rip+tok_comma]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spnd_seg
    lea rdi,[rip+tok_rbrack]; mov esi,1; xor edx,edx; call s_expect_token
.spnd_store:
    mov r10,[rip+s_nested_build_sum]; test r10,r10; jnz .spnd_have_sum
    xor edi,edi; call s_ast_u64_imm; mov r10,rax
.spnd_have_sum:
    lea rax,[rip+s_nested_sum_ast]; mov [rax+rbx*8],r10
    lea rax,[rip+s_nested_item_count]; mov [rax+rbx*8],r14
    lea rax,[rip+s_nested_segment_count]; mov [rax+rbx*8],r15
    inc dword ptr [rip+s_nested_count]
    call s_optional_semicolon; xor eax,eax; jmp .spnd_exit
.spnd_fail: mov dword ptr [rip+s_error],1; mov eax,1
.spnd_exit: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_parse_nested_reduce_decl:
    # nested_reduce result[:type] = sum|count|segment_count nested_name
    push rbx; push r12; push r13; push r14
    call s_parse_name; test edx,edx; jnz .spnr_fail
    mov r12,rax; mov r13,rcx
    lea rdi,[rip+tok_colon]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jz .spnr_eq
    call s_parse_name; test edx,edx; jnz .spnr_fail
.spnr_eq:
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    mov edi,KID_SUM; call s_match_kw_id; test eax,eax; jnz .spnr_sum
    call s_parse_name; test edx,edx; jnz .spnr_fail
    mov r14,rax; mov r11,rcx
    lea rdi,[rip+kw_count]; mov esi,5; mov rdx,r14; mov rcx,r11; xchg rdi,rdx; xchg rsi,rcx; call s_span_eq
    test eax,eax; jnz .spnr_count
    mov rdi,r14; mov rsi,r11; lea rdx,[rip+kw_segment_count]; mov ecx,13; call s_span_eq
    test eax,eax; jnz .spnr_segments
    jmp .spnr_fail
.spnr_sum:
    mov ebx,0; jmp .spnr_source
.spnr_count: mov ebx,1; jmp .spnr_source
.spnr_segments: mov ebx,2
.spnr_source:
    call s_parse_name; test edx,edx; jnz .spnr_fail
    mov rdi,rax; mov rsi,rcx; call s_nested_find; cmp eax,-1; je .spnr_fail
    mov r14d,eax
    cmp ebx,0; je .spnr_get_sum
    cmp ebx,1; je .spnr_get_count
    lea rax,[rip+s_nested_segment_count]; mov rdi,[rax+r14*8]; call s_ast_u64_imm; jmp .spnr_emit
.spnr_get_count:
    lea rax,[rip+s_nested_item_count]; mov rdi,[rax+r14*8]; call s_ast_u64_imm; jmp .spnr_emit
.spnr_get_sum:
    lea rax,[rip+s_nested_sum_ast]; mov rax,[rax+r14*8]
.spnr_emit:
    test rax,rax; jz .spnr_fail
    mov rdi,r12; mov rsi,r13; mov rdx,rax; call s_emit_compute_ast
    test eax,eax; jnz .spnr_fail
    call s_optional_semicolon; xor eax,eax; jmp .spnr_exit
.spnr_fail: mov dword ptr [rip+s_error],1; mov eax,1
.spnr_exit: pop r14; pop r13; pop r12; pop rbx; ret

# Parse an integer literal AST into u64. eax status in edx (0 success).
s_eval_literal_u64:
    push rbx; push r12; push r13
    mov rbx,rdi
    cmp dword ptr [rbx+SN_KIND],NK_IMM_U64; jne .selu_num
    mov rax,[rbx+SN_AUX]; xor edx,edx; jmp .selu_done
.selu_num:
    cmp dword ptr [rbx+SN_KIND],NK_BOOL; jne .selu_num2
    mov eax,dword ptr [rbx+SN_AUX]; xor edx,edx; jmp .selu_done
.selu_num2:
    cmp dword ptr [rbx+SN_KIND],NK_NUM; jne .selu_fail
    cmp qword ptr [rbx+SN_AUX],0; jne .selu_fail
    mov r12,[rbx+SN_PTR]; mov r13,[rbx+SN_LEN]
    xor eax,eax; xor ecx,ecx
.selu_loop:
    cmp rcx,r13; jae .selu_ok
    movzx edx,byte ptr [r12+rcx]; cmp dl,'0'; jb .selu_fail; cmp dl,'9'; ja .selu_fail
    sub edx,'0'
    mov r8,rax; mov r9,10; mul r9; test rdx,rdx; jnz .selu_fail
    add rax,r8              # placeholder overwritten below
    # Correct accumulation: old*10 + digit. old is unavailable after mul, so
    # keep the accumulator in r10 on the next iteration implementation.
    jmp .selu_fail
.selu_ok: xor edx,edx; jmp .selu_done
.selu_fail: xor eax,eax; mov edx,1
.selu_done: pop r13; pop r12; pop rbx; ret

# Robust decimal u64 parser directly from NK_NUM / NK_IMM / BOOL.
s_eval_literal_u64_fixed:
    push rbx; push r12; push r13; push r14
    mov rbx,rdi
    cmp dword ptr [rbx+SN_KIND],NK_IMM_U64; jne 1f
    mov rax,[rbx+SN_AUX]; xor edx,edx; jmp .self_done
1:  cmp dword ptr [rbx+SN_KIND],NK_BOOL; jne 2f
    mov eax,dword ptr [rbx+SN_AUX]; xor edx,edx; jmp .self_done
2:  cmp dword ptr [rbx+SN_KIND],NK_NUM; jne .self_fail
    cmp qword ptr [rbx+SN_AUX],0; jne .self_fail
    mov r12,[rbx+SN_PTR]; mov r13,[rbx+SN_LEN]; xor r14d,r14d
    xor eax,eax
.self_loop:
    cmp r14,r13; jae .self_ok
    movzx ecx,byte ptr [r12+r14]; cmp cl,'0'; jb .self_fail; cmp cl,'9'; ja .self_fail
    sub ecx,'0'
    mov r8,rax
    mov r9,10; mul r9; test rdx,rdx; jnz .self_fail
    add rax,rcx; jc .self_fail
    inc r14; jmp .self_loop
.self_ok: xor edx,edx; jmp .self_done
.self_fail: xor eax,eax; mov edx,1
.self_done: pop r14; pop r13; pop r12; pop rbx; ret

s_cascade_goal_find:
    # rdi=name,rsi=len -> eax index/-1
    push rbx; push r12; push r13
    mov rbx,rdi; mov r12,rsi; xor r13d,r13d
.scgf_loop:
    cmp r13d,dword ptr [rip+s_cascade_goal_count]; jae .scgf_no
    lea rax,[rip+s_cascade_goal_name_ptr]; mov rdi,[rax+r13*8]
    lea rax,[rip+s_cascade_goal_name_len]; mov rsi,[rax+r13*8]
    mov rdx,rbx; mov rcx,r12; call s_span_eq; test eax,eax; jnz .scgf_yes
    inc r13d; jmp .scgf_loop
.scgf_yes: mov eax,r13d; jmp .scgf_done
.scgf_no: mov eax,-1
.scgf_done: pop r13; pop r12; pop rbx; ret

s_eval_static_u64:
    # rdi=AST -> rax=value, edx=0 success / 1 unresolved-or-invalid.
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdi; test rbx,rbx; jz .ses_fail
    mov eax,dword ptr [rbx+SN_KIND]
    cmp eax,NK_NUM; je .ses_literal
    cmp eax,NK_IMM_U64; je .ses_literal
    cmp eax,NK_BOOL; je .ses_literal
    cmp eax,NK_AXIS; je .ses_axis
    cmp eax,NK_GOAL_RESULT; je .ses_goal
    cmp eax,NK_CAST; je .ses_one
    cmp eax,NK_UNARY; je .ses_unary
    cmp eax,NK_BINARY; jne .ses_fail
    mov rdi,[rbx+SN_A]; call s_eval_static_u64; test edx,edx; jnz .ses_fail
    mov r12,rax
    mov rdi,[rbx+SN_B]; call s_eval_static_u64; test edx,edx; jnz .ses_fail
    mov r13,rax
    mov eax,dword ptr [rbx+SN_OP]
    cmp eax,OP_SELECT; je .ses_select
    cmp eax,OP_ADD; je .ses_add
    cmp eax,OP_SUB; je .ses_sub
    cmp eax,OP_MUL; je .ses_mul
    cmp eax,OP_DIV; je .ses_div
    cmp eax,OP_MOD; je .ses_mod
    cmp eax,OP_BIT_AND; je .ses_band
    cmp eax,OP_BIT_OR; je .ses_bor
    cmp eax,OP_BIT_XOR; je .ses_bxor
    cmp eax,OP_SHL; je .ses_shl
    cmp eax,OP_SHR; je .ses_shr
    cmp eax,OP_EQ; je .ses_eq
    cmp eax,OP_NE; je .ses_ne
    cmp eax,OP_LT; je .ses_lt
    cmp eax,OP_LE; je .ses_le
    cmp eax,OP_GT; je .ses_gt
    cmp eax,OP_GE; je .ses_ge
    cmp eax,OP_MIN; je .ses_min
    cmp eax,OP_MAX; je .ses_max
    jmp .ses_fail
.ses_literal: mov rdi,rbx; call s_eval_literal_u64_fixed; jmp .ses_done
.ses_axis:
    cmp dword ptr [rip+s_cascade_axis_enabled],0; je .ses_fail
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]
    mov rdx,[rip+s_cascade_axis_ptr]; mov rcx,[rip+s_cascade_axis_len]; call s_span_eq
    test eax,eax; jz .ses_fail
    mov rax,[rip+s_cascade_axis_value]; xor edx,edx; jmp .ses_done
.ses_goal:
    mov rdi,[rbx+SN_PTR]; mov rsi,[rbx+SN_LEN]; call s_cascade_goal_find
    cmp eax,-1; je .ses_fail
    mov ecx,eax; lea rax,[rip+s_cascade_goal_done]; cmp dword ptr [rax+rcx*4],0; je .ses_fail
    lea rax,[rip+s_cascade_goal_result]; mov rax,[rax+rcx*8]; xor edx,edx; jmp .ses_done
.ses_one: mov rdi,[rbx+SN_A]; call s_eval_static_u64; jmp .ses_done
.ses_unary:
    mov rdi,[rbx+SN_A]; call s_eval_static_u64; test edx,edx; jnz .ses_fail
    mov r12,rax; mov eax,dword ptr [rbx+SN_OP]
    cmp eax,OP_NOT; je .ses_not
    cmp eax,OP_BIT_NOT; je .ses_bnot
    cmp eax,OP_ABS; je .ses_abs
    cmp eax,OP_NEG; jne .ses_fail
    test r12,r12; jz .ses_zero
    cmp dword ptr [rip+s_overflow_wrap],0; je .ses_fail
    mov rax,r12; neg rax; xor edx,edx; jmp .ses_done
.ses_zero: xor eax,eax; xor edx,edx; jmp .ses_done
.ses_not: test r12,r12; sete al; movzx eax,al; xor edx,edx; jmp .ses_done
.ses_bnot: mov rax,r12; not rax; xor edx,edx; jmp .ses_done
.ses_abs: mov rax,r12; xor edx,edx; jmp .ses_done
.ses_select:
    test r12,r12; jz .ses_select_c
    mov rax,r13; xor edx,edx; jmp .ses_done
.ses_select_c:
    mov rdi,[rbx+SN_C]; call s_eval_static_u64; jmp .ses_done
.ses_add: mov rax,r12; add rax,r13; jnc .ses_ok; cmp dword ptr [rip+s_overflow_wrap],0; jne .ses_ok; jmp .ses_fail
.ses_sub: mov rax,r12; sub rax,r13; jnc .ses_ok; cmp dword ptr [rip+s_overflow_wrap],0; jne .ses_ok; jmp .ses_fail
.ses_mul: mov rax,r12; mul r13; test rdx,rdx; jz .ses_ok; cmp dword ptr [rip+s_overflow_wrap],0; jne .ses_ok; jmp .ses_fail
.ses_div: test r13,r13; jz .ses_fail; mov rax,r12; xor edx,edx; div r13; xor edx,edx; jmp .ses_done
.ses_mod: test r13,r13; jz .ses_fail; mov rax,r12; xor edx,edx; div r13; mov rax,rdx; xor edx,edx; jmp .ses_done
.ses_band: mov rax,r12; and rax,r13; jmp .ses_ok
.ses_bor: mov rax,r12; or rax,r13; jmp .ses_ok
.ses_bxor: mov rax,r12; xor rax,r13; jmp .ses_ok
.ses_shl: cmp r13,64; jae .ses_fail; mov rax,r12; mov rcx,r13; shl rax,cl; jmp .ses_ok
.ses_shr: cmp r13,64; jae .ses_fail; mov rax,r12; mov rcx,r13; shr rax,cl; jmp .ses_ok
.ses_eq: cmp r12,r13; sete al; movzx eax,al; jmp .ses_ok
.ses_ne: cmp r12,r13; setne al; movzx eax,al; jmp .ses_ok
.ses_lt: cmp r12,r13; setb al; movzx eax,al; jmp .ses_ok
.ses_le: cmp r12,r13; setbe al; movzx eax,al; jmp .ses_ok
.ses_gt: cmp r12,r13; seta al; movzx eax,al; jmp .ses_ok
.ses_ge: cmp r12,r13; setae al; movzx eax,al; jmp .ses_ok
.ses_min: mov rax,r12; cmp r13,r12; cmovb rax,r13; jmp .ses_ok
.ses_max: mov rax,r12; cmp r13,r12; cmova rax,r13
.ses_ok: xor edx,edx; jmp .ses_done
.ses_fail: xor eax,eax; mov edx,1
.ses_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

s_record_add_static_field:
    # rdi=record ptr,rsi=len,rdx=field ptr,rcx=len,r8=AST -> eax
    push rbx
    mov ebx,dword ptr [rip+s_record_field_count]; cmp ebx,64; jae .sras_fail
    lea rax,[rip+s_record_name_ptr]; mov [rax+rbx*8],rdi
    lea rax,[rip+s_record_name_len]; mov [rax+rbx*8],rsi
    lea rax,[rip+s_record_field_ptr]; mov [rax+rbx*8],rdx
    lea rax,[rip+s_record_field_len]; mov [rax+rbx*8],rcx
    lea rax,[rip+s_record_value_ast]; mov [rax+rbx*8],r8
    inc dword ptr [rip+s_record_field_count]
    xor eax,eax; pop rbx; ret
.sras_fail: mov dword ptr [rip+s_error],1; mov eax,1; pop rbx; ret

s_parse_cascade_decl:
    # Closed cascade -> compile-time record. Dynamic state/input use rejects.
    push rbx; push r12; push r13; push r14; push r15
    call s_parse_name; test edx,edx; jnz .spcas_fail
    mov r12,rax; mov r13,rcx
    mov rdi,r12; mov rsi,r13; call s_decl_add; test eax,eax; jnz .spcas_fail
    mov edi,KID_EXECUTORS; call s_expect_kw_id
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spcas_fail
    mov rdi,rax; call s_eval_static_u64; test edx,edx; jnz .spcas_fail
    test rax,rax; jz .spcas_fail
    mov edi,KID_CHUNK; call s_expect_kw_id
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spcas_fail
    mov rdi,rax; call s_eval_static_u64; test edx,edx; jnz .spcas_fail
    test rax,rax; jz .spcas_fail
    mov edi,KID_AXIS; call s_expect_kw_id
    call s_parse_name; test edx,edx; jnz .spcas_fail
    mov [rip+s_cascade_axis_ptr],rax; mov [rip+s_cascade_axis_len],rcx
    mov edi,KID_EVENTS; call s_match_kw_id; test eax,eax; jz .spcas_events_done
    mov edi,KID_TRUE; call s_match_kw_id; test eax,eax; jnz .spcas_events_done
    mov edi,KID_FALSE; call s_match_kw_id; test eax,eax; jz .spcas_fail
.spcas_events_done:
    mov dword ptr [rip+s_cascade_goal_count],0
    # expose unit axis only while parsing the cascade body
    mov ebx,dword ptr [rip+s_axis_count]; cmp ebx,SCOPE_MAX; jae .spcas_fail
    lea rax,[rip+s_axis_ptrs]; mov rcx,[rip+s_cascade_axis_ptr]; mov [rax+rbx*8],rcx
    lea rax,[rip+s_axis_lens]; mov rcx,[rip+s_cascade_axis_len]; mov [rax+rbx*8],rcx
    inc dword ptr [rip+s_axis_count]
    lea rdi,[rip+tok_lbrace]; mov esi,1; xor edx,edx; call s_expect_token
.spcas_body:
    call s_skip
    lea rdi,[rip+tok_rbrace]; mov esi,1; xor edx,edx; call s_match_token
    test eax,eax; jnz .spcas_body_done
    mov edi,KID_GOAL; call s_match_kw_id; test eax,eax; jnz .spcas_goal
    mov edi,KID_RELATION; call s_match_kw_id; test eax,eax; jnz .spcas_relation
    jmp .spcas_fail_axis
.spcas_goal:
    call s_parse_name; test edx,edx; jnz .spcas_fail_axis
    mov r14,rax; mov r15,rcx
    mov eax,dword ptr [rip+s_cascade_goal_count]; cmp eax,CASCADE_GOAL_MAX; jae .spcas_fail_axis
    lea rdx,[rip+s_cascade_goal_name_ptr]; mov [rdx+rax*8],r14
    lea rdx,[rip+s_cascade_goal_name_len]; mov [rdx+rax*8],r15
    mov edi,KID_WORK; call s_expect_kw_id
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spcas_fail_axis
    mov ecx,dword ptr [rip+s_cascade_goal_count]; lea rdx,[rip+s_cascade_goal_work_ast]; mov [rdx+rcx*8],rax
    lea rdi,[rip+tok_eq1]; mov esi,1; xor edx,edx; call s_expect_token
    xor edi,edi; call s_parse_expr; test rax,rax; jz .spcas_fail_axis
    mov ecx,dword ptr [rip+s_cascade_goal_count]; lea rdx,[rip+s_cascade_goal_expr_ast]; mov [rdx+rcx*8],rax
    lea rdx,[rip+s_cascade_goal_prereq]; mov qword ptr [rdx+rcx*8],0
    lea rdx,[rip+s_cascade_goal_done]; mov dword ptr [rdx+rcx*4],0
    inc dword ptr [rip+s_cascade_goal_count]
    call s_optional_semicolon; jmp .spcas_body
.spcas_relation:
    call s_parse_name; test edx,edx; jnz .spcas_fail_axis
    mov rdi,rax; mov rsi,rcx; call s_cascade_goal_find; cmp eax,-1; je .spcas_fail_axis
    mov r14d,eax
    lea rdi,[rip+tok_arrowthin]; mov esi,2; xor edx,edx; call s_match_token
    test eax,eax; jnz .spcas_rel_target
    mov edi,KID_TO; call s_expect_kw_id
.spcas_rel_target:
    call s_parse_name; test edx,edx; jnz .spcas_fail_axis
    mov rdi,rax; mov rsi,rcx; call s_cascade_goal_find; cmp eax,-1; je .spcas_fail_axis
    mov r10d,eax
    mov ecx,r14d; mov rax,1; shl rax,cl
    lea rdx,[rip+s_cascade_goal_prereq]; or [rdx+r10*8],rax
    call s_optional_semicolon; jmp .spcas_body
.spcas_body_done:
    mov dword ptr [rip+s_axis_count],ebx
    # Fixed-point causal evaluation. A goal is eligible only after declared
    # predecessors and every goal_result it reads are available. All volatile
    # loop state lives in compile-time scratch so recursive AST evaluation cannot
    # accidentally turn register allocation into semantic state.
    xor r14,r14                             # done mask
    xor r15d,r15d                           # done count
.spcas_eval_round:
    mov dword ptr [rip+s_cascade_eval_progressed],0
    mov dword ptr [rip+s_cascade_eval_goal_idx],0
.spcas_eval_goal:
    mov ecx,dword ptr [rip+s_cascade_eval_goal_idx]
    cmp ecx,dword ptr [rip+s_cascade_goal_count]; jae .spcas_eval_round_done
    bt r14,rcx; jc .spcas_eval_next
    lea rax,[rip+s_cascade_goal_prereq]; mov rdx,[rax+rcx*8]
    mov rax,r14; not rax; and rdx,rax; test rdx,rdx; jnz .spcas_eval_next
    mov dword ptr [rip+s_cascade_axis_enabled],0
    lea rax,[rip+s_cascade_goal_work_ast]; mov rdi,[rax+rcx*8]; call s_eval_static_u64
    test edx,edx; jnz .spcas_eval_next
    cmp rax,1048576; ja .spcas_eval_hardfail
    mov [rip+s_cascade_eval_work],rax
    mov qword ptr [rip+s_cascade_eval_unit],0
    mov qword ptr [rip+s_cascade_eval_total],0
.spcas_units:
    mov r9,[rip+s_cascade_eval_unit]
    cmp r9,[rip+s_cascade_eval_work]; jae .spcas_goal_value
    mov dword ptr [rip+s_cascade_axis_enabled],1
    mov [rip+s_cascade_axis_value],r9
    mov ecx,dword ptr [rip+s_cascade_eval_goal_idx]
    lea rax,[rip+s_cascade_goal_expr_ast]; mov rdi,[rax+rcx*8]; call s_eval_static_u64
    test edx,edx; jnz .spcas_eval_next
    mov r10,[rip+s_cascade_eval_total]
    add r10,rax; jnc .spcas_sum_ok
    cmp dword ptr [rip+s_overflow_wrap],0; je .spcas_eval_hardfail
.spcas_sum_ok:
    mov [rip+s_cascade_eval_total],r10
    inc qword ptr [rip+s_cascade_eval_unit]
    jmp .spcas_units
.spcas_goal_value:
    mov ecx,dword ptr [rip+s_cascade_eval_goal_idx]
    mov r10,[rip+s_cascade_eval_total]
    lea rax,[rip+s_cascade_goal_result]; mov [rax+rcx*8],r10
    lea rax,[rip+s_cascade_goal_done]; mov dword ptr [rax+rcx*4],1
    bts r14,rcx
    inc r15d
    mov dword ptr [rip+s_cascade_eval_progressed],1
.spcas_eval_next:
    inc dword ptr [rip+s_cascade_eval_goal_idx]
    jmp .spcas_eval_goal
.spcas_eval_round_done:
    cmp r15d,dword ptr [rip+s_cascade_goal_count]; je .spcas_record
    cmp dword ptr [rip+s_cascade_eval_progressed],0; je .spcas_fail
    jmp .spcas_eval_round
.spcas_eval_hardfail:
    jmp .spcas_fail
.spcas_record:
    # Emit no binding. Materialize a compile-time record table instead.
    xor ecx,ecx
.spcas_record_loop:
    cmp ecx,dword ptr [rip+s_cascade_goal_count]; jae .spcas_completed
    lea rax,[rip+s_cascade_goal_result]; mov rdi,[rax+rcx*8]
    push rcx; call s_ast_u64_imm; pop rcx; mov r8,rax
    lea rax,[rip+s_cascade_goal_name_ptr]; mov rdx,[rax+rcx*8]
    lea rax,[rip+s_cascade_goal_name_len]; mov r9,[rax+rcx*8]
    push rcx; mov rcx,r9; mov rdi,r12; mov rsi,r13; call s_record_add_static_field; pop rcx
    test eax,eax; jnz .spcas_fail
    inc ecx; jmp .spcas_record_loop
.spcas_completed:
    mov edi,r15d; call s_ast_u64_imm; mov r8,rax
    mov rdi,r12; mov rsi,r13; lea rdx,[rip+kw_completed_goals]; mov ecx,15; call s_record_add_static_field
    test eax,eax; jnz .spcas_fail
    call s_optional_semicolon; xor eax,eax; jmp .spcas_exit
.spcas_fail_axis:
    mov dword ptr [rip+s_axis_count],ebx
.spcas_fail: mov dword ptr [rip+s_error],1; mov eax,1
.spcas_exit: pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Root parser / final canonical JSON assembly
# -----------------------------------------------------------------------------
s_match_kw_const:
    # passthrough: rdi ptr, esi len
    mov edx,1; jmp s_match_token

s_parse_wh:
.spwh_loop:
    call s_skip
    mov rax,[rip+s_cur]; cmp rax,[rip+s_end]; jae .spwh_done
    mov edi,KID_PROGRAM; call s_match_kw_id; test eax,eax; jnz .spwh_program
    mov edi,KID_CONTRACT; call s_match_kw_id; test eax,eax; jnz .spwh_contract
    mov edi,KID_TOLERANCE; call s_match_kw_id; test eax,eax; jnz .spwh_tol
    mov edi,KID_STRICT; call s_match_kw_id; test eax,eax; jnz .spwh_strict
    mov edi,KID_INPUT; call s_match_kw_id; test eax,eax; jnz .spwh_input
    mov edi,KID_AXIS; call s_match_kw_id; test eax,eax; jnz .spwh_axis
    mov edi,KID_RECORD; call s_match_kw_id; test eax,eax; jnz .spwh_record
    mov edi,KID_PURE; call s_match_kw_id; test eax,eax; jnz .spwh_pure
    mov edi,KID_REGION; call s_match_kw_id; test eax,eax; jnz .spwh_region
    mov edi,KID_FOR; call s_match_kw_id; test eax,eax; jnz .spwh_for
    mov edi,KID_WHILE; call s_match_kw_id; test eax,eax; jnz .spwh_fail
    mov edi,KID_LET; call s_match_kw_id; test eax,eax; jnz .spwh_let
    mov edi,KID_TENSOR; call s_match_kw_id; test eax,eax; jnz .spwh_tensor
    mov edi,KID_REDUCE; call s_match_kw_id; test eax,eax; jnz .spwh_reduce
    mov edi,KID_DICTIONARY; call s_match_kw_id; test eax,eax; jnz .spwh_dictionary
    mov edi,KID_LOOKUP; call s_match_kw_id; test eax,eax; jnz .spwh_lookup
    mov edi,KID_NESTED; call s_match_kw_id; test eax,eax; jnz .spwh_nested
    mov edi,KID_NESTED_REDUCE; call s_match_kw_id; test eax,eax; jnz .spwh_nested_reduce
    mov edi,KID_CASCADE; call s_match_kw_id; test eax,eax; jnz .spwh_cascade
    mov edi,KID_ITERATE; call s_match_kw_id; test eax,eax; jnz .spwh_iterate
    mov edi,KID_OUTPUT; call s_match_kw_id; test eax,eax; jnz .spwh_output
    mov edi,KID_PUBLISH; call s_match_kw_id; test eax,eax; jnz .spwh_output
    mov edi,KID_TEST; call s_match_kw_id; test eax,eax; jnz .spwh_test
    jmp .spwh_fail
.spwh_program: call s_parse_program_decl; jmp .spwh_check
.spwh_contract: call s_parse_contract_decl; jmp .spwh_check
.spwh_tol: call s_parse_tolerance_decl; jmp .spwh_check
.spwh_strict: call s_parse_strict_decl; jmp .spwh_check
.spwh_input: call s_parse_input_decl; jmp .spwh_check
.spwh_axis: call s_parse_whex_axis_decl; jmp .spwh_check
.spwh_record: call s_parse_record_decl; jmp .spwh_check
.spwh_pure: call s_parse_pure_function; jmp .spwh_check
.spwh_region: call s_parse_wh_region; jmp .spwh_check
.spwh_for: call s_parse_wh_for; jmp .spwh_check
.spwh_let: call s_parse_let_decl; jmp .spwh_check
.spwh_tensor: call s_parse_tensor_decl; jmp .spwh_check
.spwh_reduce: call s_parse_reduce_decl; jmp .spwh_check
.spwh_dictionary: call s_parse_dictionary_decl; jmp .spwh_check
.spwh_lookup: call s_parse_lookup_decl; jmp .spwh_check
.spwh_nested: call s_parse_nested_decl; jmp .spwh_check
.spwh_nested_reduce: call s_parse_nested_reduce_decl; jmp .spwh_check
.spwh_cascade: call s_parse_cascade_decl; jmp .spwh_check
.spwh_iterate: call s_parse_iterate_decl; jmp .spwh_check
.spwh_output: call s_parse_output_decl; jmp .spwh_check
.spwh_test: call s_parse_test_decl
.spwh_check:
    test eax,eax; jnz .spwh_fail
    cmp dword ptr [rip+s_error],0; jne .spwh_fail
    jmp .spwh_loop
.spwh_done: xor eax,eax; ret
.spwh_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_parse_whex:
.spwxh_loop:
    call s_skip
    mov rax,[rip+s_cur]; cmp rax,[rip+s_end]; jae .spwxh_done
    mov edi,KID_PROGRAM; call s_match_kw_id; test eax,eax; jnz .spwxh_program
    mov edi,KID_INPUT; call s_match_kw_id; test eax,eax; jnz .spwxh_input
    mov edi,KID_TOLERANCE; call s_match_kw_id; test eax,eax; jnz .spwxh_tol
    mov edi,KID_STRICT; call s_match_kw_id; test eax,eax; jnz .spwxh_strict
    mov edi,KID_AXIS; call s_match_kw_id; test eax,eax; jnz .spwxh_axis
    mov edi,KID_RECORD; call s_match_kw_id; test eax,eax; jnz .spwxh_record
    mov edi,KID_PURE; call s_match_kw_id; test eax,eax; jnz .spwxh_pure
    mov edi,KID_REGION; call s_match_kw_id; test eax,eax; jnz .spwxh_region
    mov edi,KID_FIELD; call s_match_kw_id; test eax,eax; jnz .spwxh_field
    mov edi,KID_EACH; call s_match_kw_id; test eax,eax; jnz .spwxh_each
    mov edi,KID_SUM; call s_match_kw_id; test eax,eax; jnz .spwxh_sum
    mov edi,KID_OUTPUT; call s_match_kw_id; test eax,eax; jnz .spwxh_output
    mov edi,KID_TEST; call s_match_kw_id; test eax,eax; jnz .spwxh_test
    jmp .spwxh_fail
.spwxh_program: call s_parse_program_decl; jmp .spwxh_check
.spwxh_input: call s_parse_input_decl; jmp .spwxh_check
.spwxh_tol: call s_parse_tolerance_decl; jmp .spwxh_check
.spwxh_strict: call s_parse_strict_decl; jmp .spwxh_check
.spwxh_axis: call s_parse_whex_axis_decl; jmp .spwxh_check
.spwxh_record: call s_parse_record_decl; jmp .spwxh_check
.spwxh_pure: call s_parse_pure_function; jmp .spwxh_check
.spwxh_region: call s_parse_whex_region; jmp .spwxh_check
.spwxh_field: call s_parse_whex_field; jmp .spwxh_check
.spwxh_each: call s_parse_whex_each; jmp .spwxh_check
.spwxh_sum: call s_parse_whex_sum; jmp .spwxh_check
.spwxh_output: call s_parse_output_decl; jmp .spwxh_check
.spwxh_test: call s_parse_test_decl
.spwxh_check:
    test eax,eax; jnz .spwxh_fail
    cmp dword ptr [rip+s_error],0; jne .spwxh_fail
    jmp .spwxh_loop
.spwxh_done: xor eax,eax; ret
.spwxh_fail: mov dword ptr [rip+s_error],1; mov eax,1; ret

s_path_is_whex:
    # rdi path -> eax bool
    xor ecx,ecx
.spiw_len: cmp byte ptr [rdi+rcx],0; je .spiw_chk; inc ecx; jmp .spiw_len
.spiw_chk: cmp ecx,5; jb .spiw_no
    lea rax,[rdi+rcx-5]
    cmp byte ptr [rax],'.'; jne .spiw_no
    cmp byte ptr [rax+1],'w'; jne .spiw_no
    cmp byte ptr [rax+2],'h'; jne .spiw_no
    cmp byte ptr [rax+3],'e'; jne .spiw_no
    cmp byte ptr [rax+4],'x'; jne .spiw_no
    mov eax,1; ret
.spiw_no: xor eax,eax; ret

s_finalize_json:
    lea rax,[rip+surface_json_buffer]; mov [rip+s_out_ptr],rax
    lea rax,[rip+surface_json_buffer+SBUF_FINAL_CAP]; mov [rip+s_out_limit],rax
    lea rdi,[rip+js_root_format]; call s_out_cstr
    # program
    mov rdi,[rip+s_program_ptr]; mov rsi,[rip+s_program_len]
    test rdi,rdi; jnz .sfj_have_program
    lea rdi,[rip+default_program]; mov esi,15
.sfj_have_program:
    call s_out_quote_span
    lea rdi,[rip+js_contract_prefix]; call s_out_cstr
    cmp dword ptr [rip+s_deterministic],0; je .sfj_det_false
    lea rdi,[rip+lit_true]; call s_out_cstr; jmp .sfj_det_done
.sfj_det_false: lea rdi,[rip+lit_false]; call s_out_cstr
.sfj_det_done:
    lea rdi,[rip+js_overflow_mid]; call s_out_cstr
    cmp dword ptr [rip+s_overflow_wrap],0; je .sfj_trap
    lea rdi,[rip+cv_wrap]; mov esi,4; call s_out_quote_span; jmp .sfj_overflow_done
.sfj_trap: lea rdi,[rip+cv_trap]; mov esi,4; call s_out_quote_span
.sfj_overflow_done:
    lea rdi,[rip+js_fp_mid]; call s_out_cstr
    cmp dword ptr [rip+s_fp_tolerant],0; je .sfj_fp_strict
    lea rdi,[rip+cv_tolerant]; mov esi,8; call s_out_quote_span; jmp .sfj_fp_done
.sfj_fp_strict: lea rdi,[rip+cv_strict]; mov esi,17; call s_out_quote_span
.sfj_fp_done:
    cmp dword ptr [rip+s_mode],1; jne .sfj_contract_close
    lea rdi,[rip+js_mixed_mid]; call s_out_cstr
.sfj_contract_close:
    lea rdi,[rip+js_inputs_prefix]; call s_out_cstr
    lea rdi,[rip+s_inputs_buf]; mov rsi,[rip+s_inputs_end]; sub rsi,rdi; call s_out_span
    lea rdi,[rip+js_bindings_mid]; call s_out_cstr
    lea rdi,[rip+s_bindings_buf]; mov rsi,[rip+s_bindings_end]; sub rsi,rdi; call s_out_span
    lea rdi,[rip+js_outputs_mid]; call s_out_cstr
    lea rdi,[rip+s_outputs_buf]; mov rsi,[rip+s_outputs_end]; sub rsi,rdi; call s_out_span
    lea rdi,[rip+js_tests_mid]; call s_out_cstr
    lea rdi,[rip+s_tests_buf]; mov rsi,[rip+s_tests_end]; sub rsi,rdi; call s_out_span
    # Close tests exactly once. Optional metadata is appended to the root object.
    mov dil,']'; call s_out_byte
    # optional lane/rank metadata
    cmp dword ptr [rip+s_general_lane],0; je .sfj_rank
    lea rdi,[rip+js_general_lane]; call s_out_cstr
.sfj_rank:
    cmp dword ptr [rip+s_rankn_active],0; je .sfj_close
    lea rdi,[rip+js_rank_product]; call s_out_cstr
    mov rdi,[rip+s_rankn_product]; call s_emit_u64_decimal
    lea rdi,[rip+js_rank_source]; call s_out_cstr
    mov edi,dword ptr [rip+s_rankn_source_rank]; call s_emit_u64_decimal
.sfj_close:
    mov dil,'}'; call s_out_byte
    mov rax,[rip+s_out_ptr]; lea rcx,[rip+surface_json_buffer]; sub rax,rcx
    mov [rip+surface_json_length],rax
    xor eax,eax; ret

s_emit_u64_decimal:
    # rdi=value to current output
    push rbx
    mov rax,rdi; lea rbx,[rip+s_num_scratch+31]; xor ecx,ecx
    test rax,rax; jnz .seud_loop
    dec rbx; mov byte ptr [rbx],'0'; mov ecx,1; jmp .seud_emit
.seud_loop:
    xor edx,edx; mov r8,10; div r8; add dl,'0'; dec rbx; mov [rbx],dl; inc ecx; test rax,rax; jnz .seud_loop
.seud_emit: mov rdi,rbx; mov rsi,rcx; call s_out_span; pop rbx; ret

surface_lower_to_json:
    # rdi=input path. Uses global source_ptr/source_length. eax 0 success.
    push rbx; push r12; push r13; push r14; push r15
    mov dword ptr [rip+s_error],0
    mov dword ptr [rip+s_ast_count],0
    mov dword ptr [rip+s_input_count],0; mov dword ptr [rip+s_binding_count],0
    mov dword ptr [rip+s_output_count],0; mov dword ptr [rip+s_test_count],0
    mov dword ptr [rip+s_general_lane],0; mov dword ptr [rip+s_rankn_active],0
    mov dword ptr [rip+s_record_field_count],0; mov dword ptr [rip+s_function_count],0; mov dword ptr [rip+s_decl_count],0
    mov dword ptr [rip+s_dictionary_count],0; mov dword ptr [rip+s_dictionary_entry_count],0; mov dword ptr [rip+s_nested_count],0
    mov dword ptr [rip+s_cascade_goal_count],0; mov dword ptr [rip+s_cascade_axis_enabled],0
    mov dword ptr [rip+s_overflow_wrap],0; mov dword ptr [rip+s_deterministic],1
    mov dword ptr [rip+s_fp_tolerant],0
    mov qword ptr [rip+s_tol_ptr],0; mov qword ptr [rip+s_tol_len],0
    mov qword ptr [rip+s_program_ptr],0; mov qword ptr [rip+s_program_len],0
    mov rax,[rip+source_ptr]; mov [rip+s_src],rax; mov [rip+s_cur],rax
    add rax,[rip+source_length]; mov [rip+s_end],rax
    lea rax,[rip+s_inputs_buf]; mov [rip+s_inputs_end],rax
    lea rax,[rip+s_bindings_buf]; mov [rip+s_bindings_end],rax
    lea rax,[rip+s_outputs_buf]; mov [rip+s_outputs_end],rax
    lea rax,[rip+s_tests_buf]; mov [rip+s_tests_end],rax
    call s_path_is_whex
    mov [rip+s_mode],eax
    test eax,eax; jz .sltj_wh
    call s_parse_whex; jmp .sltj_after
.sltj_wh: call s_parse_wh
.sltj_after:
    test eax,eax; jnz .sltj_fail
    cmp dword ptr [rip+s_output_count],0; je .sltj_fail
    cmp dword ptr [rip+s_test_count],0; je .sltj_fail
    call s_finalize_json
    test eax,eax; jnz .sltj_fail
    lea rax,[rip+surface_json_buffer]; mov [rip+source_ptr],rax
    mov rax,[rip+surface_json_length]; mov [rip+source_length],rax
    xor eax,eax; jmp .sltj_done
.sltj_fail: mov eax,1
.sltj_done:
    pop r15; pop r14; pop r13; pop r12; pop rbx; ret

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
.section .rodata
# punctuation
 tok_bang:.ascii "!"; tok_tilde:.ascii "~"; tok_minus:.ascii "-"; tok_plus:.ascii "+"
 tok_lparen:.ascii "("; tok_rparen:.ascii ")"; tok_lbrack:.ascii "["; tok_rbrack:.ascii "]"
 tok_lbrace:.ascii "{"; tok_rbrace:.ascii "}"; tok_comma:.ascii ","; tok_colon:.ascii ":"; tok_semicolon:.ascii ";"
 tok_eq1:.ascii "="; tok_dot:.ascii "."; tok_dotdot:.ascii ".."; tok_arrowfat:.ascii "=>"; tok_arrowthin:.ascii "->"
# keywords/names
kw_program:.ascii "program"; kw_contract:.ascii "contract"; kw_input:.ascii "input"; kw_range:.ascii "range"; kw_for:.ascii "for"; kw_if:.ascii "if"; kw_else:.ascii "else"
kw_let:.ascii "let"; kw_tensor:.ascii "tensor"; kw_reduce:.ascii "reduce"; kw_iterate:.ascii "iterate"
kw_output:.ascii "output"; kw_publish:.ascii "publish"; kw_test:.ascii "test"; kw_limit:.ascii "limit"
kw_state:.ascii "state"; kw_while:.ascii "while"; kw_update:.ascii "update"; kw_result:.ascii "result"
kw_true:.ascii "true"; kw_false:.ascii "false"; kw_cast:.ascii "cast"; kw_periodic:.ascii "periodic"; kw_select:.ascii "select"
kw_min:.ascii "min"; kw_max:.ascii "max"; kw_abs:.ascii "abs"; kw_rel:.ascii "rel"
kw_xor:.ascii "xor"; kw_bit_and:.ascii "bit_and"; kw_bit_or:.ascii "bit_or"; kw_bit_xor:.ascii "bit_xor"
kw_shl:.ascii "shl"; kw_shr:.ascii "shr"
kw_in:.ascii "in"; kw_tolerance:.ascii "tolerance"; kw_strict:.ascii "strict"; kw_field:.ascii "field"; kw_sum:.ascii "sum"
kw_axis:.ascii "axis"; kw_region:.ascii "region"; kw_effect:.ascii "effect"; kw_pure:.ascii "pure"; kw_parallel:.ascii "parallel"
kw_record:.ascii "record"; kw_generic:.ascii "generic"; kw_fn:.ascii "fn"
kw_dictionary:.ascii "dictionary"; kw_lookup:.ascii "lookup"; kw_default:.ascii "default"
kw_nested:.ascii "nested"; kw_nested_reduce:.ascii "nested_reduce"; kw_cascade:.ascii "cascade"
kw_executors:.ascii "executors"; kw_chunk:.ascii "chunk"; kw_events:.ascii "events"
kw_goal:.ascii "goal"; kw_work:.ascii "work"; kw_relation:.ascii "relation"; kw_to:.ascii "to"
kw_goal_result:.ascii "goal_result"; kw_count:.ascii "count"; kw_segment_count:.ascii "segment_count"
kw_completed_goals:.ascii "完成目标数"
name_n:.ascii "n"; rank_q_name:.ascii "__rankn_q_0"
ck_integer_overflow:.ascii "integer_overflow"; ck_deterministic:.ascii "deterministic"
cv_wrap:.ascii "wrap"; cv_trap:.ascii "trap"; cv_tolerant:.ascii "tolerant"; cv_strict:.ascii "strict_by_default"
ty_bool:.ascii "bool"; ty_i64:.ascii "i64"; ty_u64:.ascii "u64"; ty_f32:.ascii "f32"; ty_f64:.ascii "f64"; ty_string:.ascii "string"
default_program:.ascii "surface_program"
lit_true:.asciz "true"; lit_false:.asciz "false"; num_zero_float:.asciz "0.0"
# UTF-8 keyword aliases: compile-time only.
kwa_program_0:.ascii "program"; kwa_program_0_end:
kwa_program_1:.ascii "程序"; kwa_program_1_end:
kwa_program_2:.ascii "程式"; kwa_program_2_end:
kwa_contract_0:.ascii "contract"; kwa_contract_0_end:
kwa_contract_1:.ascii "契约"; kwa_contract_1_end:
kwa_contract_2:.ascii "契約"; kwa_contract_2_end:
kwa_input_0:.ascii "input"; kwa_input_0_end:
kwa_input_1:.ascii "输入"; kwa_input_1_end:
kwa_input_2:.ascii "輸入"; kwa_input_2_end:
kwa_range_0:.ascii "range"; kwa_range_0_end:
kwa_range_1:.ascii "范围"; kwa_range_1_end:
kwa_range_2:.ascii "範圍"; kwa_range_2_end:
kwa_let_0:.ascii "let"; kwa_let_0_end:
kwa_let_1:.ascii "定义"; kwa_let_1_end:
kwa_let_2:.ascii "定義"; kwa_let_2_end:
kwa_let_3:.ascii "令"; kwa_let_3_end:
kwa_tensor_0:.ascii "tensor"; kwa_tensor_0_end:
kwa_tensor_1:.ascii "张量"; kwa_tensor_1_end:
kwa_tensor_2:.ascii "張量"; kwa_tensor_2_end:
kwa_reduce_0:.ascii "reduce"; kwa_reduce_0_end:
kwa_reduce_1:.ascii "归约"; kwa_reduce_1_end:
kwa_reduce_2:.ascii "歸約"; kwa_reduce_2_end:
kwa_sum_0:.ascii "sum"; kwa_sum_0_end:
kwa_sum_1:.ascii "求和"; kwa_sum_1_end:
kwa_sum_2:.ascii "總和"; kwa_sum_2_end:
kwa_iterate_0:.ascii "iterate"; kwa_iterate_0_end:
kwa_iterate_1:.ascii "迭代"; kwa_iterate_1_end:
kwa_limit_0:.ascii "limit"; kwa_limit_0_end:
kwa_limit_1:.ascii "上限"; kwa_limit_1_end:
kwa_state_0:.ascii "state"; kwa_state_0_end:
kwa_state_1:.ascii "状态"; kwa_state_1_end:
kwa_state_2:.ascii "狀態"; kwa_state_2_end:
kwa_while_0:.ascii "while"; kwa_while_0_end:
kwa_while_1:.ascii "当"; kwa_while_1_end:
kwa_while_2:.ascii "當"; kwa_while_2_end:
kwa_update_0:.ascii "update"; kwa_update_0_end:
kwa_update_1:.ascii "更新"; kwa_update_1_end:
kwa_result_0:.ascii "result"; kwa_result_0_end:
kwa_result_1:.ascii "结果"; kwa_result_1_end:
kwa_result_2:.ascii "結果"; kwa_result_2_end:
kwa_record_0:.ascii "record"; kwa_record_0_end:
kwa_record_1:.ascii "记录"; kwa_record_1_end:
kwa_record_2:.ascii "記錄"; kwa_record_2_end:
kwa_axis_0:.ascii "axis"; kwa_axis_0_end:
kwa_axis_1:.ascii "轴"; kwa_axis_1_end:
kwa_axis_2:.ascii "軸"; kwa_axis_2_end:
kwa_pure_0:.ascii "pure"; kwa_pure_0_end:
kwa_pure_1:.ascii "纯"; kwa_pure_1_end:
kwa_pure_2:.ascii "純"; kwa_pure_2_end:
kwa_generic_0:.ascii "generic"; kwa_generic_0_end:
kwa_generic_1:.ascii "泛型"; kwa_generic_1_end:
kwa_fn_0:.ascii "fn"; kwa_fn_0_end:
kwa_fn_1:.ascii "函数"; kwa_fn_1_end:
kwa_fn_2:.ascii "函數"; kwa_fn_2_end:
kwa_region_0:.ascii "region"; kwa_region_0_end:
kwa_region_1:.ascii "区域"; kwa_region_1_end:
kwa_region_2:.ascii "區域"; kwa_region_2_end:
kwa_effect_0:.ascii "effect"; kwa_effect_0_end:
kwa_effect_1:.ascii "效应"; kwa_effect_1_end:
kwa_effect_2:.ascii "效應"; kwa_effect_2_end:
kwa_parallel_0:.ascii "parallel"; kwa_parallel_0_end:
kwa_parallel_1:.ascii "并行"; kwa_parallel_1_end:
kwa_parallel_2:.ascii "並行"; kwa_parallel_2_end:
kwa_for_0:.ascii "for"; kwa_for_0_end:
kwa_for_1:.ascii "循环"; kwa_for_1_end:
kwa_for_2:.ascii "循環"; kwa_for_2_end:
kwa_if_0:.ascii "if"; kwa_if_0_end:
kwa_if_1:.ascii "如果"; kwa_if_1_end:
kwa_if_2:.ascii "若"; kwa_if_2_end:
kwa_else_0:.ascii "else"; kwa_else_0_end:
kwa_else_1:.ascii "否则"; kwa_else_1_end:
kwa_else_2:.ascii "否則"; kwa_else_2_end:
kwa_tolerance_0:.ascii "tolerance"; kwa_tolerance_0_end:
kwa_tolerance_1:.ascii "容差"; kwa_tolerance_1_end:
kwa_strict_0:.ascii "strict"; kwa_strict_0_end:
kwa_strict_1:.ascii "严格"; kwa_strict_1_end:
kwa_strict_2:.ascii "嚴格"; kwa_strict_2_end:
kwa_field_0:.ascii "field"; kwa_field_0_end:
kwa_field_1:.ascii "场"; kwa_field_1_end:
kwa_field_2:.ascii "場"; kwa_field_2_end:
kwa_each_0:.ascii "each"; kwa_each_0_end:
kwa_each_1:.ascii "每个"; kwa_each_1_end:
kwa_each_2:.ascii "每個"; kwa_each_2_end:
kwa_in_0:.ascii "in"; kwa_in_0_end:
kwa_in_1:.ascii "属于"; kwa_in_1_end:
kwa_in_2:.ascii "屬於"; kwa_in_2_end:
kwa_output_0:.ascii "output"; kwa_output_0_end:
kwa_output_1:.ascii "输出"; kwa_output_1_end:
kwa_output_2:.ascii "輸出"; kwa_output_2_end:
kwa_publish_0:.ascii "publish"; kwa_publish_0_end:
kwa_publish_1:.ascii "发布"; kwa_publish_1_end:
kwa_publish_2:.ascii "發佈"; kwa_publish_2_end:
kwa_test_0:.ascii "test"; kwa_test_0_end:
kwa_test_1:.ascii "测试"; kwa_test_1_end:
kwa_test_2:.ascii "測試"; kwa_test_2_end:
kwa_true_0:.ascii "true"; kwa_true_0_end:
kwa_true_1:.ascii "真"; kwa_true_1_end:
kwa_false_0:.ascii "false"; kwa_false_0_end:
kwa_false_1:.ascii "假"; kwa_false_1_end:
kwa_cast_0:.ascii "cast"; kwa_cast_0_end:
kwa_cast_1:.ascii "转换"; kwa_cast_1_end:
kwa_cast_2:.ascii "轉換"; kwa_cast_2_end:
kwa_select_0:.ascii "select"; kwa_select_0_end:
kwa_select_1:.ascii "选择"; kwa_select_1_end:
kwa_select_2:.ascii "選擇"; kwa_select_2_end:
kwa_min_0:.ascii "min"; kwa_min_0_end:
kwa_min_1:.ascii "最小"; kwa_min_1_end:
kwa_max_0:.ascii "max"; kwa_max_0_end:
kwa_max_1:.ascii "最大"; kwa_max_1_end:
kwa_abs_0:.ascii "abs"; kwa_abs_0_end:
kwa_abs_1:.ascii "绝对值"; kwa_abs_1_end:
kwa_abs_2:.ascii "絕對值"; kwa_abs_2_end:
kwa_periodic_0:.ascii "periodic"; kwa_periodic_0_end:
kwa_periodic_1:.ascii "周期"; kwa_periodic_1_end:
kwa_periodic_2:.ascii "週期"; kwa_periodic_2_end:
kwa_dictionary_0:.ascii "dictionary"; kwa_dictionary_0_end:
kwa_dictionary_1:.ascii "字典"; kwa_dictionary_1_end:
kwa_dictionary_2:.ascii "辭典"; kwa_dictionary_2_end:
kwa_lookup_0:.ascii "lookup"; kwa_lookup_0_end:
kwa_lookup_1:.ascii "查找"; kwa_lookup_1_end:
kwa_lookup_2:.ascii "查詢"; kwa_lookup_2_end:
kwa_default_0:.ascii "default"; kwa_default_0_end:
kwa_default_1:.ascii "默认"; kwa_default_1_end:
kwa_default_2:.ascii "預設"; kwa_default_2_end:
kwa_nested_0:.ascii "nested"; kwa_nested_0_end:
kwa_nested_1:.ascii "嵌套"; kwa_nested_1_end:
kwa_nested_2:.ascii "巢狀"; kwa_nested_2_end:
kwa_nested_reduce_0:.ascii "nested_reduce"; kwa_nested_reduce_0_end:
kwa_nested_reduce_1:.ascii "嵌套归约"; kwa_nested_reduce_1_end:
kwa_nested_reduce_2:.ascii "巢狀歸約"; kwa_nested_reduce_2_end:
kwa_cascade_0:.ascii "cascade"; kwa_cascade_0_end:
kwa_cascade_1:.ascii "级联"; kwa_cascade_1_end:
kwa_cascade_2:.ascii "級聯"; kwa_cascade_2_end:
kwa_executors_0:.ascii "executors"; kwa_executors_0_end:
kwa_executors_1:.ascii "执行器"; kwa_executors_1_end:
kwa_executors_2:.ascii "執行器"; kwa_executors_2_end:
kwa_chunk_0:.ascii "chunk"; kwa_chunk_0_end:
kwa_chunk_1:.ascii "工作块"; kwa_chunk_1_end:
kwa_chunk_2:.ascii "工作塊"; kwa_chunk_2_end:
kwa_events_0:.ascii "events"; kwa_events_0_end:
kwa_events_1:.ascii "事件"; kwa_events_1_end:
kwa_goal_0:.ascii "goal"; kwa_goal_0_end:
kwa_goal_1:.ascii "目标"; kwa_goal_1_end:
kwa_goal_2:.ascii "目標"; kwa_goal_2_end:
kwa_work_0:.ascii "work"; kwa_work_0_end:
kwa_work_1:.ascii "工作"; kwa_work_1_end:
kwa_relation_0:.ascii "relation"; kwa_relation_0_end:
kwa_relation_1:.ascii "关系"; kwa_relation_1_end:
kwa_relation_2:.ascii "關係"; kwa_relation_2_end:
kwa_to_0:.ascii "to"; kwa_to_0_end:
kwa_to_1:.ascii "到"; kwa_to_1_end:
kwa_goal_result_0:.ascii "goal_result"; kwa_goal_result_0_end:
kwa_goal_result_1:.ascii "目标结果"; kwa_goal_result_1_end:
kwa_goal_result_2:.ascii "目標結果"; kwa_goal_result_2_end:
.p2align 3
s_kw_alias_table:
    .quad kwa_program_0; .long kwa_program_0_end-kwa_program_0; .long KID_PROGRAM
    .quad kwa_program_1; .long kwa_program_1_end-kwa_program_1; .long KID_PROGRAM
    .quad kwa_program_2; .long kwa_program_2_end-kwa_program_2; .long KID_PROGRAM
    .quad kwa_contract_0; .long kwa_contract_0_end-kwa_contract_0; .long KID_CONTRACT
    .quad kwa_contract_1; .long kwa_contract_1_end-kwa_contract_1; .long KID_CONTRACT
    .quad kwa_contract_2; .long kwa_contract_2_end-kwa_contract_2; .long KID_CONTRACT
    .quad kwa_input_0; .long kwa_input_0_end-kwa_input_0; .long KID_INPUT
    .quad kwa_input_1; .long kwa_input_1_end-kwa_input_1; .long KID_INPUT
    .quad kwa_input_2; .long kwa_input_2_end-kwa_input_2; .long KID_INPUT
    .quad kwa_range_0; .long kwa_range_0_end-kwa_range_0; .long KID_RANGE
    .quad kwa_range_1; .long kwa_range_1_end-kwa_range_1; .long KID_RANGE
    .quad kwa_range_2; .long kwa_range_2_end-kwa_range_2; .long KID_RANGE
    .quad kwa_let_0; .long kwa_let_0_end-kwa_let_0; .long KID_LET
    .quad kwa_let_1; .long kwa_let_1_end-kwa_let_1; .long KID_LET
    .quad kwa_let_2; .long kwa_let_2_end-kwa_let_2; .long KID_LET
    .quad kwa_let_3; .long kwa_let_3_end-kwa_let_3; .long KID_LET
    .quad kwa_tensor_0; .long kwa_tensor_0_end-kwa_tensor_0; .long KID_TENSOR
    .quad kwa_tensor_1; .long kwa_tensor_1_end-kwa_tensor_1; .long KID_TENSOR
    .quad kwa_tensor_2; .long kwa_tensor_2_end-kwa_tensor_2; .long KID_TENSOR
    .quad kwa_reduce_0; .long kwa_reduce_0_end-kwa_reduce_0; .long KID_REDUCE
    .quad kwa_reduce_1; .long kwa_reduce_1_end-kwa_reduce_1; .long KID_REDUCE
    .quad kwa_reduce_2; .long kwa_reduce_2_end-kwa_reduce_2; .long KID_REDUCE
    .quad kwa_sum_0; .long kwa_sum_0_end-kwa_sum_0; .long KID_SUM
    .quad kwa_sum_1; .long kwa_sum_1_end-kwa_sum_1; .long KID_SUM
    .quad kwa_sum_2; .long kwa_sum_2_end-kwa_sum_2; .long KID_SUM
    .quad kwa_iterate_0; .long kwa_iterate_0_end-kwa_iterate_0; .long KID_ITERATE
    .quad kwa_iterate_1; .long kwa_iterate_1_end-kwa_iterate_1; .long KID_ITERATE
    .quad kwa_limit_0; .long kwa_limit_0_end-kwa_limit_0; .long KID_LIMIT
    .quad kwa_limit_1; .long kwa_limit_1_end-kwa_limit_1; .long KID_LIMIT
    .quad kwa_state_0; .long kwa_state_0_end-kwa_state_0; .long KID_STATE
    .quad kwa_state_1; .long kwa_state_1_end-kwa_state_1; .long KID_STATE
    .quad kwa_state_2; .long kwa_state_2_end-kwa_state_2; .long KID_STATE
    .quad kwa_while_0; .long kwa_while_0_end-kwa_while_0; .long KID_WHILE
    .quad kwa_while_1; .long kwa_while_1_end-kwa_while_1; .long KID_WHILE
    .quad kwa_while_2; .long kwa_while_2_end-kwa_while_2; .long KID_WHILE
    .quad kwa_update_0; .long kwa_update_0_end-kwa_update_0; .long KID_UPDATE
    .quad kwa_update_1; .long kwa_update_1_end-kwa_update_1; .long KID_UPDATE
    .quad kwa_result_0; .long kwa_result_0_end-kwa_result_0; .long KID_RESULT
    .quad kwa_result_1; .long kwa_result_1_end-kwa_result_1; .long KID_RESULT
    .quad kwa_result_2; .long kwa_result_2_end-kwa_result_2; .long KID_RESULT
    .quad kwa_record_0; .long kwa_record_0_end-kwa_record_0; .long KID_RECORD
    .quad kwa_record_1; .long kwa_record_1_end-kwa_record_1; .long KID_RECORD
    .quad kwa_record_2; .long kwa_record_2_end-kwa_record_2; .long KID_RECORD
    .quad kwa_axis_0; .long kwa_axis_0_end-kwa_axis_0; .long KID_AXIS
    .quad kwa_axis_1; .long kwa_axis_1_end-kwa_axis_1; .long KID_AXIS
    .quad kwa_axis_2; .long kwa_axis_2_end-kwa_axis_2; .long KID_AXIS
    .quad kwa_pure_0; .long kwa_pure_0_end-kwa_pure_0; .long KID_PURE
    .quad kwa_pure_1; .long kwa_pure_1_end-kwa_pure_1; .long KID_PURE
    .quad kwa_pure_2; .long kwa_pure_2_end-kwa_pure_2; .long KID_PURE
    .quad kwa_generic_0; .long kwa_generic_0_end-kwa_generic_0; .long KID_GENERIC
    .quad kwa_generic_1; .long kwa_generic_1_end-kwa_generic_1; .long KID_GENERIC
    .quad kwa_fn_0; .long kwa_fn_0_end-kwa_fn_0; .long KID_FN
    .quad kwa_fn_1; .long kwa_fn_1_end-kwa_fn_1; .long KID_FN
    .quad kwa_fn_2; .long kwa_fn_2_end-kwa_fn_2; .long KID_FN
    .quad kwa_region_0; .long kwa_region_0_end-kwa_region_0; .long KID_REGION
    .quad kwa_region_1; .long kwa_region_1_end-kwa_region_1; .long KID_REGION
    .quad kwa_region_2; .long kwa_region_2_end-kwa_region_2; .long KID_REGION
    .quad kwa_effect_0; .long kwa_effect_0_end-kwa_effect_0; .long KID_EFFECT
    .quad kwa_effect_1; .long kwa_effect_1_end-kwa_effect_1; .long KID_EFFECT
    .quad kwa_effect_2; .long kwa_effect_2_end-kwa_effect_2; .long KID_EFFECT
    .quad kwa_parallel_0; .long kwa_parallel_0_end-kwa_parallel_0; .long KID_PARALLEL
    .quad kwa_parallel_1; .long kwa_parallel_1_end-kwa_parallel_1; .long KID_PARALLEL
    .quad kwa_parallel_2; .long kwa_parallel_2_end-kwa_parallel_2; .long KID_PARALLEL
    .quad kwa_for_0; .long kwa_for_0_end-kwa_for_0; .long KID_FOR
    .quad kwa_for_1; .long kwa_for_1_end-kwa_for_1; .long KID_FOR
    .quad kwa_for_2; .long kwa_for_2_end-kwa_for_2; .long KID_FOR
    .quad kwa_if_0; .long kwa_if_0_end-kwa_if_0; .long KID_IF
    .quad kwa_if_1; .long kwa_if_1_end-kwa_if_1; .long KID_IF
    .quad kwa_if_2; .long kwa_if_2_end-kwa_if_2; .long KID_IF
    .quad kwa_else_0; .long kwa_else_0_end-kwa_else_0; .long KID_ELSE
    .quad kwa_else_1; .long kwa_else_1_end-kwa_else_1; .long KID_ELSE
    .quad kwa_else_2; .long kwa_else_2_end-kwa_else_2; .long KID_ELSE
    .quad kwa_tolerance_0; .long kwa_tolerance_0_end-kwa_tolerance_0; .long KID_TOLERANCE
    .quad kwa_tolerance_1; .long kwa_tolerance_1_end-kwa_tolerance_1; .long KID_TOLERANCE
    .quad kwa_strict_0; .long kwa_strict_0_end-kwa_strict_0; .long KID_STRICT
    .quad kwa_strict_1; .long kwa_strict_1_end-kwa_strict_1; .long KID_STRICT
    .quad kwa_strict_2; .long kwa_strict_2_end-kwa_strict_2; .long KID_STRICT
    .quad kwa_field_0; .long kwa_field_0_end-kwa_field_0; .long KID_FIELD
    .quad kwa_field_1; .long kwa_field_1_end-kwa_field_1; .long KID_FIELD
    .quad kwa_field_2; .long kwa_field_2_end-kwa_field_2; .long KID_FIELD
    .quad kwa_each_0; .long kwa_each_0_end-kwa_each_0; .long KID_EACH
    .quad kwa_each_1; .long kwa_each_1_end-kwa_each_1; .long KID_EACH
    .quad kwa_each_2; .long kwa_each_2_end-kwa_each_2; .long KID_EACH
    .quad kwa_in_0; .long kwa_in_0_end-kwa_in_0; .long KID_IN
    .quad kwa_in_1; .long kwa_in_1_end-kwa_in_1; .long KID_IN
    .quad kwa_in_2; .long kwa_in_2_end-kwa_in_2; .long KID_IN
    .quad kwa_output_0; .long kwa_output_0_end-kwa_output_0; .long KID_OUTPUT
    .quad kwa_output_1; .long kwa_output_1_end-kwa_output_1; .long KID_OUTPUT
    .quad kwa_output_2; .long kwa_output_2_end-kwa_output_2; .long KID_OUTPUT
    .quad kwa_publish_0; .long kwa_publish_0_end-kwa_publish_0; .long KID_PUBLISH
    .quad kwa_publish_1; .long kwa_publish_1_end-kwa_publish_1; .long KID_PUBLISH
    .quad kwa_publish_2; .long kwa_publish_2_end-kwa_publish_2; .long KID_PUBLISH
    .quad kwa_test_0; .long kwa_test_0_end-kwa_test_0; .long KID_TEST
    .quad kwa_test_1; .long kwa_test_1_end-kwa_test_1; .long KID_TEST
    .quad kwa_test_2; .long kwa_test_2_end-kwa_test_2; .long KID_TEST
    .quad kwa_true_0; .long kwa_true_0_end-kwa_true_0; .long KID_TRUE
    .quad kwa_true_1; .long kwa_true_1_end-kwa_true_1; .long KID_TRUE
    .quad kwa_false_0; .long kwa_false_0_end-kwa_false_0; .long KID_FALSE
    .quad kwa_false_1; .long kwa_false_1_end-kwa_false_1; .long KID_FALSE
    .quad kwa_cast_0; .long kwa_cast_0_end-kwa_cast_0; .long KID_CAST
    .quad kwa_cast_1; .long kwa_cast_1_end-kwa_cast_1; .long KID_CAST
    .quad kwa_cast_2; .long kwa_cast_2_end-kwa_cast_2; .long KID_CAST
    .quad kwa_select_0; .long kwa_select_0_end-kwa_select_0; .long KID_SELECT
    .quad kwa_select_1; .long kwa_select_1_end-kwa_select_1; .long KID_SELECT
    .quad kwa_select_2; .long kwa_select_2_end-kwa_select_2; .long KID_SELECT
    .quad kwa_min_0; .long kwa_min_0_end-kwa_min_0; .long KID_MIN
    .quad kwa_min_1; .long kwa_min_1_end-kwa_min_1; .long KID_MIN
    .quad kwa_max_0; .long kwa_max_0_end-kwa_max_0; .long KID_MAX
    .quad kwa_max_1; .long kwa_max_1_end-kwa_max_1; .long KID_MAX
    .quad kwa_abs_0; .long kwa_abs_0_end-kwa_abs_0; .long KID_ABS
    .quad kwa_abs_1; .long kwa_abs_1_end-kwa_abs_1; .long KID_ABS
    .quad kwa_abs_2; .long kwa_abs_2_end-kwa_abs_2; .long KID_ABS
    .quad kwa_periodic_0; .long kwa_periodic_0_end-kwa_periodic_0; .long KID_PERIODIC
    .quad kwa_periodic_1; .long kwa_periodic_1_end-kwa_periodic_1; .long KID_PERIODIC
    .quad kwa_periodic_2; .long kwa_periodic_2_end-kwa_periodic_2; .long KID_PERIODIC
    .quad kwa_dictionary_0; .long kwa_dictionary_0_end-kwa_dictionary_0; .long KID_DICTIONARY
    .quad kwa_dictionary_1; .long kwa_dictionary_1_end-kwa_dictionary_1; .long KID_DICTIONARY
    .quad kwa_dictionary_2; .long kwa_dictionary_2_end-kwa_dictionary_2; .long KID_DICTIONARY
    .quad kwa_lookup_0; .long kwa_lookup_0_end-kwa_lookup_0; .long KID_LOOKUP
    .quad kwa_lookup_1; .long kwa_lookup_1_end-kwa_lookup_1; .long KID_LOOKUP
    .quad kwa_lookup_2; .long kwa_lookup_2_end-kwa_lookup_2; .long KID_LOOKUP
    .quad kwa_default_0; .long kwa_default_0_end-kwa_default_0; .long KID_DEFAULT
    .quad kwa_default_1; .long kwa_default_1_end-kwa_default_1; .long KID_DEFAULT
    .quad kwa_default_2; .long kwa_default_2_end-kwa_default_2; .long KID_DEFAULT
    .quad kwa_nested_0; .long kwa_nested_0_end-kwa_nested_0; .long KID_NESTED
    .quad kwa_nested_1; .long kwa_nested_1_end-kwa_nested_1; .long KID_NESTED
    .quad kwa_nested_2; .long kwa_nested_2_end-kwa_nested_2; .long KID_NESTED
    .quad kwa_nested_reduce_0; .long kwa_nested_reduce_0_end-kwa_nested_reduce_0; .long KID_NESTED_REDUCE
    .quad kwa_nested_reduce_1; .long kwa_nested_reduce_1_end-kwa_nested_reduce_1; .long KID_NESTED_REDUCE
    .quad kwa_nested_reduce_2; .long kwa_nested_reduce_2_end-kwa_nested_reduce_2; .long KID_NESTED_REDUCE
    .quad kwa_cascade_0; .long kwa_cascade_0_end-kwa_cascade_0; .long KID_CASCADE
    .quad kwa_cascade_1; .long kwa_cascade_1_end-kwa_cascade_1; .long KID_CASCADE
    .quad kwa_cascade_2; .long kwa_cascade_2_end-kwa_cascade_2; .long KID_CASCADE
    .quad kwa_executors_0; .long kwa_executors_0_end-kwa_executors_0; .long KID_EXECUTORS
    .quad kwa_executors_1; .long kwa_executors_1_end-kwa_executors_1; .long KID_EXECUTORS
    .quad kwa_executors_2; .long kwa_executors_2_end-kwa_executors_2; .long KID_EXECUTORS
    .quad kwa_chunk_0; .long kwa_chunk_0_end-kwa_chunk_0; .long KID_CHUNK
    .quad kwa_chunk_1; .long kwa_chunk_1_end-kwa_chunk_1; .long KID_CHUNK
    .quad kwa_chunk_2; .long kwa_chunk_2_end-kwa_chunk_2; .long KID_CHUNK
    .quad kwa_events_0; .long kwa_events_0_end-kwa_events_0; .long KID_EVENTS
    .quad kwa_events_1; .long kwa_events_1_end-kwa_events_1; .long KID_EVENTS
    .quad kwa_goal_0; .long kwa_goal_0_end-kwa_goal_0; .long KID_GOAL
    .quad kwa_goal_1; .long kwa_goal_1_end-kwa_goal_1; .long KID_GOAL
    .quad kwa_goal_2; .long kwa_goal_2_end-kwa_goal_2; .long KID_GOAL
    .quad kwa_work_0; .long kwa_work_0_end-kwa_work_0; .long KID_WORK
    .quad kwa_work_1; .long kwa_work_1_end-kwa_work_1; .long KID_WORK
    .quad kwa_relation_0; .long kwa_relation_0_end-kwa_relation_0; .long KID_RELATION
    .quad kwa_relation_1; .long kwa_relation_1_end-kwa_relation_1; .long KID_RELATION
    .quad kwa_relation_2; .long kwa_relation_2_end-kwa_relation_2; .long KID_RELATION
    .quad kwa_to_0; .long kwa_to_0_end-kwa_to_0; .long KID_TO
    .quad kwa_to_1; .long kwa_to_1_end-kwa_to_1; .long KID_TO
    .quad kwa_goal_result_0; .long kwa_goal_result_0_end-kwa_goal_result_0; .long KID_GOAL_RESULT
    .quad kwa_goal_result_1; .long kwa_goal_result_1_end-kwa_goal_result_1; .long KID_GOAL_RESULT
    .quad kwa_goal_result_2; .long kwa_goal_result_2_end-kwa_goal_result_2; .long KID_GOAL_RESULT
    .quad 0; .long 0; .long 0
.p2align 3
s_builtin_repair_table:
    .quad kw_xor;     .long 3; .long OP_BIT_XOR; .long 2; .long 0
    .quad kw_bit_and; .long 7; .long OP_BIT_AND; .long 2; .long 0
    .quad kw_bit_or;  .long 6; .long OP_BIT_OR;  .long 2; .long 0
    .quad kw_bit_xor; .long 7; .long OP_BIT_XOR; .long 2; .long 0
    .quad kw_shl;     .long 3; .long OP_SHL;     .long 2; .long 0
    .quad kw_shr;     .long 3; .long OP_SHR;     .long 2; .long 0
    .quad 0; .long 0; .long 0; .long 0; .long 0
# op strings
op_or:.ascii "or"; op_and:.ascii "and"; op_bit_or:.ascii "bit_or"; op_bit_xor:.ascii "bit_xor"; op_bit_and:.ascii "bit_and"
op_eq:.ascii "eq"; op_ne:.ascii "ne"; op_lt:.ascii "lt"; op_le:.ascii "le"; op_gt:.ascii "gt"; op_ge:.ascii "ge"
op_shl:.ascii "shl"; op_shr:.ascii "shr"; op_add:.ascii "add"; op_sub:.ascii "sub"; op_mul:.ascii "mul"; op_div:.ascii "div"; op_mod:.ascii "mod"
op_not:.ascii "not"; op_bit_not:.ascii "bit_not"; op_neg:.ascii "neg"; op_select:.ascii "select"; op_min:.ascii "min"; op_max:.ascii "max"; op_abs:.ascii "abs"; op_ushr:.ascii "ushr"
# JSON fragments
js_lit_prefix:.asciz "{\"literal\":"
js_type_mid:.asciz ",\"type\":"
js_var_prefix:.asciz "{\"var\":"
js_axis_prefix:.asciz "{\"axis\":"
js_state_prefix:.asciz "{\"state\":"
js_op_prefix:.asciz "{\"op\":"
js_args_mid:.asciz ",\"args\":["
js_arr_obj_close:.asciz "]}"
js_cast_prefix:.asciz "{\"op\":\"cast\",\"to\":"
js_cast_mid:.asciz ",\"args\":["
js_load_prefix:.asciz "{\"load\":"
js_indices_mid:.asciz ",\"indices\":["
js_type_obj_base:.asciz "{\"base\":"
js_tol_mid_abs:.asciz ",\"mode\":\"tolerant\",\"absolute_error\":"
js_tol_mid_rel:.asciz ",\"relative_error\":"
js_axis_obj_name:.asciz "{\"name\":"
js_extent_mid:.asciz ",\"extent\":"
js_extent_var_n:.asciz ",\"extent\":{\"var\":\"n\"}}]"
js_name_key:.asciz "\"name\":"
js_type_key:.asciz ",\"type\":"
js_min_key:.asciz ",\"min\":"
js_max_key:.asciz ",\"max\":"
js_binding_name:.asciz "{\"name\":"
js_compute_prefix:.asciz ",\"op\":\"compute\""
js_compute_mid:.asciz ",\"op\":\"compute\",\"expr\":"
js_output_label:.asciz "{\"label\":"
js_output_expr_mid:.asciz ",\"expr\":"
js_test_args:.asciz "{\"args\":["
js_expected_mid:.asciz "],\"expected\":{"
js_test_close:.asciz "}}"
js_iterate_mid:.asciz ",\"op\":\"iterate\",\"states\":["
js_state_obj_name:.asciz "{\"name\":"
js_init_key:.asciz ",\"init\":"
js_condition_mid:.asciz "],\"condition\":"
js_update_mid:.asciz ",\"update\":{"
js_result_mid:.asciz "},\"result\":"
js_maxiter_mid:.asciz ",\"max_iterations\":"
js_map_mid_axes:.asciz ",\"op\":\"map\",\"axes\":"
js_expr_key:.asciz ",\"expr\":"
js_reduce_mid_axes:.asciz ",\"op\":\"reduce\",\"kind\":\"sum\",\"axes\":"
js_acc_key:.asciz ",\"accumulator\":"
js_reduce_kind_mid:.asciz ",\"kind\":"
js_reduce_sum_expr:.asciz ",\"expr\":"
js_acc_tol_prefix:.asciz "{\"base\":\"f64\",\"mode\":\"tolerant\",\"absolute_error\":"
js_acc_tol_rel:.asciz ",\"relative_error\":"
js_root_format:.asciz "{\"format\":\"wheelchair.tensor/1\",\"program\":"
js_contract_prefix:.asciz ",\"contracts\":{\"deterministic\":"
js_overflow_mid:.asciz ",\"integer_overflow\":"
js_fp_mid:.asciz ",\"floating_point\":"
js_mixed_mid:.asciz ",\"mixed_precision\":\"lower_precision_dominates\""
js_inputs_prefix:.asciz "},\"inputs\":["
js_bindings_mid:.asciz "],\"bindings\":["
js_outputs_mid:.asciz "],\"outputs\":["
js_tests_mid:.asciz "],\"tests\":["
js_general_lane:.asciz ",\"_compiler_lane\":\"wheelchair.general/1\""
js_rank_product:.asciz ",\"rank_n_product\":"
js_rank_source:.asciz ",\"rank_n_source_rank\":"

.section .bss
.p2align 6
s_src:.skip 8
s_cur:.skip 8
s_end:.skip 8
s_mode:.skip 4
s_error:.skip 4
s_general_lane:.skip 4
s_deterministic:.skip 4
s_overflow_wrap:.skip 4
s_fp_tolerant:.skip 4
s_tol_ptr:.skip 8
s_tol_len:.skip 8
s_program_ptr:.skip 8
s_program_len:.skip 8
s_input_count:.skip 4
s_binding_count:.skip 4
s_output_count:.skip 4
s_test_count:.skip 4
s_ast_count:.skip 4
s_axis_count:.skip 4
s_state_count:.skip 4
s_rank_count:.skip 4
s_rank_static_bits:.skip 4
s_rank_static_factor:.skip 8
s_rankn_active:.skip 4
s_rankn_source_rank:.skip 4
s_rankn_product:.skip 8
s_out_ptr:.skip 8
s_out_limit:.skip 8
s_inputs_end:.skip 8
s_bindings_end:.skip 8
s_outputs_end:.skip 8
s_tests_end:.skip 8
surface_json_length:.skip 8
s_axis_ptrs:.skip SCOPE_MAX*8
s_axis_lens:.skip SCOPE_MAX*8
s_state_ptrs:.skip SCOPE_MAX*8
s_state_lens:.skip SCOPE_MAX*8
s_rank_axis_ptrs:.skip RANK_MAX*8
s_rank_axis_lens:.skip RANK_MAX*8
s_rank_dynamic:.skip RANK_MAX*4
s_rank_extent:.skip RANK_MAX*8
s_rank_low_bit:.skip RANK_MAX*4
s_iter_limit_ast:.skip 8
s_iter_condition_ast:.skip 8
s_iter_result_ptr:.skip 8
s_iter_result_len:.skip 8
s_iter_update_count:.skip 4
s_iter_state_name_ptr:.skip SCOPE_MAX*8
s_iter_state_name_len:.skip SCOPE_MAX*8
s_iter_state_type_ptr:.skip SCOPE_MAX*8
s_iter_state_type_len:.skip SCOPE_MAX*8
s_iter_state_init_ast:.skip SCOPE_MAX*8
s_iter_update_name_ptr:.skip SCOPE_MAX*8
s_iter_update_name_len:.skip SCOPE_MAX*8
s_iter_update_ast:.skip SCOPE_MAX*8
s_record_field_count:.skip 4
s_function_count:.skip 4
s_record_name_ptr:.skip 64*8
s_record_name_len:.skip 64*8
s_record_field_ptr:.skip 64*8
s_record_field_len:.skip 64*8
s_record_value_ast:.skip 64*8
s_function_name_ptr:.skip 16*8
s_function_name_len:.skip 16*8
s_function_param_ptr:.skip 16*8
s_function_param_len:.skip 16*8
s_function_expr_ast:.skip 16*8
s_decl_count:.skip 4
s_decl_ptrs:.skip DECL_MAX*8
s_decl_lens:.skip DECL_MAX*8
s_repair_split_end:.skip 8
s_repair_split_len:.skip 8
s_dictionary_count:.skip 4
s_dictionary_entry_count:.skip 4
s_dictionary_name_ptr:.skip DICT_MAX*8
s_dictionary_name_len:.skip DICT_MAX*8
s_dictionary_entry_dict:.skip DICT_ENTRY_MAX*4
s_dictionary_entry_key:.skip DICT_ENTRY_MAX*8
s_dictionary_entry_value:.skip DICT_ENTRY_MAX*8
s_nested_count:.skip 4
s_nested_name_ptr:.skip NESTED_MAX*8
s_nested_name_len:.skip NESTED_MAX*8
s_nested_sum_ast:.skip NESTED_MAX*8
s_nested_item_count:.skip NESTED_MAX*8
s_nested_segment_count:.skip NESTED_MAX*8
s_nested_build_sum:.skip 8
s_nested_item_ast:.skip 8
s_cascade_goal_count:.skip 4
s_cascade_axis_enabled:.skip 4
s_cascade_axis_ptr:.skip 8
s_cascade_axis_len:.skip 8
s_cascade_axis_value:.skip 8
s_cascade_goal_name_ptr:.skip CASCADE_GOAL_MAX*8
s_cascade_goal_name_len:.skip CASCADE_GOAL_MAX*8
s_cascade_goal_work_ast:.skip CASCADE_GOAL_MAX*8
s_cascade_goal_expr_ast:.skip CASCADE_GOAL_MAX*8
s_cascade_goal_prereq:.skip CASCADE_GOAL_MAX*8
s_cascade_goal_done:.skip CASCADE_GOAL_MAX*4
s_cascade_goal_result:.skip CASCADE_GOAL_MAX*8
s_cascade_eval_goal_idx:.skip 4
s_cascade_eval_progressed:.skip 4
s_cascade_eval_work:.skip 8
s_cascade_eval_unit:.skip 8
s_cascade_eval_total:.skip 8
s_num_scratch:.skip 32
.p2align 6
s_ast_nodes:.skip SAST_MAX*SAST_SIZE
.p2align 6
s_inputs_buf:.skip SBUF_INPUTS_CAP
s_bindings_buf:.skip SBUF_BINDINGS_CAP
s_outputs_buf:.skip SBUF_OUTPUTS_CAP
s_tests_buf:.skip SBUF_TESTS_CAP
.p2align 6
surface_json_buffer:.skip SBUF_FINAL_CAP
