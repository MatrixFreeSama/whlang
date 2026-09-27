.intel_syntax noprefix
.global _start
.extern surface_field_lower_to_json

.equ SYS_read,0
.equ SYS_close,3
.equ SYS_lseek,8
.equ SYS_mmap,9
.equ SYS_execve,59
.equ SYS_exit,60
.equ SYS_readlink,89
.equ SYS_openat,257
.equ AT_FDCWD,-100
.equ SEEK_END,2
.equ SEEK_SET,0
.equ PROT_READ,1
.equ MAP_PRIVATE,2

.section .bss
.align 16
.global source_ptr
.global source_length
source_ptr: .quad 0
source_length: .quad 0
exe_path: .skip 4096
selected_path: .skip 4096
argv_copy: .skip 2056
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
    mov [rip+source_len],rax
    test rax,rax
    jz .close_fail

    # Classification is read-only and every parser is length bounded. Map the
    # actual source file instead of reserving an unrelated 8 MiB compiler slab.
    # Source size is therefore a host virtual-memory/file-system frontier, not a
    # language constant.
    mov rsi,rax
    mov eax,SYS_mmap
    xor edi,edi
    mov edx,PROT_READ
    mov r10d,MAP_PRIVATE
    mov r8,rbx
    xor r9d,r9d
    syscall
    test rax,rax
    js .close_fail
    mov r9,rax
    mov [rip+source_ptr],rax
    mov r10,[rip+source_len]
    mov [rip+source_length],r10
    mov eax,SYS_close
    mov rdi,rbx
    syscall

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
    # Native materialized-field WH/WHEX gets first-class structural
    # classification before the ordinary tensor/general surface. A failed field
    # recognition is only a frontend classification miss, never backend retry.
    mov rdi,[r13+8]
    call surface_field_lower_to_json
    test eax,eax
    jz .nd_field_surface
    cmp eax,2
    je .field
    mov rdi,[r13+8]
    call surface_lower_to_json
    test eax,eax
    jnz .base
    mov r9,[rip+source_ptr]
    mov r10,[rip+source_length]
    jmp .nd_have_canonical
.nd_field_surface:
    mov r9,[rip+source_ptr]
    mov r10,[rip+source_length]
    jmp .nd_have_canonical
.nd_ws_next:
    inc r8
    jmp .nd_skip_ws

.nd_have_canonical:
    # Canonical materialized-field semantics select the sovereign 1.2.17 field
    # AOT compiler structurally. This is format dispatch, not workload-name or
    # failure-driven selection, and happens before any backend code generation.
    mov rdi,r9
    lea rsi,[rip+field_marker]
    mov edx,field_marker_end-field_marker
    mov rcx,r10
    call memcontains
    test eax,eax
    jnz .field

    # ShapeFact-N is the logical-shape authority, but consumer choice follows
    # the shape itself.  Rank-1/product-1 belongs to the base physicalizer; only
    # a genuinely productized shape requires the derived consumer.  Presence of
    # ShapeFact-N alone must never force derived code generation.
    mov rdi,r9
    lea rsi,[rip+shape_marker]
    mov edx,shape_marker_end-shape_marker
    mov rcx,r10
    call memcontains
    test eax,eax
    jz .base
    mov rdi,r9
    mov rcx,r10
    call shape_fact_requires_derived
    test eax,eax
    jnz .derived
    jmp .base

    # One topology compiler owns physical materialization. Register pressure is
    # solved only after the complete Physical DAG exists; the launcher no longer
    # guesses a base/wide implementation from a structural-load count.
    jmp .base

.field:
    lea rsi,[rip+name_field]
    mov edx,name_field_end-name_field
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

# rdi=canonical bytes, rcx=length.  Return eax=1 only when ShapeFact-N contains
# two or more top-level axis objects.  This is classification of an already
# existing consumer boundary, not a second shape parser or a fallback path.
# Whitespace and JSON strings are tolerated so direct canonical input and the
# in-process Surface canonicalization use the same rule.
shape_fact_requires_derived:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12,rdi                         # buffer
    mov r13,rcx                         # length
    mov r14d,shape_marker_end-shape_marker
    lea rsi,[rip+shape_marker]
    cmp r13,r14
    jb .sfrd_base
    xor ebx,ebx                         # candidate offset
    mov r15,r13
    sub r15,r14                         # final legal marker offset
.sfrd_find_marker:
    cmp rbx,r15
    ja .sfrd_base
    xor edx,edx
.sfrd_match_marker:
    cmp edx,r14d
    jae .sfrd_marker_found
    lea rax,[r12+rbx]
    mov al,[rax+rdx]
    cmp al,[rsi+rdx]
    jne .sfrd_next_candidate
    inc edx
    jmp .sfrd_match_marker
.sfrd_next_candidate:
    inc rbx
    jmp .sfrd_find_marker

.sfrd_marker_found:
    add rbx,r14                         # scan after "shape_fact_n"
.sfrd_find_array:
    cmp rbx,r13
    jae .sfrd_base
    mov al,[r12+rbx]
    inc rbx
    cmp al,'['
    jne .sfrd_find_array

    xor r14d,r14d                       # object nesting depth
    xor r15d,r15d                       # top-level axis count
    xor edx,edx                         # bit0=in string, bit1=escape
.sfrd_scan_axes:
    cmp rbx,r13
    jae .sfrd_base
    mov al,[r12+rbx]
    inc rbx
    test dl,1
    jz .sfrd_not_string
    test dl,2
    jnz .sfrd_clear_escape
    cmp al,'\\'
    je .sfrd_set_escape
    cmp al,'"'
    jne .sfrd_scan_axes
    and dl,0xfe
    jmp .sfrd_scan_axes
.sfrd_set_escape:
    or dl,2
    jmp .sfrd_scan_axes
.sfrd_clear_escape:
    and dl,0xfd
    jmp .sfrd_scan_axes
.sfrd_not_string:
    cmp al,'"'
    je .sfrd_enter_string
    cmp al,'{'
    je .sfrd_open_object
    cmp al,'}'
    je .sfrd_close_object
    cmp al,']'
    je .sfrd_close_array
    jmp .sfrd_scan_axes
.sfrd_enter_string:
    or dl,1
    jmp .sfrd_scan_axes
.sfrd_open_object:
    test r14d,r14d
    jnz .sfrd_nested_object
    inc r15d
    cmp r15d,2
    jae .sfrd_derived
.sfrd_nested_object:
    inc r14d
    jmp .sfrd_scan_axes
.sfrd_close_object:
    test r14d,r14d
    jz .sfrd_base
    dec r14d
    jmp .sfrd_scan_axes
.sfrd_close_array:
    test r14d,r14d
    jnz .sfrd_scan_axes
    jmp .sfrd_base

.sfrd_derived:
    mov eax,1
    jmp .sfrd_done
.sfrd_base:
    xor eax,eax
.sfrd_done:
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
field_marker: .ascii "wheelchair.field/1"
field_marker_end:
shape_marker: .ascii "\"shape_fact_n\""
shape_marker_end:
name_field: .ascii "fieldc"
name_field_end:
name_base: .ascii "topologyc"
name_base_end:
name_derived: .ascii "topologyc-derived"
name_derived_end:
