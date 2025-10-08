module main(
    // Portas de Entrada
    input CLOCK_50,
    input [2:0] INSTRUCTION,
    input [7:0] DATA_IN,
    input [17:0] MEM_ADDR,
    input ENABLE,

    // Portas de Saída
    output reg [7:0] DATA_OUT,
    output reg FLAG_DONE,
    output reg FLAG_ERROR,
    output reg FLAG_ZOOM_MAX,
    output reg FLAG_ZOOM_MIN,
    
    // Portas do VGA
    output [7:0] VGA_R,
    output [7:0] VGA_B,
    output [7:0] VGA_G,
    output VGA_BLANK_N,
    output VGA_H_SYNC_N,
    output VGA_V_SYNC_N,
    output VGA_CLK,
    output VGA_SYNC,

    // Portas de Debug
    output [18:0] addr_in_memory,
    output [7:0] data_in_memory,
    output [2:0] op_count,
    output addr_control_done
);

    //================================================================
    // 1. Definições, Parâmetros e Sinais
    //================================================================
    wire clk_100, clk_25_vga;
    pll pll0(.refclk(CLOCK_50), .rst(1'b0), .outclk_0(clk_100), .outclk_1(clk_25_vga));

    // --- Sinais da Memória ---
    reg [17:0] mem_addr;
    reg [7:0]  data_in_mem;
    wire [7:0] data_out_mem;
    wire       mem_wr;
    memory_block memory_to_img(.address(mem_addr), .clock(clk_100), .data(data_in_mem), .wren(mem_wr), .q(data_out_mem));

    // --- Parâmetros e Estados da FSM ---
    localparam NOP = 3'b000, LOAD = 3'b001, STORE = 3'b010, ZOOM_IN_VP = 3'b011;
    localparam ZOOM_IN_RP = 3'b100, ZOOM_OUT_MP = 3'b101, ZOOM_OUT_VD = 3'b110, RESET_INST = 3'b111;
    localparam IDLE = 2'b00, READ_AND_WRITE = 2'b01, ALGORITHM = 2'b10, RESET = 2'b11;
    
    // --- Passos dos Algoritmos (Interface com memory_control) ---
    localparam STEP_READ_SRC1   = 3'd0;
    localparam STEP_READ_SRC2   = 3'd1;
    localparam STEP_READ_SRC3   = 3'd2;
    localparam STEP_READ_SRC4   = 3'd3;
    localparam STEP_WRITE_DEST  = 3'd4;
    localparam STEP_SAVE_DATA   = 3'd1;
    localparam STEP_WRITE_DEST1 = 3'd2;
    localparam STEP_WRITE_DEST2 = 3'd3;
    localparam STEP_WRITE_DEST3 = 3'd4;
    localparam STEP_WRITE_DEST4 = 3'd5;

    // --- Sinais de Controle ---
    reg [1:0] uc_state;
    reg       has_alg_on_exec;
    reg [2:0] last_instruction;
    reg [2:0] current_zoom;
    reg       addr_control_enable;
    wire [17:0] addr_from_memory_control;
    wire [2:0]  counter_op;
    reg [2:0]   counter_op_delayed;

    // --- Lógica de Gatilho (Pulso para FSM, Nível para sub-módulo) ---
    reg  enable_ff;
    wire enable_pulse;
    always @(posedge clk_100) begin
        enable_ff <= !ENABLE;
    end
    assign enable_pulse = !ENABLE && !enable_ff;

    // --- Sinais do Pipeline e Algoritmos ---
    reg       enable_mp, enable_rp;
    reg [31:0] data_read_from_memory;
    wire [31:0] data_from_pixel_rep;
    wire [7:0]  data_from_block_avg;
    
    // --- Sinais do VGA ---
    wire [9:0] next_x, next_y;
    reg [17:0] addr_from_vga;
    reg [17:0] addr_base_to_vga;
    reg        inside_box;

    // --- Conexões para portas de debug ---
    assign op_count = counter_op;
    assign data_in_memory = data_out_mem;
    assign addr_in_memory = {1'b0, addr_from_memory_control};

    //================================================================
    // 2. Lógica de Geração de Endereço para o VGA (Display)
    //================================================================
    always @(posedge clk_25_vga) begin
        localparam X_START = 160, Y_START = 120, X_END = X_START + 320, Y_END = Y_START + 240;
        reg [16:0] vga_offset;

        if (next_x >= X_START && next_x < X_END && next_y >= Y_START && next_y < Y_END) begin
            inside_box <= 1'b1;
            vga_offset = (next_y - Y_START) * 320 + (next_x - X_START);
            addr_from_vga <= addr_base_to_vga + vga_offset;
        end else begin
            inside_box <= 1'b0;
            addr_from_vga <= 18'd0;
        end
    end
    
    //================================================================
    // 3. Pipeline de Dados do Algoritmo (Síncrono e Correto)
    //================================================================
    always @(posedge clk_100) begin
        counter_op_delayed <= counter_op;

        if (has_alg_on_exec) begin
            enable_rp <= 1'b0;
            enable_mp <= 1'b0;

            case (last_instruction)
                ZOOM_IN_VP,
                ZOOM_OUT_VD: begin
                    // CAPTURA o dado lido. O ciclo ocioso é respeitado aqui.
                    if (counter_op_delayed == STEP_READ_SRC1) begin
                        data_read_from_memory[7:0] <= data_out_mem;
                    end
                    // FORNECE o mesmo dado para a escrita.
                    if (counter_op == STEP_WRITE_DEST) begin
                        data_in_mem <= data_read_from_memory[7:0];
                    end
                end

                ZOOM_IN_RP: begin
                    if (counter_op_delayed == STEP_READ_SRC1) begin
                        data_read_from_memory[7:0] <= data_out_mem;
                        enable_rp <= 1'b1;
                    end
                    if (counter_op == STEP_SAVE_DATA) data_in_mem <= data_from_pixel_rep[7:0];
                    if (counter_op == STEP_WRITE_DEST1) data_in_mem <= data_from_pixel_rep[15:8];
                    if (counter_op == STEP_WRITE_DEST2) data_in_mem <= data_from_pixel_rep[23:16];
                    if (counter_op == STEP_WRITE_DEST3) data_in_mem <= data_from_pixel_rep[31:24];
                end
                
                ZOOM_OUT_MP: begin
                    if (counter_op_delayed == STEP_READ_SRC1) data_read_from_memory[7:0]   <= data_out_mem;
                    if (counter_op_delayed == STEP_READ_SRC2) data_read_from_memory[15:8]  <= data_out_mem;
                    if (counter_op_delayed == STEP_READ_SRC3) data_read_from_memory[23:16] <= data_out_mem;
                    if (counter_op_delayed == STEP_READ_SRC4) begin
                        data_read_from_memory[31:24] <= data_out_mem;
                        enable_mp <= 1'b1;
                    end
                    if (counter_op == STEP_WRITE_DEST) begin
                        data_in_mem <= data_from_block_avg;
                    end
                end
            endcase
        end else begin
            enable_rp <= 1'b0;
            enable_mp <= 1'b0;
        end
    end

    reg [17:0] addr_to_memory_control;
    
    //================================================================
    // 4. Máquina de Estados Finitos (FSM) Principal
    //================================================================
    always @(posedge clk_100) begin
        if (has_alg_on_exec) begin
            mem_addr <= addr_from_memory_control;
        end else begin
            mem_addr <= addr_from_vga;
        end

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
                        uc_state            <= READ_AND_WRITE;
                        last_instruction    <= INSTRUCTION;
                        addr_to_memory_control <= MEM_ADDR;
                        //has_alg_on_exec     <= 1'b1;
                        addr_control_enable <= 1'b1;
                    end else if (INSTRUCTION >= ZOOM_IN_VP && INSTRUCTION <= ZOOM_OUT_VD) begin
                        uc_state            <= ALGORITHM;
                        last_instruction    <= INSTRUCTION;
                        has_alg_on_exec     <= 1'b1;
                        addr_control_enable <= 1'b1;
                    end else if (INSTRUCTION == RESET_INST) begin
                        uc_state <= RESET;
                    end
                end
            end
            
            READ_AND_WRITE: begin
                FLAG_DONE <= 1'b0;
                addr_control_enable <= 1'b0;
                if (addr_control_done) begin
                    if (last_instruction == LOAD) DATA_OUT <= data_out_mem;
                    uc_state <= IDLE;
                end
            end

            ALGORITHM: begin
                FLAG_DONE <= 1'b0;
                addr_control_enable <= 1'b0;
                if (addr_control_done) begin
                    reg [2:0] next_zoom;
                    if (last_instruction == ZOOM_IN_RP || last_instruction == ZOOM_IN_VP) begin
                        next_zoom = current_zoom + 1;
                    end else if (last_instruction == ZOOM_OUT_MP || last_instruction == ZOOM_OUT_VD) begin
                        next_zoom = current_zoom - 1;
                    end else begin
                        next_zoom = current_zoom;
                    end
                    current_zoom <= next_zoom;

                    case (next_zoom)
                        3'b100: addr_base_to_vga <= 18'd0;       // Imagem 1x
                        3'b101, 3'b011: addr_base_to_vga <= 18'd76800;   // Imagem 2x | Imagem 0.5x
                        3'b110, 3'b010: addr_base_to_vga <= 18'd153600;  // Imagem 4x | Imagem 0.25x
                        default: addr_base_to_vga <= 18'd0;
                    endcase
                    uc_state <= IDLE;
                end
            end
            
            RESET: begin
                current_zoom     <= 3'b100; // Zoom padrão 1x
                addr_base_to_vga <= 18'd0;
                uc_state         <= IDLE;
            end
            
            default: uc_state <= IDLE;
        endcase
    end

    //================================================================
    // 5. Instâncias dos Módulos
    //================================================================
    memory_control addr_control(.addr_base(addr_to_memory_control), .clock(clk_100), .operation(last_instruction), .current_zoom(current_zoom), .enable(addr_control_enable), .addr_out(addr_from_memory_control), .done(addr_control_done), .wr_enable(mem_wr), .counter_op(counter_op));
    zoom_in_two zoom_in_pr(.enable(enable_rp), .data_in(data_read_from_memory[7:0]), .data_out(data_from_pixel_rep));
    zoom_out_one zoom_out_mp(.enable(enable_mp), .data_in(data_read_from_memory), .data_out(data_from_block_avg));

    reg [7:0] color_data_for_vga;
    always @(posedge clk_100) begin
        if (!has_alg_on_exec && inside_box) begin
            color_data_for_vga <= data_out_mem;
        end else begin
            color_data_for_vga <= 8'b0;
        end
    end

    vga_module vga_out(.clock(clk_25_vga), .reset(1'b0), .color_in(color_data_for_vga), .next_x(next_x), .next_y(next_y), .hsync(VGA_H_SYNC_N), .vsync(VGA_V_SYNC_N), .red(VGA_R), .green(VGA_G), .blue(VGA_B), .sync(VGA_SYNC), .clk(VGA_CLK), .blank(VGA_BLANK_N));

endmodule