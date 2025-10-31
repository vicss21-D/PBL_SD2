@ ARMv7-A

.section .data

    @ SYSTEM MESSAGES

    err_open_mem: .asciz "ASM: Error: Unable to open /dev/mem\n"
    err_mmap:     .asciz "ASM: Error: mmap failed\n"
    str_sucess:   .asciz "ASM: Operation completed successfully.\n"
    str_fail:     .asciz "ASM: Operation failed.\n"

    @ PATHS

    dev_mem_path:  .asciz "/dev/mem"
    img_file_path: .asciz "image.bmp"  @ to define

    @ FPGA CONSTANTS

    FPGA_BRIDGE: .word 0xFF200000
    FPGA_SPAN:   .word 0x00001000

    @ Framebuffer and Image Constants

    BMP_HEADER_SIZE: .word 1078       
    FB_BASE_ADDR:    .word 0xC8000000  @ to define
    FB_SIZE:         .word 19200       @ (240x160)

.section .text
    .global _start

@ INICIALIZATION

_start:

    @ Salva registradores que serão usados (padrão C ABI)
    PUSH {R4-R11, LR}

    @ ---------------------------------------------------------------
    @ 1. MAPEAR A PONTE DO FPGA
    @ ---------------------------------------------------------------
    LDR R0, =dev_mem_path
    MOV R1, #2             @ O_RDWR (Leitura/Escrita)
    MOV R2, #0
    MOV R7, #5             @ Syscall: open
    SVC 0

    CMP R0, #0
    B.LT handle_err_open_mem @ Se R0 < 0, erro
    LDR R1, =fd_mem
    STR R0, [R1]           @ Salva o file descriptor de /dev/mem

    @ Mapeia a ponte leve (LW Bridge)
    MOV R0, #0             @ Deixa o kernel escolher o endereço virtual
    LDR R1, =FPGA_BRIDGE_SPAN
    LDR R1, [R1]           @ R1 = Comprimento (span)
    MOV R2, #3             @ PROT_READ | PROT_WRITE
    MOV R3, #1             @ MAP_SHARED
    LDR R4, =fd_mem
    LDR R4, [R4]           @ R4 = File descriptor
    LDR R5, =FPGA_BRIDGE_BASE
    LDR R5, [R5]           @ R5 = Endereço físico base
    LSR R5, R5, #12        @ Converte para 'page offset' (Obrigatório para mmap2)
    MOV R7, #192           @ Syscall: mmap2
    SVC 0

    CMP R0, #0
    B.LT handle_err_mmap    @ Se R0 < 0, erro
    LDR R1, =lw_bridge_ptr
    STR R0, [R1]           @ Salva o ponteiro do endereço virtual

@ LOAD FRAMEBUFFER WITH IMAGE DATA
@
@load_framebuffer:
@
@    push {lr}              @ Save return address
@

@LOAD IMAGE DATA FROM FILE
load_data:

@ EXIT PROGRAM
exit_program:
    
