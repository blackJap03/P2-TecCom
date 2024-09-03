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
    // FIFO para a saída
    FIFOF#(Tuple2#(Timeslot, Bit#(1))) fifo_out <- mkFIFOF;
    
    // Estados
    Reg#(State) state <- mkReg(UNSYNCED);
    Reg#(Bit#(TLog#(8))) cur_bit <- mkRegU;
    Reg#(Timeslot) cur_ts <- mkRegU;
    Reg#(Bool) fas_turn <- mkReg(False);
    Reg#(Bit#(8)) cur_byte <- mkReg(0);

    // Sequências FAS e NFAS (ajustadas para Bit#(8))
    Bit#(8) fas = 8'b00110110; // note que foi ajustado para 8 bits
    Bit#(2) nfas_valid = 2'b10;

    // Regra única para atualizar cur_ts
    rule update_cur_ts;
        if (cur_bit == 7) begin
            cur_ts <= cur_ts + 1;
        end
    endrule

    interface out = toGet(fifo_out);

    interface Put in;
        method Action put(Bit#(1) b);
            // Desloca os bits em cur_byte para a esquerda e insere o novo bit
            cur_byte <= (cur_byte << 1) | zeroExtend(b);
            
            if (cur_bit == 7) begin
                cur_bit <= 0;
            end else begin
                cur_bit <= cur_bit + 1;
            end

            case (state)
                UNSYNCED: begin
                    if (cur_byte == fas) begin
                        state <= FIRST_FAS;
                        cur_ts <= 0;
                    end
                end

                FIRST_FAS: begin
                    if (cur_ts == 31) begin
                        if (cur_byte[6:5] == nfas_valid) begin
                            state <= FIRST_NFAS;
                        end else begin
                            state <= UNSYNCED;
                        end
                    end
                end

                FIRST_NFAS: begin
                    if (cur_ts == 31) begin
                        if (cur_byte == fas) begin
                            state <= SYNCED;
                        end else begin
                            state <= UNSYNCED;
                        end
                    end
                end

                SYNCED: begin
                    if (cur_ts == 0) begin
                        // Verifica TS0 para fas/NFAS
                        if ((fas_turn && cur_byte != fas) || (!fas_turn && cur_byte[6:5] != nfas_valid)) begin
                            state <= UNSYNCED;
                        end
                        fas_turn <= !fas_turn;
                    end else begin
                        // Produz saída válida para TS1-31
                        fifo_out.enq(tuple2(cur_ts, b));
                    end
                end
            endcase
        endmethod
    endinterface

endmodule
