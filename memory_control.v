module memory_control (
    addr_base,
    clock,
    operation,
    enable,
    addr_out,
    done,
);

    localparam RNB = 3'b000;
    localparam RPR = 3'b001;
    localparam RAM = 3'b010;
    localparam RDM = 3'b011;
    localparam WNB = 3'b100;
    localparam WPR = 3'b101;
    localparam WAM = 3'b110;
    localparam WDM = 3'b111;


    input [16:0] addr_base;
    input [2:0] operation;
    input enable, clock;
    output [16:0] addr_out;
    output done;

    reg [16:0] last_addr;

    always @(posedge clock) begin
        if (enable == 1'b1) begin
            case (operation)
                : 
                default: begin
                    addr_out <= addr_base;
                    done <= 1'b1;
                end
            endcase
        end
    end


endmodule