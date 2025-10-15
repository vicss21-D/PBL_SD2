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
    localparam IDLE = 3'b00, READ_AND_WRITE = 3'b001, ALGORITHM = 3'b010, RESET = 3'b011, COPY_READ = 3'b100, COPY_WRITE = 3'b101;
    localparam MEM1 = 2'b00, MEM2 = 2'b01, MEM3 = 2'b10;

    reg [7:0] copy_data_buffer;

    // --- Sinais de Controle da FSM ---
    reg [2:0] uc_state;
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
    wire [7:0] data_in_mem3;
    reg [7:0]  data_in_mem1, data_in_mem2;
    reg        wren_mem1, wren_mem2, wren_mem3;
    wire [7:0] data_out_mem1, data_out_mem2, data_out_mem3;
    
    //memoria que guarda a imagem original
    mem1 memory1(
    .rdaddress(addr_from_memory_control_rd), 
    .wraddress(), 
    .clock(clk_100), 
    .data(data_in_mem1), 
    .wren(wren_mem1), 
    .q(data_out_mem1)
    );

    //memoria de exibiçao
    mem1 memory2(
    .rdaddress(addr_mem2), 
    .wraddress(addr_wr_mem2), 
    .clock(clk_100), 
    .data(data_in_mem2), 
    .wren(wren_mem2), 
    .q(data_out_mem2)
    );
    //memoria de trabalho
    mem1 memory3(
        .rdaddress(addr_mem3), // <-- Mudança aqui para permitir controle
        .wraddress(addr_from_memory_control_wr), 
        .clock(clk_100), 
        .data(data_in_mem3), // <-- MUDANÇA PRINCIPAL: Usar o dado do algoritmo
        .wren(wr_enable_from_alg), 
        .q(data_out_mem3)
    );

    wire [7:0] data_out_from_alg;
    wire       wr_enable_from_alg;

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
    

    reg [1:0] counter_rd_wr;

    reg [16:0] counter_address;
    //================================================================
    // 4. Pipeline de Dados do Algoritmo
    //================================================================
reg [2:0] next_zoom;
reg has_alg_on_exec;
reg [16:0] addr_from_vga_sync;

    reg [1:0] counter;
    reg has_done;

reg [16:0] addr_wr_mem2;
wire clk_vga;
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
                has_done <= 1'b0;
                vga_mem_select <= MEM2;

                if (enable_pulse) begin
                    if (INSTRUCTION == LOAD || INSTRUCTION == STORE) begin
                        uc_state         <= READ_AND_WRITE;
                        last_instruction <= INSTRUCTION;
                        addr_control_enable <= 1'b1;
                    end else if (INSTRUCTION >= ZOOM_IN_VP && INSTRUCTION <= ZOOM_OUT_VD) begin
                        uc_state         <= ALGORITHM;
                        last_instruction <= INSTRUCTION;
                        counter_address <= 17'd0;
                        counter_rd_wr <= 2'b0;
                        
                        // LÓGICA DE PING-PONG
                        alg_read_mem_select <= MEM1;
                        alg_write_mem_select <= MEM3;
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
                

                addr_control_enable <= 1'b1; 

                if (addr_control_done) begin //ao fim do algoritmo inicia a etapa de copia
                    addr_control_enable <= 1'b0;
                    counter_rd_wr <= 2'b00;
                    counter_address <= 17'd0; // Zera o contador para a cópia
                    wren_mem2 <= 1'b0; // Garante que não estamos escrevendo nada ainda
                    uc_state <= COPY_READ;
                end
            end

            RESET: begin
                current_zoom   <= 3'b100;
                vga_mem_select <= MEM3; // VGA sempre reseta para a memória original
                alg_read_mem_select <= MEM1;
                alg_write_mem_select <= MEM3;
                uc_state       <= IDLE;
            end

            COPY_READ: begin
            // Neste ciclo, o endereço de leitura da MEM3 (addr_mem3) é setado
            // para 'counter_address' pelo bloco always@(*).
            // A saída 'data_out_mem3' estará disponível no próximo ciclo de clock.
                if(counter_rd_wr == 2'b10) begin
                    wren_mem2 <= 1'b0; // Garante que não estamos escrevendo nada ainda
                    counter_rd_wr <= 2'b00;
                    uc_state <= COPY_WRITE;
                    
                end else begin
                    counter_rd_wr <= counter_rd_wr + 1;
                end
            end

            COPY_WRITE: begin
            // O dado lido da MEM3 no ciclo anterior já está disponível em 'data_out_mem3'.
                data_in_mem2 <= data_out_mem3; // Prepara o dado para ser escrito
                addr_wr_mem2 <= counter_address; // Define o endereço de escrita na MEM2
                wren_mem2    <= 1'b1;             // Habilita a escrita na MEM2
                
                if (counter_rd_wr == 2'b10) begin
                    counter_rd_wr <= 2'b00;
                    if (counter_address == 17'd76799) begin // 320*240 - 1
                        uc_state <= IDLE; // Cópia concluída
                        vga_mem_select <= MEM2; // Aponta o VGA para a nova imagem
                        FLAG_DONE <= 1'b1;
                    end else begin
                        counter_address <= counter_address + 1'b1; // Incrementa para o próximo pixel
                        uc_state <= COPY_READ; // Volta para o estado de leitura
                    end
                end else begin
                    counter_rd_wr <= counter_rd_wr + 1;
                end
            end
            
            default: uc_state <= IDLE;
        endcase
    
    end

    always @(*) begin
          // Endereçamento
        addr_mem3 <= counter_address;
        addr_mem2 <= addr_from_vga_sync;

        // Endereçamento das outras memórias (simplificado)
        addr_mem1 = addr_from_memory_control_rd; // MEM1 sempre lê do controle de algoritmo
    end

    wire [16:0] addr_from_memory_control_wr;
    wire [16:0] addr_from_memory_control_rd;

    //================================================================
    // 6. Instâncias de Módulos
    //================================================================
    memory_control addr_control(.addr_base(MEM_ADDR), 
    .clock(clk_100), 
    .operation(last_instruction), 
    .current_zoom(current_zoom), 
    .enable(addr_control_enable), 
    .addr_out_wr(addr_from_memory_control_wr), 
    .done(addr_control_done), 
    .wr_enable(wr_enable_from_alg), 
    .counter_op(counter_op), 
    .color_in(8'b11100000), 
    .color_out(data_in_mem3), 
    .addr_out_rd(addr_from_memory_control_rd));

    vga_module vga_out(.clock(clk_25_vga), 
    .reset(1'b0), 
    .color_in(data_to_vga_pipe), 
    .next_x(next_x), 
    .next_y(next_y), 
    .hsync(VGA_H_SYNC_N), 
    .vsync(VGA_V_SYNC_N), 
    .red(VGA_R), 
    .green(VGA_G), 
    .blue(VGA_B), 
    .sync(VGA_SYNC), 
    .clk(VGA_CLK), 
    .blank(VGA_BLANK_N));

    // --- Conexões para portas de debug ---
    assign addr_in_memory = addr_from_memory_control;
    assign data_in_memory = data_out_from_alg;

endmodule