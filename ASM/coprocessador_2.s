@ =========================================================================
@ ASSEMBLY PROGRAM (ARMv7-A) FOR IMAGE PROCESSING USING AN FPGA COPROCESSOR
@ =========================================================================

@@@ SYSCALLS CODES (ARM Linux)

@__NR_read (ler): 3
@__NR_open (abrir): 5
@__NR_close (fechar): 6
@__NR_lseek (buscar): 19
@__NR_mmap2 (mapear memória): 192

.section .data

    @ --- SYSTEM MESSAGES  ---
    err_open_mem:  .asciz "ASM: Erro: Nao foi possivel abrir /dev/mem\n"
    err_mmap:      .asciz "ASM: Erro: mmap falhou\n"
    err_open_img:  .asciz "ASM: Erro: Nao foi possivel abrir image.bmp\n"
    err_seek_img:  .asciz "ASM: Erro: Falha no lseek do BMP\n"
    err_read_img:  .asciz "ASM: Erro: Falha ao ler dados do BMP\n"
    str_sucess:    .asciz "ASM: Operacao concluida com sucesso.\n"
    str_load_img:  .asciz "ASM: Imagem carregada. Enviando para FPGA...\n"
    
    @ --- PATHS ---
    dev_mem_path:  .asciz "/dev/mem"
    img_file_path: .asciz "image.bmp"

    @ --- FPGA CONSTANTS ---
    FPGA_BRIDGE_BASE: .word 0xFF200000
    FPGA_BRIDGE_SPAN: .word 0x00001000  @ 4KB

    @ --- BMP CONSTANTS ---
    BMP_HEADER_SIZE:  .word 1078  @ 54 (header) + 1024 (palette 8-bit)
    IMAGE_PIXELS:     .word 19200 @ 160x120

    @ --- PIOs OFFSETS (from Qsys) ---
    
    @@@@@@@@@@@@@@ TO CHECK ADRESSES @@@@@@@@@@@@@@

    PIO_INSTR_OFS:    .word 0x00  @ PIO INSTRUCTION [2:0]
    PIO_ENABLE_OFS:   .word 0x10  @ PIO ENABLE
    PIO_DATA_IN_OFS:  .word 0x20  @ PIO DATA_IN [7:0]
    PIO_MEM_ADDR_OFS: .word 0x30  @ PIO MEM_ADDR [16:0]
    PIO_DONE_OFS:     .word 0x40  @ PIO FLAG_DONE[0]
    PIO_ERROR_OFS:    .word 0x50  @ PIO FLAG_DONE[0]
    PIO_SEL_MEM:      .word 0x60  @ PIO SEL_MEM

    @ --- INSTRUCTIONS ---
    INSTR_NOP:        .word 0     @ 3'b000
    INSTR_LOAD:       .word 1     @ 3'b001
    INSTR_STORE:      .word 2     @ 3'b010
    INSTR_NHI_ALG:    .word 3     @ 3'b011
    INSTR_PR_ALG:     .word 4     @ 3'b100
    INSTR_BA_ALG:     .word 5     @ 3'b101 ------------------------------------------------------- TO CHECK
    
    @ --- BIT MASKS (@@@@@probly not needed anymore (TO CHECK) @@@@@@)---
    ENABLE_BIT_MASK:  .word 1     @ Assumes ENABLE is bit 0
    SEL_MEM_BIT_MASK: .word 2     @ Assumes SEL_MEM is bit 1
    FLAG_DONE_MASK:   .word 1     @ Assumes FLAG_DONE is bit 0

.section .bss
    @ buffers and file descriptors (executed at runtime)
    .lcomm fd_mem, 4           @ File descriptor para /dev/mem
    .lcomm fd_img, 4           @ File descriptor para image.bmp
    .lcomm lw_bridge_ptr, 4    @ Endereço virtual da ponte LW
    .lcomm img_buffer, 19200   @ Buffer para os pixels da imagem

.section .text
    .global _start

_start:
    @ SAVING REGISTERS
    PUSH {R4-R11, LR}

    @ ---------------------------------------------------------------
    @ 1. FPGA BRIDGE MAPPING

    LDR R0, =dev_mem_path
    MOV R1, #2             @ O_RDWR (rd/wr)
    MOV R2, #0
    MOV R7, #5             @ Syscall: open
    SVC 0

    CMP R0, #0
    blt handle_err_open_mem @ R0 < 0 --> error
    LDR R1, =fd_mem
    STR R0, [R1]           @ save "/dev/mem" file descriptor 

    @ LW Bridge mapping
    MOV R0, #0             @ Kenel chooses virtual address
    LDR R1, =FPGA_BRIDGE_SPAN
    LDR R1, [R1]           @ R1 = (span)
    MOV R2, #3             @ PROT_READ | PROT_WRITE
    MOV R3, #1             @ MAP_SHARED
    LDR R4, =fd_mem
    LDR R4, [R4]           @ R4 = File descriptor
    LDR R5, =FPGA_BRIDGE_BASE
    LDR R5, [R5]           @ R5 = phys base address
    LSR R5, R5, #12        @ 'page offset' (mmap2 requirement)
    MOV R7, #192           @ Syscall: mmap2
    SVC 0

    CMP R0, #0
    blt handle_err_mmap    @ Se R0 < 0 --> error
    LDR R1, =lw_bridge_ptr
    STR R0, [R1]           @ save virtual address pointer

    @ ---------------------------------------------------------------
    @ 2. LOAD IMAGE FOR BUFFER (load_data)
    @ ---------------------------------------------------------------

load_data:
    LDR R0, =img_file_path
    MOV R1, #0             @ O_RDONLY
    MOV R2, #0
    MOV R7, #5             @ Syscall: open
    SVC 0

    CMP R0, #0
    blt handle_err_open_img
    LDR R1, =fd_img
    STR R0, [R1]           @ save image.bmp file descriptor

    @ skip header (lseek)
    LDR R0, =fd_img
    LDR R0, [R0]           @ R0 = fd
    LDR R1, =BMP_HEADER_SIZE
    LDR R1, [R1]           @ R1 = offset (1078 bytes)
    MOV R2, #0             @ SEEK_SET ()
    MOV R7, #19            @ Syscall: lseek
    SVC 0
    CMP R0, #0
    blt handle_err_seek_img

    @ read image data into buffer
    LDR R0, =fd_img
    LDR R0, [R0]           @ R0 = fd
    LDR R1, =img_buffer    @ R1 = pointer to img_buffer
    LDR R2, =IMAGE_PIXELS
    LDR R2, [R2]           @ R2 = (19200)
    MOV R7, #3             @ Syscall: read
    SVC 0
    CMP R0, #0
    blt handle_err_read_img

    @ close image file
    LDR R0, =fd_img
    LDR R0, [R0]
    MOV R7, #6             @ Syscall: close
    SVC 0
    
    LDR R0, =str_load_img
    BL printf              @ External function

    @ ---------------------------------------------------------------
    @ 3. SEND IMAGE TO FPGA (load_framebuffer)
    @ ---------------------------------------------------------------
    @ R4 = FPGA Base Pointer (lw_bridge_ptr)
    @ R5 = image buffer pointer (img_buffer)
    @ R6 = counter (19200)
    @ R7 = FPGA memory address (MEM_ADDR)

    LDR R4, =lw_bridge_ptr
    LDR R4, [R4]
    LDR R5, =img_buffer
    LDR R6, =IMAGE_PIXELS
    LDR R6, [R6]
    MOV R7, #0             @ starts at 0

    @ Load offsets and STORE instruction

    LDR R8, =PIO_INSTR_OFS
    LDR R8, [R8]           @ R8 = Offset - PIO of INSTR
    LDR R9, =PIO_MEM_ADDR_OFS
    LDR R9, [R9]           @ R9 = Offset - PIO of MEM_ADDR
    LDR R10, =PIO_DATA_IN_OFS
    LDR R10, [R10]         @ R10 = Offset - PIO of DATA_IN
    LDR R11, =INSTR_STORE
    LDR R11, [R11]         @ R11 = STORE (2)

store_loop:
    LDRB R0, [R5], #1      @ R0 = pixel, post-indexed adressing
    STR R11, [R4, R8]      @ wr '2' in [FPGA_BASE + PIO_INSTR_OFS] - @ 1. STORE
    STR R7, [R4, R9]       @ wr R7 in [FPGA_BASE + PIO_MEM_ADDR_OFS] - @ 2. ADDRESS
    ADD R7, R7, #1         @ +1 in MEM_ADDR for next pixel

    STR R0, [R4, R10]      @ wr in [FPGA_BASE + PIO_DATA_IN_OFS] - @ 3. DATA_IN

    BL pulse_enable        @ pulse sub-routine - @ 4. ENABLE pulse

    BL wait_for_done       @ 5. wait for flag (FLAG_DONE)

    @ 6. Loop
    SUBS R6, R6, #1        @ Decrement counter
    bne store_loop         

    @ ---------------------------------------------------------------
    @ 4. ALGORITHM
    @ ---------------------------------------------------------------
    @ (R4 = FPGA base pointer)
    @ (R8 = PIO_INSTR_OFS)
    
    LDR R0, =INSTR_NHI_ALG @@@@@@@ TO CHANGE ALGORITHM @@@@@@@ -- TO CHECK
    LDR R0, [R0]           @ R0 = Comando (3)
    STR R0, [R4, R8]       @ Write command to PIO_INSTR_OFS
    
    BL pulse_enable        @ Pulse ENABLE
    BL wait_for_done       @ wait for FLAG_DONE

    LDR R0, =str_sucess
    BL printf              @ External function
    B exit_program         @ Exit

@ =========================================================================
@ ERROR ROUTINES
@ =========================================================================

handle_err_open_mem:
    LDR R0, =err_open_mem
    BL printf
    B exit_program

handle_err_mmap:
    LDR R0, =err_mmap
    BL printf
    B exit_program

handle_err_open_img:
    LDR R0, =err_open_img
    BL printf
    B exit_program

handle_err_seek_img:
    LDR R0, =err_seek_img
    BL printf
    B exit_program

handle_err_read_img:
    LDR R0, =err_read_img
    BL printf
    B exit_program

exit_program:
    @ clear "/dev/mem"
    LDR R0, =fd_mem
    LDR R0, [R0]
    MOV R7, #6             @ Syscall: close
    SVC 0

    @ restore registers and exit
    POP {R4-R11, PC}

@ =========================================================================
@ SUB-ROUTINES
@ =========================================================================

@ wait_for_done: Espera (polling) pela FLAG_DONE (bit 0)
@ rd PIO_FLAGS_OFS and tests bit FLAG_DONE_MASK

wait_for_done:
    PUSH {R0, R1, R2, R3}  @ save temp regs
    LDR R0, =lw_bridge_ptr
    LDR R0, [R0]           @ R0 = FPGA base pointer
    LDR R1, =PIO_FLAGS_OFS
    LDR R1, [R1]           @ R1 = Offset of PIO flags
    LDR R2, =FLAG_DONE_MASK
    LDR R2, [R2]           @ R2 = Mask (1)

poll_loop:
    LDR R3, [R0, R1]       @ rd PIO flags
    TST R3, R2             @ Tests bit 0 (FLAG_DONE)
    beq poll_loop         
    
    POP {R0, R1, R2, R3}
    BX LR                  

@ pulse_enable: pulses ENABLE flag

pulse_enable:
    PUSH {R0, R1, R2, R3}
    LDR R0, =lw_bridge_ptr
    LDR R0, [R0]           @ R0 = FPGA base pointer
    LDR R1, =PIO_CONTROL_OFS
    LDR R1, [R1]           @ R1 = Offset of PIO control
    LDR R2, =ENABLE_BIT_MASK
    LDR R2, [R2]           @ R2 = Mask (1)

    LDR R3, [R0, R1]       @ rd current value (para preservar SEL_MEM)
    ORR R3, R3, R2         @ Sets ENABLE bit 
    STR R3, [R0, R1]       

    BIC R3, R3, R2         @ Clears ENABLE bit
    STR R3, [R0, R1]       @ wb (preservando SEL_MEM)

    POP {R0, R1, R2, R3}
    BX LR                

@ =========================================================================
@ --- C Functions (Extern) ---
@ =========================================================================
.extern printf