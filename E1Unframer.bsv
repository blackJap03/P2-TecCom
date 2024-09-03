import GetPut::*;
import FIFOF::*;
import Assert::*;

typedef Bit#(TLog#(32)) Timeslot;

interface E1Unframer;
    interface Put#(Bit#(1)) in;
    interface Get#(Tuple2#(Timeslot, Bit#(1))) out;
endinterface

typedef enum {
    UNSYNCED,
    FIRST_FAS,
    FIRST_NFAS,
    SYNCED
} State deriving (Bits, Eq, FShow);

module mkE1Unframer(E1Unframer);
    // Estado e registros
    FIFOF#(Tuple2#(Timeslot, Bit#(1))) fifo_out <- mkFIFOF;
    Reg#(State) state <- mkReg(UNSYNCED);
    Reg#(Bit#(TLog#(8))) cur_bit <- mkRegU;
    Reg#(Timeslot) cur_ts <- mkReg(0);
    Reg#(Bool) fas_turn <- mkReg(False);
    Reg#(Bit#(8)) cur_byte <- mkReg(0);

    // Sequências de FAS e NFAS
    let fas_pattern = 7'b0011011;
    let nfas_mask = 8'h7F; // 01111111 em binário
    let nfas_valid = 8'h40; // 01000000 em binário

    interface out = toGet(fifo_out);

    interface Put in;
        method Action put(Bit#(1) b);
            cur_byte <= {cur_byte[6:0], b}; // Shiftar para a direita para construir o byte atual

            case (state)
                UNSYNCED: begin
                    cur_ts <= 0;
                    if (cur_byte[7:1] == fas_pattern) begin
                        state <= FIRST_FAS;
                        cur_bit <= 0;
                    end
                end

                FIRST_FAS: begin
                    cur_ts <= cur_ts + 1;
                    cur_bit <= cur_bit + 1;

                    if (cur_ts == 30) begin
                        // Verificar se o próximo TS0 é um NFAS válido
                        Bit#(8) nfas_check = cur_byte & nfas_mask;
                        if (nfas_check == nfas_valid) begin
                            state <= FIRST_NFAS;
                        end else begin
                            state <= UNSYNCED;
                        end
                        cur_ts <= 0;
                        cur_bit <= 0;
                    end
                end

                FIRST_NFAS: begin
                    cur_ts <= cur_ts + 1;
                    cur_bit <= cur_bit + 1;

                    if (cur_ts == 30) begin
                        // Verificar se o próximo TS0 é um FAS válido
                        if (cur_byte[7:1] == fas_pattern) begin
                            state <= SYNCED;
                        end else begin
                            state <= UNSYNCED;
                        end
                        cur_ts <= 0;
                        cur_bit <= 0;
                    end
                end

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
                            if (cur_byte[7:1] != fas_pattern) begin
                                state <= UNSYNCED;
                            end
                        end else begin
                            // Verificar se a máscara corresponde ao valor esperado para NFAS
                            Bit#(8) nfas_check = cur_byte & nfas_mask;
                            Bool nfas_valid_check = nfas_check == nfas_valid; // Comparação como booleano
                            if (!nfas_valid_check) begin
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
