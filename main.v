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
    

    //instruções
    localparam NOP = 3'b000;
    localparam LOAD = 3'b001;
    localparam STORE = 3'b010;
    localparam ZOOM_IN_VP = 3'b011;
    localparam ZOOM_IN_RP = 3'b100;
    localparam ZOOM_OUT_MP = 3'b101;
    localparam ZOOM_OUT_VD = 3'b110;

    //estados da maquina principal
    localparam IDLE = 2'b00;
    localparam READ = 2'b01;
    localparam EXEC = 2'b10;
    localparam WRITE = 2'b11;

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
    

    reg [1:0] uc_state;
    reg addr_control_enable;
    reg addr_control_done;
    reg enable_vp, enable_mp, enable_vd, enable_rp;

    reg [2:0] last_instruction; // realizar instruções em cima

    always @(posedge CLOCK_50) begin
        case (uc_state)
            IDLE: begin
                
                if(ENABLE) begin
                    last_instruction <= INSTRUCTION;
                    uc_state <= READ;
                    addr_control_enable <= 1'b1;
                    //adicionar depois a possibilidade de verificar previamente qual a instrução
                end
            end
            READ: begin
                if(addr_control_done) begin
                    uc_state <= EXEC;
                    addr_control_enable <= 1'b0;

                    case (param)
                        : 
                        default: 
                    endcase
                    
                end
            end
            

            default: 
        endcase
    end
    //vga
    vga_module video_out(
        //instanciar as portas
    );
endmodule