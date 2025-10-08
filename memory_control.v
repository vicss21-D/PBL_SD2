module memory_control (
    addr_base,
    clock,
    operation,
    current_zoom,
    enable,
    addr_out,
    done,
    wr_enable,
    counter_op
);

    // estado de aguardar uma nova instrução
    localparam IDLE = 3'b000;

    //operações de leitura ou escrita na memoria
    localparam RD_DATA = 3'b001;
    localparam WR_DATA = 3'b010;

    //algoritmos
    localparam NHI_ALG = 3'b011;
    localparam PR_ALG = 3'b100;
    localparam NH_ALG = 3'b101;
    localparam BA_ALG = 3'b110;
    
    //estado apenas para aguardar finalizar a operação de leitura ou escrita
    localparam WAIT_WR_RD = 3'b111;

    input [16:0] addr_base;
    input [2:0] operation;
    input [2:0] current_zoom;
    input enable, clock;
    output reg [16:0] addr_out;
    output reg done;
    output reg wr_enable;

    reg [2:0] state;

    reg [1:0] wr_wait_counter;
    reg [16:0] algorithm_needed_steps;
    reg [16:0] algorithm_current_step;
    
    always @(posedge clock) begin
        case (state)
            IDLE:   begin
                done <= 1'b1;
                wr_enable <= 1'b0;
                addr_out <= 17'b0;
                if (enable) begin
                    state <= operation;
                    done <= 1'b0;
                end else begin
                    state <= IDLE;
                end
            end

            WAIT_WR_RD: begin // adicionar a veri
                if (algorithm_current_step >= algorithm_needed_steps) begin
                    state <= IDLE;
                    wr_wait_counter <= 2'b00;
                    wr_enable <= 1'b0;
                    done <= 1'b1;
                end else begin
                    if (wr_wait_counter == 2'b11) begin
                        wr_enable <= 1'b0;
                        state <= operation;
                    end else begin
                        wr_wait_counter <= wr_wait_counter + 1;
                        wr_enable <= wr_enable;
                        state <= WAIT_WR_RD;
                    end
                end
            end

            RD_DATA: begin
                addr_out <= addr_base;
                state <= WAIT_WR_RD;
                wr_wait_counter <= 2'b00;
                wr_enable <= 1'b0;
                done <= 1'b0;
            end
        endcase
    end


endmodule