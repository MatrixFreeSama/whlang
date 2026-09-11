.intel_syntax noprefix
.global _start

.equ SYS_read,0
.equ SYS_close,3
.equ SYS_lseek,8
.equ SYS_execve,59
.equ SYS_exit,60
.equ SYS_readlink,89
.equ SYS_openat,257
.equ AT_FDCWD,-100
.equ SEEK_END,2
.equ SEEK_SET,0
.equ MAX_SOURCE,8388608

.section .bss
.align 16
.global source_ptr
.global source_length
source_ptr: .quad 0
source_length: .quad 0
load_hash_count: .long 0
.align 8
load_hashes: .skip 512
exe_path: .skip 4096
selected_path: .skip 4096
argv_copy: .skip 2056
source_buf: .skip MAX_SOURCE+1
dir_len: .quad 0
source_len: .quad 0

.section .text
_start:
    mov r15,rsp
    mov r14,[r15]
    cmp r14,2
    jb .usage
    lea r13,[r15+8]
    lea r12,[r13+r14*8+8]

    mov eax,SYS_readlink
    lea rdi,[rip+proc_self_exe]
    lea rsi,[rip+exe_path]
    mov edx,4095
    syscall
    test rax,rax
    jle .fail
    lea rbx,[rip+exe_path]
    mov byte ptr [rbx+rax],0
    mov rcx,rax
.find_slash:
    test rcx,rcx
    jz .fail
    dec rcx
    cmp byte ptr [rbx+rcx],'/'
    jne .find_slash
    inc rcx
    mov [rip+dir_len],rcx

    mov eax,SYS_openat
    mov edi,AT_FDCWD
    mov rsi,[r13+8]
    xor edx,edx
    xor r10d,r10d
    syscall
    test rax,rax
    js .fail
    mov rbx,rax

    mov eax,SYS_lseek
    mov rdi,rbx
    xor esi,esi
    mov edx,SEEK_END
    syscall
    test rax,rax
    js .close_fail
    cmp rax,MAX_SOURCE
    ja .close_fail
    mov [rip+source_len],rax
    mov eax,SYS_lseek
    mov rdi,rbx
    xor esi,esi
    mov edx,SEEK_SET
    syscall
    test rax,rax
    js .close_fail

    mov rdx,[rip+source_len]
    test rdx,rdx
    jz .close_fail
    xor r8d,r8d
.read_loop:
    cmp r8,rdx
    jae .read_done
    mov eax,SYS_read
    mov rdi,rbx
    lea rsi,[rip+source_buf]
    add rsi,r8
    mov r10,rdx
    sub r10,r8
    mov rdx,r10
    syscall
    test rax,rax
    jle .close_fail
    add r8,rax
    mov rdx,[rip+source_len]
    jmp .read_loop
.read_done:
    mov eax,SYS_close
    mov rdi,rbx
    syscall
    lea r9,[rip+source_buf]
    mov r10,[rip+source_len]
    mov byte ptr [r9+r10],0
    mov [rip+source_ptr],r9
    mov [rip+source_length],r10

    # Canonicalize human WH/WHEX in-process using the handwritten assembly
    # surface lowerer.  This is classification only: the selected backend later
    # re-opens the original source and compiles it once.  No failure-driven
    # backend retry is introduced.
    xor r8d,r8d
.nd_skip_ws:
    cmp r8,r10
    jae .base
    mov al,[r9+r8]
    cmp al,' '
    je .nd_ws_next
    cmp al,9
    je .nd_ws_next
    cmp al,10
    je .nd_ws_next
    cmp al,13
    je .nd_ws_next
    cmp al,'{'
    je .nd_have_canonical
    mov rdi,[r13+8]
    call surface_lower_to_json
    test eax,eax
    jnz .base
    mov r9,[rip+source_ptr]
    mov r10,[rip+source_length]
    jmp .nd_have_canonical
.nd_ws_next:
    inc r8
    jmp .nd_skip_ws

.nd_have_canonical:
    # Derived Rank-N authority has priority over register-pressure profiles.
    mov rdi,r9
    lea rsi,[rip+rank_marker]
    mov edx,rank_marker_end-rank_marker
    mov rcx,r10
    call memcontains
    test eax,eax
    jnz .derived

    # Resource class is chosen from the canonical graph before code generation.
    # Count distinct structural load objects.  Historical profile thresholds are
    # preserved exactly: base <=10, wide 11..14, base recompute >14.
    mov rdi,r9
    mov rsi,r10
    call profile_pressure
    cmp eax,11
    jb .base
    cmp eax,14
    jbe .wide
    jmp .base

.wide:
    lea rsi,[rip+name_wide]
    mov edx,name_wide_end-name_wide
    jmp .select
.derived:
    lea rsi,[rip+name_derived]
    mov edx,name_derived_end-name_derived
    jmp .select
.base:
    lea rsi,[rip+name_base]
    mov edx,name_base_end-name_base
.select:
    lea rdi,[rip+selected_path]
    lea rbx,[rip+exe_path]
    xor r8d,r8d
    mov rcx,[rip+dir_len]
.copy_dir:
    cmp r8,rcx
    jae .copy_name
    mov al,[rbx+r8]
    mov [rdi+r8],al
    inc r8
    jmp .copy_dir
.copy_name:
    xor eax,eax
.copy_nloop:
    cmp eax,edx
    jae .name_done
    mov bl,[rsi+rax]
    mov [rdi+r8],bl
    inc r8
    inc eax
    jmp .copy_nloop
.name_done:
    mov byte ptr [rdi+r8],0

    lea rbx,[rip+argv_copy]
    lea rax,[rip+selected_path]
    mov [rbx],rax
    mov rcx,1
.argv_loop:
    cmp rcx,r14
    jae .argv_done
    mov rax,[r13+rcx*8]
    mov [rbx+rcx*8],rax
    inc rcx
    jmp .argv_loop
.argv_done:
    mov qword ptr [rbx+rcx*8],0
    mov eax,SYS_execve
    lea rdi,[rip+selected_path]
    lea rsi,[rip+argv_copy]
    mov rdx,r12
    syscall
    jmp .fail

# profile_pressure(rdi=canonical JSON ptr, rsi=len) -> eax distinct structural loads.
# A structural load object emitted by the canonical surface has `"load"` as its
# first key.  Hash the full object while ignoring JSON whitespace outside strings;
# nested index expressions therefore distinguish i, i-1, i+1, etc.  The small
# fixed hash set is compile-time metadata only and never enters generated code.
profile_pressure:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi
    mov r13,rsi
    mov dword ptr [rip+load_hash_count],0
    xor r14d,r14d
.pp_scan:
    lea rax,[r14+6]
    cmp rax,r13
    ja .pp_done
    lea rbx,[r12+r14]
    cmp byte ptr [rbx],'"'; jne .pp_next
    cmp byte ptr [rbx+1],'l'; jne .pp_next
    cmp byte ptr [rbx+2],'o'; jne .pp_next
    cmp byte ptr [rbx+3],'a'; jne .pp_next
    cmp byte ptr [rbx+4],'d'; jne .pp_next
    cmp byte ptr [rbx+5],'"'; jne .pp_next
    # Require this to be the first key in an object: previous nonspace byte is '{'.
    mov r15,r14
.pp_back:
    test r15,r15
    jz .pp_next
    dec r15
    mov al,[r12+r15]
    cmp al,' '; je .pp_back
    cmp al,9; je .pp_back
    cmp al,10; je .pp_back
    cmp al,13; je .pp_back
    cmp al,'{'; jne .pp_next
    # Hash object [r15, matching closing brace], whitespace-normalized outside strings.
    mov r8,1469598103934665603
    xor r9d,r9d                 # object brace depth
    xor r10d,r10d               # in-string flag
    xor r11d,r11d               # escape flag
    mov rcx,r15
.pp_hash_loop:
    cmp rcx,r13
    jae .pp_next
    movzx eax,byte ptr [r12+rcx]
    test r10d,r10d
    jnz .pp_in_string
    cmp al,'"'; je .pp_string_open
    cmp al,' '; je .pp_hash_advance
    cmp al,9; je .pp_hash_advance
    cmp al,10; je .pp_hash_advance
    cmp al,13; je .pp_hash_advance
    cmp al,'{'; jne .pp_check_close
    inc r9d
    jmp .pp_hash_byte
.pp_check_close:
    cmp al,'}'; jne .pp_hash_byte
    dec r9d
    jmp .pp_hash_byte_after_close
.pp_string_open:
    mov r10d,1
    xor r11d,r11d
    jmp .pp_hash_byte
.pp_in_string:
    test r11d,r11d
    jnz .pp_escaped
    cmp al,'\\'; je .pp_set_escape
    cmp al,'"'; jne .pp_hash_byte
    xor r10d,r10d
    jmp .pp_hash_byte
.pp_set_escape:
    mov r11d,1
    jmp .pp_hash_byte
.pp_escaped:
    xor r11d,r11d
.pp_hash_byte:
    xor r8b,al
    mov rax,1099511628211
    imul r8,rax
    jmp .pp_hash_advance
.pp_hash_byte_after_close:
    xor r8b,al
    mov rax,1099511628211
    imul r8,rax
    test r9d,r9d
    jz .pp_have_hash
.pp_hash_advance:
    inc rcx
    jmp .pp_hash_loop
.pp_have_hash:
    # Deduplicate 64-bit structural signatures.
    mov edx,dword ptr [rip+load_hash_count]
    xor edi,edi
    lea rsi,[rip+load_hashes]
.pp_find_hash:
    cmp edi,edx
    jae .pp_new_hash
    cmp qword ptr [rsi+rdi*8],r8
    je .pp_after_hash
    inc edi
    jmp .pp_find_hash
.pp_new_hash:
    cmp edx,64
    jae .pp_saturate
    mov qword ptr [rsi+rdx*8],r8
    inc edx
    mov dword ptr [rip+load_hash_count],edx
    jmp .pp_after_hash
.pp_saturate:
    mov dword ptr [rip+load_hash_count],65
.pp_after_hash:
    mov r14,rcx
.pp_next:
    inc r14
    jmp .pp_scan
.pp_done:
    mov eax,dword ptr [rip+load_hash_count]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

memcontains:
    push rbx
    push r12
    push r13
    mov r12d,edx
    cmp rcx,r12
    jb .mc_no
    sub rcx,r12
    xor ebx,ebx
.mc_outer:
    cmp rbx,rcx
    ja .mc_no
    xor r13d,r13d
.mc_inner:
    cmp r13d,r12d
    jae .mc_yes
    lea rax,[rdi+rbx]
    mov dl,[rax+r13]
    cmp dl,[rsi+r13]
    jne .mc_next
    inc r13d
    jmp .mc_inner
.mc_next:
    inc rbx
    jmp .mc_outer
.mc_yes:
    mov eax,1
    pop r13
    pop r12
    pop rbx
    ret
.mc_no:
    xor eax,eax
    pop r13
    pop r12
    pop rbx
    ret

.close_fail:
    mov eax,SYS_close
    mov rdi,rbx
    syscall
.fail:
    mov edi,66
    mov eax,SYS_exit
    syscall
.usage:
    mov edi,64
    mov eax,SYS_exit
    syscall

.section .rodata
proc_self_exe: .asciz "/proc/self/exe"
rank_marker: .ascii "\"rank_n_product\""
rank_marker_end:
name_base: .ascii "topologyc"
name_base_end:
name_wide: .ascii "topologyc-wide"
name_wide_end:
name_derived: .ascii "topologyc-derived"
name_derived_end:
