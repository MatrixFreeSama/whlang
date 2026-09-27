.intel_syntax noprefix

.equ SYS_write,1

.extern surface_diag_active
.extern surface_diag_repaired
.extern surface_diag_repair_line
.extern surface_diag_cheesed
.extern surface_diag_cheese_line
.extern surface_diag_error_line

.global human_shell_report_success
.global human_shell_report_error

.section .text
# Human WH has one fused user-facing report path.  This unit does not inspect
# optimization kinds or frontend internals; it only renders the already-proved
# Surface facts in the fixed order Repair -> Convergence -> final result.
# eax=1 when a human report was emitted, 0 when caller should keep expert output.
human_shell_report_success:
    push rbx
    cmp dword ptr [rip+surface_diag_active],0
    je .hsrs_inactive

    cmp dword ptr [rip+surface_diag_repaired],0
    je .hsrs_after_repair
    mov edi,1
    mov esi,1
    call hs_print_art
    mov rax,[rip+surface_diag_repair_line]
    test rax,rax
    jz .hsrs_repaired_text
    mov edi,1
    mov rsi,rax
    call hs_print_line
.hsrs_repaired_text:
    lea rsi,[rip+hs_msg_repaired]
    mov edx,hs_msg_repaired_end-hs_msg_repaired
    mov edi,1
    call hs_write

.hsrs_after_repair:
    cmp dword ptr [rip+surface_diag_cheesed],0
    je .hsrs_compiled
    lea rsi,[rip+hs_msg_cheesed]
    mov edx,hs_msg_cheesed_end-hs_msg_cheesed
    mov edi,1
    call hs_write
    mov rax,[rip+surface_diag_cheese_line]
    test rax,rax
    jz .hsrs_cheese_gap
    mov edi,1
    mov rsi,rax
    call hs_print_line
.hsrs_cheese_gap:
    lea rsi,[rip+hs_newline]
    mov edx,1
    mov edi,1
    call hs_write

.hsrs_compiled:
    lea rsi,[rip+hs_msg_compiled]
    mov edx,hs_msg_compiled_end-hs_msg_compiled
    mov edi,1
    call hs_write
    mov eax,1
    pop rbx
    ret
.hsrs_inactive:
    xor eax,eax
    pop rbx
    ret

# Final errors dominate every successful intermediate event.  If repair and
# error coexist, only the error state is rendered, matching the human-shell law.
human_shell_report_error:
    push rbx
    cmp dword ptr [rip+surface_diag_active],0
    je .hsre_inactive
    mov edi,2
    mov esi,2
    call hs_print_art
    mov rax,[rip+surface_diag_error_line]
    test rax,rax
    jz .hsre_text
    mov edi,2
    mov rsi,rax
    call hs_print_line
.hsre_text:
    lea rsi,[rip+hs_msg_failed]
    mov edx,hs_msg_failed_end-hs_msg_failed
    mov edi,2
    call hs_write
    mov eax,1
    pop rbx
    ret
.hsre_inactive:
    xor eax,eax
    pop rbx
    ret

# edi=fd, esi=mode (1 repair='!', 2 error='x-multiplication sign').
# One canonical mask is rendered into either state, so the character geometry
# cannot fork into duplicated pictures.
hs_print_art:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d,edi
    mov r13d,esi
    lea r14,[rip+hs_art_pattern]
    lea r15,[rip+hs_art_pattern_end]
    lea rbx,[rip+hs_art_buffer]
    mov r8,rbx
    lea r9,[rip+hs_rep_repair]
    mov r10d,1
    cmp r13d,1
    je .hspa_loop
    lea r9,[rip+hs_rep_error]
    mov r10d,2
.hspa_loop:
    cmp r14,r15
    jae .hspa_emit
    mov al,[r14]
    inc r14
    cmp al,'#'
    jne .hspa_copy_plain
    xor ecx,ecx
.hspa_rep_loop:
    cmp ecx,r10d
    jae .hspa_loop
    mov al,[r9+rcx]
    mov [r8],al
    inc r8
    inc ecx
    jmp .hspa_rep_loop
.hspa_copy_plain:
    mov [r8],al
    inc r8
    jmp .hspa_loop
.hspa_emit:
    mov rdx,r8
    sub rdx,rbx
    mov rdi,r12
    mov rsi,rbx
    call hs_write
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# edi=fd, rsi=1-based line.
hs_print_line:
    push rbx
    push r12
    push r13
    mov r12d,edi
    mov rax,rsi
    lea rbx,[rip+hs_num_buffer+31]
    mov byte ptr [rbx],0
    xor r13d,r13d
    test rax,rax
    jnz .hspl_digits
    dec rbx
    mov byte ptr [rbx],'0'
    mov r13d,1
    jmp .hspl_emit
.hspl_digits:
    mov r8,10
.hspl_digit_loop:
    xor edx,edx
    div r8
    add dl,'0'
    dec rbx
    mov [rbx],dl
    inc r13d
    test rax,rax
    jnz .hspl_digit_loop
.hspl_emit:
    lea rsi,[rip+hs_line_prefix]
    mov edx,hs_line_prefix_end-hs_line_prefix
    mov edi,r12d
    call hs_write
    mov rsi,rbx
    mov edx,r13d
    mov edi,r12d
    call hs_write
    lea rsi,[rip+hs_line_suffix]
    mov edx,hs_line_suffix_end-hs_line_suffix
    mov edi,r12d
    call hs_write
    pop r13
    pop r12
    pop rbx
    ret

# edi=fd, rsi=buffer, edx=len
hs_write:
    mov eax,SYS_write
    syscall
    ret

.section .rodata
hs_rep_repair:.ascii "!"
hs_rep_error:.byte 0xC3,0x97
hs_line_prefix:.ascii "line "
hs_line_prefix_end:
hs_line_suffix:.ascii ":\n"
hs_line_suffix_end:
hs_msg_repaired:.ascii "Repaired successfully.\n\n"
hs_msg_repaired_end:
hs_msg_cheesed:.ascii "Cheesed successfully.\n"
hs_msg_cheesed_end:
hs_msg_compiled:.ascii "Compiled successfully.\n"
hs_msg_compiled_end:
hs_msg_failed:.ascii "Compilation failed.\n"
hs_msg_failed_end:
hs_newline:.ascii "\n"

# Condensed fixed character portrait.  '#' is an internal mask token only and
# is never emitted; each occupied cell becomes the selected one-cell glyph.
hs_art_pattern:
.ascii "                   ####       #########\n"
.ascii "                 ### ########## ## ########\n"
.ascii "                ###### ####   ###          ###\n"
.ascii "               ####  #####                 #####\n"
.ascii "               ###  ####                   ### ##\n"
.ascii "               ##  ###                      ######\n"
.ascii "                   ##               ##       ### ##\n"
.ascii "                  #        ##       ##    #   ## ##\n"
.ascii "                 ## #     #####    ## # ####   # ###\n"
.ascii "                #####    ##   ##   # ##### #   ######\n"
.ascii "                # ##    ## ######  ##########  #  ###\n"
.ascii "                 ###    ######## # ## ##########  ####\n"
.ascii "                 #####  ###### # ##### ### ##### # ###\n"
.ascii "                #######  #######          ######## ###\n"
.ascii "                # ############            ###  ########\n"
.ascii "               ##### ##  #######        ### # ### # ####\n"
.ascii "              ######  ## ## #####  # ######## # # #  ####\n"
.ascii "             ######    #######    ######## ## ##   # #####\n"
.ascii "             ######  ######  ###   ### ###### ##   ########\n"
.ascii "            ######  ##  ###   ##  ## # #### # #  ###  ##  ##\n"
.ascii "           ## ####  #     #  ###  ## #### ########     #   ###\n"
.ascii "          ## ####  ##     # ###   ###  # ##            ##    ###\n"
.ascii "         #######   #      ### #   # ######  ####        #      ##\n"
.ascii "        #######    #          #####  ###   ##  #        #       ##\n"
.ascii "        # ####    ##       ##         ## ###   #        ##     ####\n"
.ascii "        #  ##   ####     #####        ##   #   #         #       ###\n"
.ascii "        #  #   ##  #        ####      ##  ##  ###        #       # #\n"
.ascii "        ## # #######         ######## ##  ### #          ##       ##\n"
.ascii "         ########  #              ### ###  #####          ###  #####\n"
.ascii "      #######  #  #                ## # #  ######          ########\n"
.ascii "   ####   ##   #  #                  ##### ## ####         #  ### ####\n"
.ascii "  ###     ##   #  ##          #####    ####                #  ##     ##\n"
.ascii " ####    ## #  #   ###       ##   #     ###                ## ###     ##\n"
.ascii " #########  ###########    #########    ###               ##### ###### ####\n"
.ascii " ####                  #####  ##########################                 ###\n"
.ascii "############################################################################\n"
.ascii "                                                                               #\n"
.ascii "####  ##############################################################################\n"
.ascii "   #  #                                                                ######\n"
.ascii "   #  #                                                                 ### #\n"
hs_art_pattern_end:

.section .bss
.p2align 4
hs_art_buffer:.skip 16384
hs_num_buffer:.skip 32
