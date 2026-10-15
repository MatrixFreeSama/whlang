# Compile-time structural member spans. rdi=object bytes, rsi=length,
# rdx=literal key, ecx=key bytes -> rax=value bytes, rdx=value length / 0.
# One scanner is consumed by every format/shape discriminator. Strings and
# nested containers are skipped as complete values; their contents are data.
.global surface_json_member
surface_json_member:
    push rbx; push r12; push r13; push r14; push r15
    mov rbx,rdx; mov r12d,ecx
    mov r10,rdi; lea r9,[rdi+rsi]
    call .sjm_ws
    cmp al,'{'; jne .sjm_absent
    inc r10
.sjm_member:
    call .sjm_ws
    cmp al,'"'; jne .sjm_absent
    lea r14,[r10+1]
    call .sjm_string
    test eax,eax; jz .sjm_absent
    lea r13,[r10-1]; sub r13,r14
    xor r15d,r15d
    cmp r13,r12; jne .sjm_key_done
    xor ecx,ecx
.sjm_key:
    cmp rcx,r12; jae .sjm_key_equal
    mov al,[r14+rcx]; cmp al,[rbx+rcx]; jne .sjm_key_done
    inc rcx; jmp .sjm_key
.sjm_key_equal: mov r15d,1
.sjm_key_done:
    call .sjm_ws
    cmp al,':'; jne .sjm_absent
    inc r10
    call .sjm_ws
    mov r14,r10
    xor r13d,r13d
.sjm_value:
    cmp r10,r9; jae .sjm_absent
    mov al,[r10]
    cmp al,'"'; je .sjm_value_string
    cmp al,'{'; je .sjm_open
    cmp al,'['; je .sjm_open
    cmp al,'}'; je .sjm_close
    cmp al,']'; je .sjm_close
    cmp al,','; jne .sjm_advance
    test r13,r13; jz .sjm_value_end
.sjm_advance: inc r10; jmp .sjm_value
.sjm_open: inc r13; jmp .sjm_advance
.sjm_close:
    test r13,r13; jz .sjm_value_end
    dec r13; jmp .sjm_advance
.sjm_value_string:
    call .sjm_string
    test eax,eax; jz .sjm_absent
    jmp .sjm_value
.sjm_value_end:
    test r15d,r15d; jnz .sjm_found
    cmp byte ptr [r10],','; jne .sjm_absent
    inc r10; jmp .sjm_member
.sjm_found:
    mov rax,r14
    mov rdx,r10
.sjm_trim:
    cmp rdx,r14; jbe .sjm_absent
    mov cl,[rdx-1]
    cmp cl,' '; je .sjm_trim_one
    cmp cl,9; je .sjm_trim_one
    cmp cl,10; je .sjm_trim_one
    cmp cl,13; jne .sjm_length
.sjm_trim_one: dec rdx; jmp .sjm_trim
.sjm_length: sub rdx,r14; jmp .sjm_done
.sjm_absent: xor eax,eax; xor edx,edx
.sjm_done: pop r15; pop r14; pop r13; pop r12; pop rbx; ret
.sjm_ws:
    cmp r10,r9; jae .sjm_ws_end
    mov al,[r10]
    cmp al,' '; je .sjm_ws_one
    cmp al,9; je .sjm_ws_one
    cmp al,10; je .sjm_ws_one
    cmp al,13; jne .sjm_ws_ret
.sjm_ws_one: inc r10; jmp .sjm_ws
.sjm_ws_end: xor eax,eax
.sjm_ws_ret: ret
.sjm_string:
    inc r10
.sjm_string_byte:
    cmp r10,r9; jae .sjm_string_bad
    mov al,[r10]; inc r10
    cmp al,'"'; je .sjm_string_ok
    cmp al,'\\'; jne .sjm_string_byte
    cmp r10,r9; jae .sjm_string_bad
    inc r10; jmp .sjm_string_byte
.sjm_string_ok: mov eax,1; ret
.sjm_string_bad: xor eax,eax; ret

# Same bounded value span, compared to a quoted literal. rdi=span, rsi=bytes,
# rdx=literal contents, ecx=content bytes -> eax=equal. No global text search.
.global surface_json_string_equal
surface_json_string_equal:
    lea eax,[rcx+2]
    cmp rsi,rax; jne .sjse_no
    cmp byte ptr [rdi],'"'; jne .sjse_no
    cmp byte ptr [rdi+rsi-1],'"'; jne .sjse_no
    xor r8d,r8d
.sjse_next:
    cmp r8d,ecx; jae .sjse_yes
    mov al,[rdi+r8+1]; cmp al,[rdx+r8]; jne .sjse_no
    inc r8; jmp .sjse_next
.sjse_yes: mov eax,1; ret
.sjse_no: xor eax,eax; ret
