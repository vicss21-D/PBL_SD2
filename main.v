module main(
    ////ports///
    CLOCK_50,
    INSTRUCTION,
    DATA_IN,
    MEM_ADDR,
    ENABLE,

    addr_in_memory,
    data_in_memory,
    op_count,
    addr_control_done,
    

    DATA_OUT,
    FLAG_DONE,
    FLAG_ERROR,
    FLAG_ZOOM_MAX,
    FLAG_ZOOM_MIN,
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
    input [17:0] MEM_ADDR;
    input ENABLE;

    output reg FLAG_DONE;
    output reg FLAG_ERROR;
    output reg FLAG_ZOOM_MAX;
    output reg FLAG_ZOOM_MIN;
    output reg [7:0] DATA_OUT;
    output [7:0] VGA_R;
    output [7:0] VGA_B;
    output [7:0] VGA_G;
    output VGA_BLANK_N;
    output VGA_H_SYNC_N;
    output VGA_V_SYNC_N;
    output VGA_CLK;
    output VGA_SYNC;
    output [18:0] addr_in_memory;
    output [7:0] data_in_memory;
    output [2:0] op_count;


    //assign op_count = counter_op;
    assign data_in_memory = data_out_mem;
    assign addr_in_memory = addr_from_memory_control;


	//assign FLAG_DONE = addr_control_done;

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

    reg enable_ff;
    wire enable_pulse;

    always @(posedge clk_100) begin
        enable_ff <= ENABLE;
    end

    assign enable_pulse = ENABLE && !enable_ff;

    //memoria
    reg [17:0] mem_addr;
    reg [7:0] data_in_mem;
    wire [7:0] data_out_mem;
    wire mem_wr;

    memory_block memory_to_img(
	.address(mem_addr),
	.clock(clk_100),
	.data(data_in_mem),
	.wren(mem_wr),
	.q(data_out_mem));
    

    reg [1:0] uc_state;
    reg addr_control_enable;
    /*wire*/output addr_control_done;
    reg enable_mp, enable_rp;

    reg [2:0] last_instruction; // realizar instruções em cima

    reg [17:0] addr_to_memory_control;
    reg has_alg_on_exec;

    wire [9:0] next_x, next_y;

    wire [17:0] addr_from_memory_control;
    reg [17:0] addr_from_vga;
    wire [7:0] color_to_vga;
    reg [2:0] current_zoom;
    reg [31:0] data_read_from_memory;
    wire [31:0] data_from_pixel_rep;
    wire [7:0] data_from_block_avg;

    //maquina de estados auxiliar para a execução dos algoritmos

    wire [2:0] counter_op;
    reg inside_box;	 
    reg [17:0] addr_base;

    reg [16:0] counter_addr;

    always @(posedge clk_100)   begin

        case (uc_state)
            IDLE: begin
                if (ENABLE) begin
                    addr_base <= MEM_ADDR;
                    case (INSTRUCTION)
                        LOAD: begin
                            uc_state <= READ_AND_WRITE;
                            last_instruction <= LOAD;
                        end
                        STORE: begin
                            uc_state <= READ_AND_WRITE;
                            last_instruction <= STORE;
                        end
                        ZOOM_IN_VP: begin
                            addr_control_enable <= 1'b1;
                            uc_state <= ALGORITHM;
                            last_instruction <= ZOOM_IN_VP;
                        end
                        ZOOM_IN_RP: begin
                            addr_control_enable <= 1'b1;
                            uc_state <= ALGORITHM;
                            last_instruction <= ZOOM_IN_RP;
                        end
                        ZOOM_OUT_MP: begin
                            addr_control_enable <= 1'b1;
                            uc_state <= ALGORITHM;
                            last_instruction <= ZOOM_OUT_MP;
                        end
                        ZOOM_OUT_VD: begin
                            addr_control_enable <= 1'b1;
                            uc_state <= ALGORITHM;
                            last_instruction <= ZOOM_OUT_VD;
                        end
                        NOP: begin
                            uc_state <= IDLE;
                            last_instruction <= NOP;
                        end
                        RESET_INST: begin
                            uc_state <= RESET;
                            last_instruction <= RESET_INST;
                        end
                        default: begin
                            uc_state <= IDLE;
                            last_instruction <= NOP;
                        end
                    endcase
                end
            end
            READ_AND_WRITE: begin
                FLAG_DONE <= 1'b0;
                case(last_instruction)
                    LOAD: begin
                        addr_to_memory_control <= addr_base;

                        addr_control_enable <= 1'b1;

                        if(addr_control_done) begin
                            uc_state <= IDLE;
                            DATA_OUT <= data_out_mem;
                            FLAG_DONE <= 1'b1;
                            addr_control_enable <= 1'b0;
                        end else begin
                            uc_state <= READ_AND_WRITE;
                            last_instruction <= LOAD;
                        end
                    end
                    STORE: begin
                        addr_to_memory_control <= addr_base;
                        addr_control_enable <= 1'b1;

                        if(addr_control_done) begin
                            uc_state <= IDLE;
                            FLAG_DONE <= 1'b1;
                            addr_control_enable <= 1'b0;
                        end else begin
                            uc_state <= READ_AND_WRITE;
                            last_instruction <= STORE;
                        end
                    end
                    default: begin
                        uc_state <= IDLE;
                        FLAG_DONE <= 1'b1;
                    end
                endcase
            end
            ALGORITHM: begin
                FLAG_DONE <= 1'b0;
                case(last_instruction)
                    ZOOM_IN_VP: begin //TODO: Rever essa logica de leitura e escrita
                        
                        case(counter_op)

                            3'b000: begin
                                data_read_from_memory[7:0] <= data_out_mem;
                            end
                            3'b001: begin
                                data_in_mem <= data_read_from_memory[7:0];
                            end
                            3'b010: begin
                                DATA_OUT <= data_read_from_memory[7:0];
                            end
                        endcase

                        if (addr_control_done && !ENABLE) begin
                            uc_state <= IDLE;
                            FLAG_DONE <= 1'b1;
                            addr_control_enable <= 1'b0;
                        end else begin
                            uc_state <= ALGORITHM;
                            last_instruction <= ZOOM_IN_VP;
                        end
                    end
                    ZOOM_IN_RP: begin
                        case(counter_op)
                            3'b000: begin
                                data_read_from_memory[7:0] <= data_out_mem;
                            end
                            3'b001: begin
                                data_in_mem <= data_read_from_memory[7:0];
                            end
                            3'b010: begin
                                data_in_mem <= data_read_from_memory[7:0];
                            end
                            3'b011: begin
                                data_in_mem <= data_read_from_memory[7:0];
                            end
                            3'b100: begin
                                data_in_mem <= data_read_from_memory[7:0];
                            end
                            3'b101: begin
                                DATA_OUT <= data_read_from_memory[7:0];
                            end
                        endcase
                    end
                    ZOOM_OUT_MP: begin
                        case(counter_op)
                            3'b000: begin
                                data_read_from_memory[7:0] <= data_out_mem;
                            end
                            3'b001: begin
                                data_read_from_memory[15:8] <= data_out_mem;
                            end
                            3'b010: begin
                                data_read_from_memory[23:16] <= data_out_mem;
                            end
                            3'b011: begin
                                data_read_from_memory[31:24] <= data_out_mem;
                            end
                            3'b100: begin
                                enable_mp <= 1'b1;
                            end
                            3'b101: begin
                                enable_mp <= 1'b0;
                                data_in_mem <= data_from_block_avg; 
                            end
                            3'b110: begin
                                DATA_OUT <= data_from_block_avg;
                            end
                        endcase
                    end
                endcase
            end
            default: begin
				
				end
        endcase

    end
    //algoritmos
    zoom_in_two zoom_in_pr(
        .enable(enable_rp),
        .data_in(data_read_from_memory[7:0]),
        .data_out(data_from_pixel_rep)
    );

    zoom_out_one zoom_out_mp(
        .enable(enable_mp),
        .data_in(data_read_from_memory),
        .data_out(data_from_block_avg)
    );


    memory_control addr_control(
        .addr_base(addr_to_memory_control),
        .clock(clk_100),
        .operation(last_instruction),
        .current_zoom(current_zoom),
        .enable(addr_control_enable),
        .addr_out(addr_from_memory_control),
        .done(addr_control_done),
        .wr_enable(mem_wr),
        .counter_op(op_count)
    );

    //vga
    vga_module vga_out(
    .clock(clk_25_vga),     // 25 MHz
    .reset(addr_control_enable),     // Active high
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