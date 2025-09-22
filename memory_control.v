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
    output reg done;
    output reg wr_enable;

    reg [18:0] num_steps_needed; // tempo que uma operação necessita para ser execultada

    reg [2:0] state; //estado atual

    reg [16:0] last_addr_rd; //ultimo endereço utilizado
    reg [16:0] last_addr_wr; //ultimo endereço utilizado
    reg [1:0] wr_rd_timer_counter; // conta os 3 ciclos necessarios para realizar uma operação de leitura ou escrita

    reg [2:0] last_op; //armazena qual foi a ultima operação enviada

    reg [18:0] algorithm_step_counter; //conta o numero de passos realizados em alguma operação

    reg [2:0] operation_step_counter; // armazena em qual passo do algoritimo está

    reg has_alg_on_exec;

    reg [9:0] count_x_new, count_y_new; 

    always @(posedge clock) begin

        case (state)
                IDLE: begin
                    done <= 1'b1;
                    wr_enable <= 1'b0;
                    has_alg_on_exec <= 1'b0;
                    algorithm_step_counter <= 19'b0;
                    num_steps_needed <= 19'b0;
                    count_x_new <= 19'b0;
                    count_y_new <= 19'b0;
                    if (enable == 1'b1) begin
                        state <= operation;
                    end else  begin
                        state <= IDLE;
                    end
                end

                WAIT_WR_RD: begin
                    wr_rd_timer_counter <= wr_rd_timer_counter + 1'b1;
                    if (wr_rd_timer_counter == 2'b11) begin //quando o contador chegar em 3
                        if (last_op == RD_DATA || last_op == WR_DATA) begin //se for operação de escrita
                            state <= IDLE; //vai pro idle
                        end else begin // se não
                            if (algorithm_step_counter == num_steps_needed) begin //se tiver chegado no numero de passos necessarios
                                state <= IDLE; //vai pro idle
                                has_alg_on_exec <= 1'b0; //desativa o sinal que tem um algoritmo em execução
                                done <= 1'b1; //ativa o sinal de pronto
                            end else begin // se não
                                has_alg_on_exec <= 1'b1; //ativa o sinal que tem um algoritmo em execução
                                state <= last_op; //retorna a ultima operação
                            end
                        end

                        wr_enable <= 1'b0;   //desabilita o sinal de escrita

                        case (last_op) // verifico qual a ultima operação realizada 
                            RD_DATA: begin //se for leitura, atualiza last_addr_rd
                                last_addr_rd <= addr_out;
                                last_addr_wr <= last_addr_wr;
                            end
                            WR_DATA: begin //se for escrita, atualiza last_addr_wr
                                last_addr_wr <= addr_out;
                                last_addr_rd <= last_addr_rd;
                            end
                            PR_ALG: begin //se for um dos algoritmos, atualiza last_addr_rd e last_addr_wr dependendo do passo
                                if (operation_step_counter == 3'b000) begin //leitura do dado
                                    last_addr_wr <= last_addr_wr;
                                    last_addr_rd <= addr_out;
                                end else begin  // escrita do dado
                                    last_addr_wr <= addr_out;
                                    last_addr_rd <= last_addr_rd;
                                end
                            end
                            default: begin
                                last_addr_rd <= last_addr_rd;
                                last_addr_wr <= last_addr_wr;
                            end
                        endcase
                        last_addr <= addr_out ; // guarda o ultimo endereço de escrita / leitura
                    end else begin
                        state <= WAIT_WR_RD;
                    end
                end
                WR_DATA: begin
                    addr_out <= addr_base;  //endereço que sera utilizado
                    wr_enable <= 1'b1;  //habilita a escrita
                    wr_rd_timer_counter <= 2'b00; //reseta o contador de tempo para escrita e leitura
                    done <= 1'b0; //desabilita o sinal de pronto
                    last_op <= WR_DATA; //armazena a ultima operação
                end 
                
                RD_DATA: begin
                    addr_out <= addr_base;
                    wr_enable <= 1'b0;
                    wr_rd_timer_counter <= 2'b00;
                    done <= 1'b0;
                    last_op <= RD_DATA;
                end

                PR_ALG: begin
                    done <= 1'b0;
                    if (!has_alg_on_exec) begin // se não tem um algoritmo em execução = primeira execução
                        num_steps_needed <= 19'd47700;
                        addr_out <= last_addr_wr-16'd28800; //deslocamento até 1 quarto da imagem
                        state <= WAIT_WR_RD;
                        operation_step_counter <= 3'b000;
                    end else begin
                        if (operation_step_counter == 3'b100) begin // se for o ultimo passo 
                            algorithm_step_counter <= algorithm_step_counter + 1'b1; // incrementa um a contagem de passos
                            operation_step_counter <= 3'b000; //reseta o contador da operação
                            addr_out <= last_addr_wr+ 1'b1; //acessa o ultimo endereço escrito +1
                            wr_enable <= 1'b1; //habilita a escrita
                            state <= WAIT_WR_RD; //vai pro estado de aguardar a escrita acontecer
                        end else if (operation_step_counter > 3'b000 && operation_step_counter < 3'b100) begin //se não for o ultimo nem o primeiro
                            operation_step_counter <= operation_step_counter + 1'b1; //incrementa o contador da operação
                            addr_out <= last_addr_wr + 1'b1; //habilita a escrita
                            wr_enable <= 1'b1;
                            state <= WAIT_WR_RD;
                        end else if (operation_step_counter == 3'b000) begin // primeiro estagio
                            operation_step_counter <= operation_step_counter + 1'b1;
                            addr_out <= last_addr_rd + 1'b1;
                            state <= WAIT_WR_RD;
                        end
                    end
                    last_op <= PR_ALG;
                end
                NHI_ALG: begin
                    done <= 1'b0;
                    if (!has_alg_on_exec) begin //
                        num_steps_needed <= 19'd86100;
                        
                        addr_out <= last_addr_wr - 16'd28800;
                        state <= WAIT_WR_RD;
                        operation_step_counter <= 3'b000;
                    end
                    else if (operation_step_counter == 3'b001) begin
                        algorithm_step_counter <= algorithm_step_counter + 1'b1;
                        operation_step_counter <= 3'b000;
                        addr_out <= last_addr_wr + 1'b1;
                        wr_enable <= 1'b1;
                        state <= WAIT_WR_RD;
                        
                        if (count_y_new == 10'd239) begin
                            count_x_new <= count_x_new + 1'b1;
                            count_y_new <= 10'b0;
                        end else begin
                            count_y_new <= count_y_new + 1'b1;
                        end
                    
                    end else if (operation_step_counter == 3'b000) begin
                        operation_step_counter <= 3'b001;
                        addr_out <= last_addr_rd + (count_y_new>>2) + ((count_x_new>>2)*320);  //calcula o endereço do dado novo com base na imagem anterior e levando em conta que são 2 pixeis por endereço
                        state <= WAIT_WR_RD;
                    end
                    last_op <= NHI_ALG; //guarda "endereço" da ultima operação
                end

                NH_ALG: begin
                    if (!has_alg_on_exec) begin
                        
                    end
                end

                default: begin
                    addr_out <= addr_base;
                    done <= 1'b1;
                end
            endcase
    end


endmodule