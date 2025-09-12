module main(
    ////ports///
    CLOCK_50,
    INSTRUCTION,
    DATA_IN,
    ENABLE,

    DATA_OUT,
    FLAG_DONE,
    VGA_R,
    VGA_B,
    VGA_G,
    VGA_BLANK_N,
    VGA_H_SYNC_N,
    VGA_V_SYNC_N,
    VGA_CLK,
    VGA_SYNC
);

    input CLOCK_50;
    input [2:0] INSTRUCTION;
    input [15:0] DATA_IN;
    input ENABLE;

    output FLAG_DONE;
    output [15:0] DATA_OUT;
    output [7:0] VGA_R;
    output [7:0] VGA_B;
    output [7:0] VGA_G;
    output VGA_BLANK_N;
    output VGA_H_SYNC_N;
    output VGA_V_SYNC_N;
    output VGA_CLK;


    parameter ORIGINAL_WIDTH = 160;
    parameter ORIGINAL_HEIGHT = 120;
    localparam IDLE_NOP = 3'b000;
    localparam LOAD = 3'b001;
    localparam STORE = 3'b010;
    localparam ZOOM_IN_ONE = 3'b011;
    localparam ZOOM_IN_TWO = 3'b100;
    localparam ZOOM_OUT_ONE = 3'b101;
    localparam ZOOM_OUT_TWO = 3'b110;
    //pll

    wire clk_100, clk_25_vga;

    pll pll0(
        .refclk   (CLOCK_50),   //  refclk.clk
		.rst      (1'b0),      //   reset.reset
		.outclk_0 (clk_100), // outclk0.clk
		.outclk_1 (clk_25_vga), // outclk1.clk
		.outclk_2 (), // outclk2.clk
		.outclk_3 (), // outclk3.clk
		.locked   () 
    );

    ///A IMAGEM TEVE SEU TAMANHO REDUZIDO PARA 180X120///

    //memoria
    reg [15:0] mem_addr;
    reg [15:0] data_in_mem;
    wire [15:0] data_out_mem;
    reg mem_wr;
    memoryBlock imgMemory(
        mem_addr,
        clk_100,
        data_in_mem,
        mem_wr,
	    data_out_mem
    );
    reg [1:0] count_mem;
    reg [15:0] data_out_mem_read;
    reg done_mem_op;
    reg memory_on;

    reg [32:0] pixel_for_operation;

    reg [19:0] count_for_operation;

    always @(posedge clk_100) begin
        if (memory_on) begin
            count <= count + 1;
        end else if (count == 2'b10) begin
            data_out_mem_read <= data_out_mem;
            count <= 0;
            done_mem_op <= 1;
        end else begin
            count <= 0;
        end
    end
    
    assign DATA_OUT = (state == LOAD || state == STORE) ? data_out_mem_read:16'b0;
    assign FLAG_DONE = done_mem_op;

    //maquina de estados
    reg [2:0] state;
    reg done_state;
    reg enable_zoom_in_one;
    reg enable_zoom_in_two;
    reg enable_zoom_out_one;
    reg enable_zoom_out_two;

    reg [2:0] current_zoom; 
    reg [16:0] last_addr;

    reg [3:0] count_for_pixel_operation;

    always @(posedge CLOCK_50) begin
        case (state)
            IDLE_NOP: begin //ver se isso aqui funciona
                //manter os dados sem atualizar
                mem_wr <= 0;
                memory_on <= 0;
                mem_addr <= mem_addr;
                done_state <= 1'b0;
                count_for_pixel_operation <= 0;
                count_for_operation <= 0;

                if (ENABLE == 1'b1) begin
                    state <= INSTRUCTION;
                end else begin
                    state <= IDLE_NOP;
                end
            end
            LOAD: begin //ver se aqui funciona
                mem_addr <= DATA_IN;
                mem_wr <= 1'b0;
                memory_on <= 1'b1;
                if (count == 2'b01) begin
                    state <= IDLE_NOP;
                    done_state <= 1'b1;
                end else begin 
                    state <= LOAD;
                    mem_addr <= mem_addr;
                end
            end //ver se isso aqui funciona
            STORE: begin
                mem_addr <= DATA_IN;
                mem_wr <= 1'b1;
                memory_on <= 1'b1;
                if (count == 2'b01) begin
                    state <= IDLE_NOP;
                    done_state <= 1'b1;
                    last_addr <= mem_addr;
                end else begin 
                    state <= STORE;
                    mem_addr <= mem_addr;
                    current_zoom <= 3'b010;
                end
            end
            ZOOM_IN_ONE: begin
                //execultar o algoritmo de zoom in com bit mais proximo

            end
            ZOOM_IN_TWO: begin
                //execultar o algoritmo de zoom in com replicação de pixel

            end
            ZOOM_OUT_ONE: begin
                //execultar o algoritmo de zoom out com decim
                if (count_for_operation == 0) begin
                    if (current_zoom <= 3'b010 && current_zoom > 3'b000 && count_for_pixel_operation == 4'b0) begin
                        current_zoom <= current_zoom - 1;

                        mem_addr <= last_addr - ((current_zoom == 3'b010) ? (ORIGINAL_HEIGHT*ORIGINAL_WIDTH>>1):((current_zoom < 3'b010) ? ((ORIGINAL_HEIGHT<<(current_zoom - 2))*(ORIGINAL_WIDTH<<(current_zoom - 2))>>1):((ORIGINAL_HEIGHT>>(2-current_zoom))*(ORIGINAL_WIDTH>>(2-current_zoom))>>1)));
                        count_for_pixel_operation = 1;
                        memory_on <= 1'b1;
                        
                    end
                    else begin
                        if(count == 2'b01) begin
                            memory_on <= 1'b0;
                        end



                    end
                end


            end
            ZOOM_OUT_TWO: begin
                //execultar o algoritmo de zoom out com media dos blocos

            end
            default: begin

                //não fazer nada

            end 
        endcase
    end

    always @(posedge clk ) begin
        
    end

    zoom_in_one zoom_in_one_module(
        //instanciar as portas
    );
    
    zoom_in_two zoom_in_two_module(
        //instanciar as portas
    );
    zoom_out_one zoom_out_one_module(
        .enable(enable_zoom_out_one),
        .data_in(),
        .data_out()

    );
    zoom_out_two zoom_out_two_module(
        //instanciar as portas
    );

    //vga
    vga_module video_out(
        //instanciar as portas
    );
endmodule