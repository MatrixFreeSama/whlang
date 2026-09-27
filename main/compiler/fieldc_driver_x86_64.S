.intel_syntax noprefix
.equ SYS_read,0
.equ SYS_write,1
.equ SYS_close,3
.equ SYS_openat,257
.equ SYS_lseek,8
.equ SYS_mmap,9
.equ SYS_exit,60
.equ AT_FDCWD,-100
.equ O_RDONLY,0
.equ SEEK_END,2
.equ SEEK_SET,0
.equ PROT_READ,1
.equ MAP_PRIVATE,2
.extern compile_field_source
.extern surface_field_lower_to_json
.extern load_outward_materialization_ticks
.extern outward_materialization_ticks
.extern human_shell_report_success
.extern human_shell_report_error
.extern silicon_domain_probe
.extern sd_execution_admission_capacity
.global _start
.global source_ptr
.global source_length
.global execution_admission_capacity
.section .text
_start:
    call detect_target_parallel_width
    call load_outward_materialization_ticks
    mov r15,rsp
    mov r14,[r15]
    cmp r14,4
    jne .usage
    # argv[2] == -o
    mov rdi,[r15+24]; lea rsi,[rip+opt_o]; call streq
    test eax,eax; jz .usage
    # Target parallel width is an immutable compiler-time Physical Reality fact.
    # fieldc accepts no worker-count or chunk-size option.
    # read source
    mov eax,SYS_openat; mov edi,AT_FDCWD; mov rsi,[r15+16]; mov edx,O_RDONLY; xor r10d,r10d; syscall
    test rax,rax; js .fail
    mov r12,rax
    mov eax,SYS_lseek; mov rdi,r12; xor esi,esi; mov edx,SEEK_END; syscall
    test rax,rax; js .closefail
    test rax,rax; jz .closefail
    mov [rip+source_length],rax
    # The parser is length bounded, so the source can be mapped directly.  No
    # fixed compiler source slab and no source-size language ceiling remain.
    mov rsi,rax
    mov eax,SYS_mmap; xor edi,edi; mov edx,PROT_READ; mov r10d,MAP_PRIVATE; mov r8,r12; xor r9d,r9d; syscall
    test rax,rax; js .closefail
    mov r13,rax; mov [rip+source_ptr],rax
    mov eax,SYS_close; mov rdi,r12; syscall
    # Human WH/WHEX native-field sources are lowered in-process by the same
    # handwritten assembly surface parser used for classification. Canonical
    # wheelchair.field/1 JSON continues to enter compile_field_source directly.
    mov rax,[rip+source_ptr]
    mov rcx,[rip+source_length]
    xor r8d,r8d
.fcd_surface_skip:
    cmp r8,rcx; jae .reject
    mov dl,[rax+r8]
    cmp dl,' '; je .fcd_surface_next
    cmp dl,9; je .fcd_surface_next
    cmp dl,10; je .fcd_surface_next
    cmp dl,13; je .fcd_surface_next
    cmp dl,'{'; je .fcd_compile
    mov rdi,[r15+16]
    call surface_field_lower_to_json
    test eax,eax; jz .fcd_compile
    cmp eax,2; je .surface_reject
    jmp .reject
.fcd_surface_next:
    inc r8; jmp .fcd_surface_skip
.fcd_compile:
    mov rdi,[r15+32]
    call compile_field_source
    test eax,eax; jnz .compile_reject
    call human_shell_report_success
    xor edi,edi; mov eax,SYS_exit; syscall
.compile_reject:
    call human_shell_report_error
    jmp .reject
.surface_reject:
    call human_shell_report_error
    test eax,eax; jnz .reject
    lea rsi,[rip+msg_surface_generic]
    mov edx,msg_surface_generic_end-msg_surface_generic
    mov eax,SYS_write; mov edi,2; syscall
    jmp .reject
.closefail:
    mov eax,SYS_close; mov rdi,r12; syscall
.fail: mov edi,66; mov eax,SYS_exit; syscall
.reject: mov edi,65; mov eax,SYS_exit; syscall
.usage: mov edi,64; mov eax,SYS_exit; syscall

# Discover exact external execution admission. This is compile-time Physical
# Reality, not runtime free-capacity accounting and never creates or reserves
# workers. Locality identity remains a separate placement fact.
detect_target_parallel_width:
    # Field still supplies deterministic LLC sharing width when exposed, but
    # unknown LLC identity no longer erases affinity/quota execution admission.
    call detect_field_llc_share_threads
    xor edi,edi
    xor esi,esi
    mov edx,eax
    call silicon_domain_probe
    mov eax,dword ptr [rip+sd_execution_admission_capacity]
    test eax,eax
    jnz .dtpw_store
    mov eax,1
.dtpw_store:
    mov dword ptr [rip+execution_admission_capacity],eax
    ret

# Return EAX = logical contexts in the architectural L3 sharing domain, or 0
# when the target exposes no deterministic L3 topology. Vendor/model identity is
# deliberately irrelevant. This is compile-time silicon geometry only.
detect_field_llc_share_threads:
    push rbx
    push r12
    xor r12d,r12d
    mov eax,0x80000000
    cpuid
    cmp eax,0x8000001d
    jb .dfllc_basic
    mov r11d,0x8000001d
    jmp .dfllc_loop_init
.dfllc_basic:
    xor eax,eax
    cpuid
    cmp eax,4
    jb .dfllc_done
    mov r11d,4
.dfllc_loop_init:
    xor r10d,r10d
.dfllc_loop:
    mov eax,r11d
    mov ecx,r10d
    cpuid
    mov edx,eax
    and edx,0x1f
    test edx,edx
    jz .dfllc_done
    mov edx,eax
    shr edx,5
    and edx,7
    cmp edx,3
    jne .dfllc_next
    shr eax,14
    and eax,0xfff
    inc eax
    mov r12d,eax
.dfllc_next:
    inc r10d
    cmp r10d,32
    jb .dfllc_loop
.dfllc_done:
    mov eax,r12d
    pop r12
    pop rbx
    ret


streq:
    xor eax,eax
.sloop:
    mov dl,[rdi+rax]; mov cl,[rsi+rax]; cmp dl,cl; jne .sno
    test dl,dl; jz .syes
    inc rax; jmp .sloop
.syes: mov eax,1; ret
.sno: xor eax,eax; ret
.section .rodata
msg_surface_generic:.ascii "fieldc: invalid or unsupported native-field human surface\n"
msg_surface_generic_end:
opt_o:.asciz "-o"
.section .bss
.p2align 3
source_ptr:.skip 8
source_length:.skip 8
execution_admission_capacity: .skip 4
.p2align 6
.p2align 6
