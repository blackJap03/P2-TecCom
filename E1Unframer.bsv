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
    FIFOF#(Tuple2#(Timeslot, Bit#(1))) fifo_out <- mkFIFOF;
    Reg#(State) current_state <- mkReg(UNSYNCED);
    Reg#(Bit#(TLog#(8))) current_bit_index <- mkRegU;
    Reg#(Timeslot) current_ts <- mkRegU;
    Reg#(Bool) fas_turn <- mkRegU;
    Reg#(Bit#(8)) current_byte <- mkReg(0);

    interface out = toGet(fifo_out);

    interface Put in;
        method Action put(Bit#(1) b);
            let new_byte = {current_byte[6:0], b};

            case (current_state)
                // Estado inicial onde a sincronização não foi obtida
                UNSYNCED:
                    if (new_byte[6:0] == 7'b0011011) action
                        current_state <= FIRST_FAS;
                        current_bit_index <= 0;
                        current_ts <= 1;
                        fas_turn <= True;
                    endaction
                // Estado após encontrar o primeiro FAS    
                FIRST_FAS:
                    if (current_ts == 0 && current_bit_index == 7) action
                        if (new_byte[6] == 1) action
                            current_state <= FIRST_NFAS;
                            current_bit_index <= 0;
                            current_ts <= 1;
                            fas_turn <= False;
                        endaction
                        else action
                            current_state <= UNSYNCED;
                        endaction
                    endaction
                    else if (current_bit_index == 7) action
                        current_ts <= current_ts + 1;
                        current_bit_index <= 0;
                    endaction
                    else action
                        current_bit_index <= current_bit_index + 1;
                    endaction
                // Estado após encontrar o primeiro NFAS
                FIRST_NFAS:
                    if (current_ts == 0 && current_bit_index == 7) action
                        if (new_byte[6:0] == 7'b0011011) action
                            current_state <= SYNCED;
                            current_bit_index <= 0;
                            current_ts <= 1;
                            fas_turn <= True;
                        endaction
                        else action
                            current_state <= UNSYNCED;
                        endaction
                    endaction
                    else if (current_bit_index == 7) action
                        current_ts <= current_ts + 1;
                        current_bit_index <= 0;
                    endaction
                    else action
                        current_bit_index <= current_bit_index + 1;
                    endaction
                // Estado onde a sincronização foi obtida e mantida
                SYNCED:
                    action
                        if (current_ts == 0 && current_bit_index == 7) action
                            if (fas_turn) action
                                // Próximo é NFAS
                                if (new_byte[6] == 1) action
                                    current_bit_index <= 0;
                                    current_ts <= 1;
                                    fas_turn <= False;
                                endaction
                                else action
                                    current_state <= UNSYNCED;
                                endaction
                            endaction
                            else action
                                // Próximo é NFAS
                                if (new_byte[6:0] == 7'b0011011) action
                                    current_bit_index <= 0;
                                    current_ts <= 1;
                                    fas_turn <= True;
                                endaction
                                else action
                                    current_state <= UNSYNCED;
                                endaction
                            endaction
                        endaction
                        else if (current_bit_index == 7) action
                            current_ts <= current_ts + 1;
                            current_bit_index <= 0;
                        endaction
                        else action
                            current_bit_index <= current_bit_index + 1;
                        endaction

                        fifo_out.enq(tuple2(current_ts, b));
                    endaction
            endcase

            current_byte <= new_byte;
        endmethod
    endinterface
endmodule