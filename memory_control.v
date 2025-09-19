module memory_control (
    addr_base,
    clock,
    operation,
    current_zoom,
    enable,
    addr_out,
    done,
    wr_enable,
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
    output done;
    output reg wr_enable;

    reg [18:0] needed_time; // tempo que uma operação necessita para ser execultada

    reg [2:0] state; //estado atual

    reg [16:0] last_addr; //ultimo endereço utilizado
    reg [1:0] count_wr_rd; // conta os 3 ciclos necessarios para realizar uma operação de leitura ou escrita

    reg [2:0] last_op; //armazena qual foi a ultima operação enviada

    reg [18:0] op_step_count; //conta o numero de passos realizados em alguma operação

    reg has_alg_on_exec;

    always @(posedge clock) begin

        case (state)
                IDLE: begin
                    done <= 1'b1;
                    wr_enable <= 1'b0;
                    has_alg_on_exec <= 1'b0;
                    op_step_count <= 19'b0;
                    needed_time <= 19'b0;
                    if (enable == 1'b1) begin
                        state <= operation;
                    end else  begin
                        state <= IDLE;
                    end
                end

                WAIT_WR_RD: begin
                    count_wr_rd <= count_wr_rd + 1'b1;
                    if (count_wr_rd == 2'b10) begin //quando o contador chegar em 3
                        if (last_op == RD_DATA || last_op == WR_DATA) begin //se for operação de escrita
                            state <= IDLE; //vai pro idle
                        end else begin // se não
                            op_step_count <= op_step_count + 1'b1; //adiciona um no contador de passo
                            if (op_step_count == needed_time) begin //se tiver chegado no numero de passos necessarios
                                state <= IDLE; //vai pro idle
                                has_alg_on_exec <= 1'b0; //desativa o sinal que tem um algoritmo em execução
                            end else begin // se não
                                has_alg_on_exec <= 1'b1; //ativa o sinal que tem um algoritmo em execução
                                state <= last_op; //retorna a ultima operação
                            end
                        end

                        last_addr <= addr_out ; // guarda o ultimo endereço de escrita / leitura
                    end
                end
                WR_DATA: begin
                    addr_out <= addr_base;  //endereço que sera utilizado
                    wr_enable <= 1'b1;  //habilita a escrita
                    count_wr_rd <= 2'b00; //reseta o contador de tempo para escrita e leitura
                    done <= 1'b0; //desabilita o sinal de pronto
                    last_op <= WR_DATA; //armazena a ultima operação
                end 
                
                RD_DATA: begin
                    addr_out <= addr_base;
                    wr_enable <= 1'b0;
                    count_wr_rd <= 2'b00;
                    done <= 1'b0;
                    last_op <= RD_DATA;
                end

                PR_ALG: begin
                    done <= 1'b0;
                    if (!has_alg_on_exec) begin
                        needed_time <= 19'd47700;
                        addr_out <= last_addr-16'b38400; // volta pro endereço inicial da imagem conferir como fazer isso do jeito correto
                    end
                end
                default: begin
                    addr_out <= addr_base;
                    done <= 1'b1;
                end
            endcase
    end


endmodule