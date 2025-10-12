module main(
    // Portas de Entrada
    input CLOCK_50,
    input [2:0] INSTRUCTION,
    input [7:0] DATA_IN,
    input [16:0] MEM_ADDR,
    input ENABLE,

    // Portas de Saída e Debug
    output reg [7:0] DATA_OUT,
    output reg FLAG_DONE,
    output reg FLAG_ERROR,
    output reg FLAG_ZOOM_MAX,
    output reg FLAG_ZOOM_MIN,
    output [16:0] addr_in_memory,
    output [7:0] data_in_memory,
    output [2:0] op_count,
    output addr_control_done,

    output [7:0] VGA_R, output [7:0] VGA_B, output [7:0] VGA_G,
    output VGA_BLANK_N, output VGA_H_SYNC_N, output VGA_V_SYNC_N, output VGA_CLK, output VGA_SYNC
);

    //================================================================
    // 1. Definições, Clocks e Sinais
    //================================================================
    wire clk_100, clk_25_vga;
    pll pll0(.refclk(CLOCK_50), .rst(1'b0), .outclk_0(clk_100), .outclk_1(clk_25_vga));

    localparam NOP = 3'b000, LOAD = 3'b001, STORE = 3'b010, ZOOM_IN_VP = 3'b011;
    localparam ZOOM_IN_RP = 3'b100, ZOOM_OUT_MP = 3'b101, ZOOM_OUT_VD = 3'b110, RESET_INST = 3'b111;
    localparam IDLE = 2'b00, READ_AND_WRITE = 2'b01, ALGORITHM = 2'b10, RESET = 2'b11;
    localparam MEM1 = 2'b00, MEM2 = 2'b01, MEM3 = 2'b10;

    // --- Sinais de Controle da FSM ---
    reg [1:0] uc_state;
    reg       addr_control_enable;
    reg [2:0] last_instruction;
    reg [2:0] current_zoom;
    
    // --- Lógica de Gatilho ---
    reg  enable_ff;
    wire enable_pulse;
    always @(posedge clk_100) enable_ff <= !ENABLE;
    assign enable_pulse = !ENABLE && !enable_ff;
    
    // --- Sinais do Pipeline e Algoritmos ---
    wire [16:0] addr_from_memory_control;
    wire [2:0]  counter_op;
    reg [2:0]   counter_op_delayed;
    reg         enable_mp, enable_rp;
    wire [31:0]  data_read_from_memory;
    wire [31:0] data_from_pixel_rep;
    wire [7:0]  data_from_block_avg;
    
    // --- Sinais do VGA ---
    wire [9:0] next_x, next_y;
    reg [16:0] addr_from_vga;
    reg        inside_box;

    //================================================================
    // 2. Lógica de Gerenciamento das 3 Memórias
    //================================================================
    reg [1:0] vga_mem_select;
    reg [1:0] alg_read_mem_select;
    reg [1:0] alg_write_mem_select;

    reg [16:0] addr_mem1, addr_mem2, addr_mem3;
    reg [7:0]  data_in_mem1, data_in_mem2, data_in_mem3;
    reg        wren_mem1, wren_mem2, wren_mem3;
    wire [7:0] data_out_mem1, data_out_mem2, data_out_mem3;
    
    mem1 memory1(.address(addr_mem1), .clock(clk_100), .data(data_in_mem1), .wren(wren_mem1), .q(data_out_mem1));
    mem1 memory2(.address(addr_mem2), .clock(clk_100), .data(data_in_mem2), .wren(wren_mem2), .q(data_out_mem2));
    mem1 memory3(.address(addr_mem3), .clock(clk_100), .data(data_in_mem3), .wren(wren_mem3), .q(data_out_mem3));

    wire [7:0] data_out_from_alg;
    wire       wr_enable_from_alg;

    
    assign data_out_from_alg = (alg_read_mem_select == MEM1) ? data_out_mem1 :
                               (alg_read_mem_select == MEM2) ? data_out_mem2 : data_out_mem3;

    //================================================================
    // 3. Lógica do VGA
    //================================================================
    always @(posedge clk_25_vga) begin
        localparam X_START=160, Y_START=120, X_END=X_START+320, Y_END=Y_START+240;
        reg [16:0] vga_offset;
        if (next_x >= X_START && next_x < X_END && next_y >= Y_START && next_y < Y_END) begin
            inside_box <= 1'b1;
            vga_offset = (next_y - Y_START) * 320 + (next_x - X_START);
            addr_from_vga <= vga_offset;
        end else begin
            inside_box <= 1'b0;
            addr_from_vga <= 17'd0;
        end
    end
    
    reg [7:0] data_to_vga_pipe;
    always @(posedge clk_100) begin
        case(vga_mem_select)
            MEM1: data_to_vga_pipe <= (inside_box) ? data_out_mem1:8'b0;
            MEM2: data_to_vga_pipe <= (inside_box) ? data_out_mem2:8'b0;
            MEM3: data_to_vga_pipe <= (inside_box) ? data_out_mem3:8'b0;
            default: data_to_vga_pipe <= data_out_mem1;
        endcase
    end 
    
    //================================================================
    // 4. Pipeline de Dados do Algoritmo
    //================================================================
reg [2:0] next_zoom;
reg has_alg_on_exec;
reg [16:0] addr_from_vga_sync;
    //================================================================
    // 5. Máquina de Estados Finitos (FSM) Principal
    //================================================================
    always @(posedge clk_100) begin
        
        addr_from_vga_sync <= addr_from_vga;
        case (uc_state) 
            IDLE: begin 
                has_alg_on_exec     <= 1'b0;
                addr_control_enable <= 1'b0;
                FLAG_DONE           <= 1'b1;
                FLAG_ERROR          <= 1'b0;
                FLAG_ZOOM_MAX       <= 1'b0;
                FLAG_ZOOM_MIN       <= 1'b0;

                 if (enable_pulse) begin
                    if (INSTRUCTION == LOAD || INSTRUCTION == STORE) begin
                        uc_state         <= READ_AND_WRITE;
                        last_instruction <= INSTRUCTION;
                        addr_control_enable <= 1'b1;
                    end else if (INSTRUCTION >= ZOOM_IN_VP && INSTRUCTION <= ZOOM_OUT_VD) begin
                        uc_state         <= ALGORITHM;
                        last_instruction <= INSTRUCTION;
                        
                        // LÓGICA DE PING-PONG
                        alg_read_mem_select <= (alg_read_mem_select == MEM2) ? MEM3 : MEM2;
                        alg_write_mem_select <= (vga_mem_select == MEM2) ? MEM3 : MEM2;
                    end else if (INSTRUCTION == RESET_INST) begin
                        uc_state <= RESET;
                    end
                end
            end
            
            READ_AND_WRITE: begin
                FLAG_DONE <= 1'b0;
                has_alg_on_exec <= 1'b1;
                addr_control_enable <= 1'b1;
                
                if (addr_control_done) begin
                    if (last_instruction == LOAD) DATA_OUT <= data_out_from_alg;
                    uc_state <= IDLE;
                end
            end

            ALGORITHM: begin
                FLAG_DONE <= 1'b0;
                has_alg_on_exec <= 1'b1;
                addr_control_enable <= 1'b1; // <-- CORREÇÃO: Mantém o módulo de controle LIGADO

                if (addr_control_done) begin
                    // Aponta o VGA para a memória que acabou de ser escrita
                    vga_mem_select <= alg_write_mem_select;
                    
                    // Lógica para atualizar o nível de zoom
                    
                    // ... (código para calcular next_zoom) ...
                    current_zoom <= next_zoom;
                    
                    uc_state <= IDLE;
                end
            end

            RESET: begin
                current_zoom   <= 3'b100;
                vga_mem_select <= MEM1; // VGA sempre reseta para a memória original
                alg_read_mem_select <= MEM3;
                alg_write_mem_select <= MEM2;
                uc_state       <= IDLE;
            end
            
            default: uc_state <= IDLE;
        endcase

         if (uc_state == ALGORITHM) begin
            if (counter_op_delayed == 3'b001) begin
                //data_read_from_memory[7:0] <= data_out_from_alg;
            end
            // ... lógica para outros algoritmos ...
        end


        
    
    end

    always @(*) begin
          // Endereçamento
        addr_mem1 = (vga_mem_select == MEM1) ? addr_from_vga_sync : (alg_read_mem_select == MEM1) ? addr_from_memory_control : 17'd0;


        addr_mem2 = (vga_mem_select == MEM2) ? addr_from_vga_sync : (alg_read_mem_select == MEM2 || alg_write_mem_select == MEM2) ? addr_from_memory_control : 17'd0;
        addr_mem3 = (vga_mem_select == MEM3) ? addr_from_vga_sync : (alg_read_mem_select == MEM3 || alg_write_mem_select == MEM3) ? addr_from_memory_control : 17'd0;

        // Escrita
        wren_mem1 = (uc_state == READ_AND_WRITE && last_instruction == STORE) ? wr_enable_from_alg : 1'b0;
        data_in_mem1 = (uc_state == READ_AND_WRITE && last_instruction == STORE) ? DATA_IN : 8'd0;
        
        wren_mem2 = (alg_write_mem_select == MEM2) ? wr_enable_from_alg : 1'b0;
        data_in_mem2 = (alg_write_mem_select == MEM2) ? data_read_from_memory[7:0] : 8'd0;
        
        wren_mem3 = (alg_write_mem_select == MEM3) ? wr_enable_from_alg : 1'b0;
        data_in_mem3 = (alg_write_mem_select == MEM3) ? data_read_from_memory[7:0] : 8'd0;
    end

    //================================================================
    // 6. Instâncias de Módulos
    //================================================================
    memory_control addr_control(.addr_base(MEM_ADDR), .clock(clk_100), .operation(last_instruction), .current_zoom(current_zoom), .enable(addr_control_enable), .addr_out(addr_from_memory_control), .done(addr_control_done), .wr_enable(wr_enable_from_alg), .counter_op(counter_op), .color_in(data_out_from_alg), .color_out(data_read_from_memory[7:0]));
    zoom_in_two zoom_in_pr(.enable(enable_rp), .data_in(data_read_from_memory[7:0]), .data_out(data_from_pixel_rep));
    zoom_out_one zoom_out_mp(.enable(enable_mp), .data_in(data_read_from_memory), .data_out(data_from_block_avg));
    vga_module vga_out(.clock(clk_25_vga), .reset(1'b0), .color_in(data_to_vga_pipe), .next_x(next_x), .next_y(next_y), .hsync(VGA_H_SYNC_N), .vsync(VGA_V_SYNC_N), .red(VGA_R), .green(VGA_G), .blue(VGA_B), .sync(VGA_SYNC), .clk(VGA_CLK), .blank(VGA_BLANK_N));

    // --- Conexões para portas de debug ---
    assign addr_in_memory = addr_from_memory_control;
    assign data_in_memory = data_out_from_alg;

endmodule