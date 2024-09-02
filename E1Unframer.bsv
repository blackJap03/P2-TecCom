module mkE1Unframer(E1Unframer);
    // Estado e registros
    FIFOF#(Tuple2#(Timeslot, Bit#(1))) fifo_out <- mkFIFOF;
    Reg#(State) state <- mkReg(UNSYNCED);
    Reg#(Bit#(TLog#(8))) cur_bit <- mkRegU;
    Reg#(Timeslot) cur_ts <- mkReg(0);
    Reg#(Bool) fas_turn <- mkReg(False);
    Reg#(Bit#(8)) cur_byte <- mkReg(0);

    // Sequências de FAS e NFAS
    Bit#(7) FAS_PATTERN = 7'b0011011;
    Bit#(7) NFAS_MASK = 7'b0111111; // O segundo bit deve ser 1
    Bit#(7) NFAS_VALID = 7'b0100000;

    interface out = toGet(fifo_out);

    interface Put in;
        method Action put(Bit#(1) b);
            cur_byte <= {cur_byte[6:0], b}; // Shiftar para a direita para construir o byte atual

            case (state)
                UNSYNCED: begin
                    cur_ts <= 0;
                    if (cur_byte[6:0] == FAS_PATTERN) begin
                        state <= FIRST_FAS;
                        cur_bit <= 0;
                    end
                end

                // Inicialização do FIRST FAS
                FIRST_FAS: begin
                    cur_ts <= cur_ts + 1;
                    cur_bit <= cur_bit + 1;

                    if (cur_ts == 30) begin
                        // Verificar se o próximo TS0 é um NFAS válido
                        if ((cur_byte & NFAS_MASK) == NFAS_VALID) begin
                            state <= FIRST_NFAS;
                        end else begin
                            state <= UNSYNCED;
                        end
                        cur_ts <= 0;
                        cur_bit <= 0;
                    end
                end

                // Inicialização do FIRST NFAS
                FIRST_NFAS: begin
                    cur_ts <= cur_ts + 1;
                    cur_bit <= cur_bit + 1;

                    if (cur_ts == 30) begin
                        // Verificar se o próximo TS0 é um FAS válido
                        if (cur_byte[6:0] == FAS_PATTERN) begin
                            state <= SYNCED;
                        end else begin
                            state <= UNSYNCED;
                        end
                        cur_ts <= 0;
                        cur_bit <= 0;
                    end
                end
                
                // Inicialização do SYNCED STATE
                SYNCED: begin
                    // Gerar saída para os timeslots TS1-TS31
                    if (cur_ts != 0) begin
                        fifo_out.enq(tuple2(cur_ts, b));
                    end

                    cur_ts <= cur_ts + 1;
                    cur_bit <= cur_bit + 1;

                    if (cur_ts == 30) begin
                        // Verificar se o próximo TS0 é um FAS ou NFAS válido
                        if (fas_turn) begin
                            if (cur_byte[6:0] != FAS_PATTERN) begin
                                state <= UNSYNCED;
                            end
                        end else begin
                            if ((cur_byte & NFAS_MASK) != NFAS_VALID) begin
                                state <= UNSYNCED;
                            end
                        end
                        fas_turn <= ~fas_turn;
                        cur_ts <= 0;
                        cur_bit <= 0;
                    end
                end
            endcase
        endmethod
    endinterface
endmodule
