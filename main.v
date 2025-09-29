module main(
    ////ports///
    CLOCK_50,
    INSTRUCTION,
    DATA_IN,
    MEM_ADDR,
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
    input [7:0] DATA_IN;
    input [18:0] MEM_ADDR;
    input ENABLE;

    output FLAG_DONE;
    output [7:0] DATA_OUT;
    output [7:0] VGA_R;
    output [7:0] VGA_B;
    output [7:0] VGA_G;
    output VGA_BLANK_N;
    output VGA_H_SYNC_N;
    output VGA_V_SYNC_N;
    output VGA_CLK;



    parameter ORIGINAL_WIDTH = 320;
    parameter ORIGINAL_HEIGHT = 240;
    

    //instruções
    localparam NOP = 3'b000;
    localparam LOAD = 3'b001;
    localparam STORE = 3'b010;
    localparam ZOOM_IN_VP = 3'b011;
    localparam ZOOM_IN_RP = 3'b100;
    localparam ZOOM_OUT_MP = 3'b101;
    localparam ZOOM_OUT_VD = 3'b110;
    localparam RESET_INST = 3'b111;

    //estados da maquina principal
    localparam IDLE = 2'b00;
    localparam READ_AND_WRITE = 2'b01;
    localparam ALGORITHM = 2'b10;
    localparam RESET = 2'b11;
    

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

    

    //memoria
    reg [18:0] mem_addr;
    reg [7:0] data_in_mem;
    wire [7:0] data_out_mem;
    reg mem_wr;
    memoryBlock imgMemory(
        .mem_addr(),
        .clk_100(),
        .data_in_mem(),
        .mem_wr(),
	    .data_out_mem()
    );
    

    reg [1:0] uc_state;
    reg addr_control_enable;
    wire addr_control_done;
    reg enable_vp, enable_mp, enable_vd, enable_rp;

    reg [2:0] last_instruction; // realizar instruções em cima

    reg [18:0] addr_to_memory_control;
    reg has_alg_on_exec;

    wire [9:0] next_x, next_y;

    wire [18:0] addr_from_memory_control;
    wire [18:0] addr_from_vga;
    wire [7:0] color_to_vga;
    reg [2:0] current_zoom;

    always @(posedge CLOCK_50) begin
        case (uc_state)
            IDLE: begin
                if(ENABLE) begin
                    
                    if(INSTRUCTION == 3'b001 || INSTRUCTION == 3'b010) begin
                        last_instruction <= INSTRUCTION;
                        uc_state <= READ_AND_WRITE;
                        has_alg_on_exec <= 1'b1;
                    end else if (INSTRUCTION <=3'b110) begin
                        last_instruction <= INSTRUCTION;
                        uc_state <= ALGORITHM;
                        has_alg_on_exec <= 1'b1;

                        if (INSTRUCTION == ZOOM_IN_RP) begin
                            if (current_zoom < 3'b100) begin
                                enable_md <= 1'b1;
                            end else if (current_zoom <= 3'b101) begin
                                enable_rp <= 1'b1;
                            end else begin
                                enable_rp <= 1'b0;
                                enable_md <= 1'b0;
                            end
                        end else if (INSTRUCTION == ZOOM_IN_VP) begin
                            if (current_zoom < 3'b100) begin
                                enable_vd <= 1'b1;
                            end else if (current_zoom <= 3'b101) begin
                                enable_vp <= 1'b1;
                            end else begin
                                enable_vp <= 1'b0;
                                enable_vd <= 1'b0;
                            end
                        end else if (INSTRUCTION == ZOOM_OUT_MP) begin
                            if (current_zoom <= 3'b100) begin
                                enable_md <= 1'b1;
                            end else if (current_zoom <= 3'b1) begin
                                enable_rp <= 1'b1;
                            end else begin
                                enable_mp <= 1'b0;
                                enable_rp <= 1'b0;
                            end
                        end else if (INSTRUCTION == ZOOM_OUT_VD) begin
                            if (current_zoom <= 3'b100) begin
                                enable_vd <= 1'b1;
                            end else if (current_zoom <= 3'b101) begin
                                enable_vp <= 1'b1;
                            end else begin
                                enable_vd <= 1'b0;
                                enable_vp <= 1'b0;
                            end
                        end
                    end else begin
                        last_instruction <= 3'b000;
                        uc_state <= RESET;
                        has_alg_on_exec <= 1'b0;
                    end
                    addr_control_enable <= 1'b1;
                end
            end
            READ_AND_WRITE: begin
                if (addr_control_done) begin
                    DATA_OUT <= data_out_mem;
                    uc_state <= IDLE;
                    addr_control_enable <= 1'b0;
                end 
            end
            ALGORITHM: begin
                if (addr_control_done) begin
                    uc_state <= IDLE;
                    addr_control_enable <= 1'b0;
                    if (last_instruction == ZOOM_IN_RP || last_instruction == ZOOM_IN_VP) begin
                        current_zoom <= current_zoom + 1'b1;
                    end else if (last_instruction == ZOOM_OUT_MP || last_instruction == ZOOM_OUT_VD) begin
                        current_zoom <= current_zoom - 1'b1;
                    end else begin
                        current_zoom <= current_zoom;
                    end
                end
            end
            RESET: begin
                current_zoom <= 3'b100;
            end
            

            default: 
        endcase
    end

    

    assign color_to_vga = (has_alg_on_exec) ? data_out_mem : 8'b0;

    memory_control addr_control(
        .addr_base(addr_to_memory_control),
        .clock(clk_100),
        .operation(last_instruction),
        .current_zoom(current_zoom),
        .enable(addr_control_enable),
        .addr_out(addr_from_memory_control),
        .done(addr_control_done),
        .wr_enable(mem),
    );

    //vga
    vga_module vga_out(
    .clock(clk_25_vga),     // 25 MHz
    .reset(),     // Active high
    .color_in(color_to_vga), // Pixel color data (RRRGGGBB)
    .next_x(next_x),  // x-coordinate of NEXT pixel that will be drawn
    .next_y(next_y),  // y-coordinate of NEXT pixel that will be drawn
    .hsync(VGA_H_SYNC_N),    // HSYNC (to VGA connector)
    .vsync(VGA_V_SYNC_N),    // VSYNC (to VGA connctor)
    .red(VGA_R),     // RED (to resistor DAC VGA connector)
    .green(VGA_G),   // GREEN (to resistor DAC to VGA connector)
    .blue(VGA_B),    // BLUE (to resistor DAC to VGA connector)
    .sync(VGA_SYNC),          // SYNC to VGA connector
    .clk(VGA_CLK),           // CLK to VGA connector
    .blank(VGA_BLANK_N)          // BLANK to VGA connector
);
endmodule