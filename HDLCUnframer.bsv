import GetPut::*;
import FIFOF::*;
import Assert::*;

interface HDLCUnframer;
    interface Put#(Bit#(1)) in; 
    interface Get#(Tuple2#(Bool, Bit#(8))) out;
endinterface

typedef enum {
    IDLE,               
    PROCESS_FRAME,      
    CHECK_BIT_STUFFING  
} FrameState deriving (Eq, Bits, FShow);

module mkHDLCUnframer(HDLCUnframer);
    // Sugestão de elementos de estado (podem ser alterados caso conveniente)
    FIFOF#(Tuple2#(Bool, Bit#(8))) fifo_out <- mkFIFOF; 
    Reg#(Bool) start_of_frame <- mkReg(True);
    Reg#(FrameState) current_state <- mkReg(IDLE); // Estado atual
    Reg#(Bit#(3)) bit_index <- mkReg(0); // Índice do bit atual no byte
    Reg#(Bit#(8)) current_frame_byte <- mkRegU; // Byte atual do quadro
    Reg#(Bit#(8)) recent_bits <- mkReg(0); 

    // Flag HDLC padrão que indica início/fim de quadro
    Bit#(8) hdlc_flag_pattern = 8'b01111110;

    interface out = toGet(fifo_out);

    // Interface de entrada de bits
    interface Put in;
        method Action put(Bit#(1) b);
            let updated_recent_bits = {b, recent_bits[7:1]};
            let next_bit_index = bit_index + 1;
            let updated_frame_byte = {b, current_frame_byte[7:1]};
            // Preserva o estado atual por padrão
            let next_state = current_state;
            // Verifica se há possível bit de preenchimento
            let check_bit_stuffing = updated_recent_bits[7:3] == 5'b11111;

            // Transição de estados com base no estado atual
            case (current_state)
                IDLE:
                    // Verifica o padrão de flag HDLC para iniciar um quadro
                    if (updated_recent_bits == hdlc_flag_pattern) action
                        next_state = PROCESS_FRAME;
                        next_bit_index = 0;
                        start_of_frame <= True;
                    endaction
                PROCESS_FRAME:
                    action
                        // Se o byte estiver completo, enfileira o byte no FIFO
                        if (bit_index == 7) action
                            next_state = check_bit_stuffing ? CHECK_BIT_STUFFING : PROCESS_FRAME;
                            fifo_out.enq(tuple2(start_of_frame, updated_frame_byte));
                            start_of_frame <= False;
                        endaction
                        else if (check_bit_stuffing) action
                            // Transita para verificar bit de preenchimento se necessário
                            next_state = CHECK_BIT_STUFFING;
                        endaction
                        current_frame_byte <= updated_frame_byte;
                    endaction
                CHECK_BIT_STUFFING:
                    if (b == 1) action
                        // Flag ou erro detectado
                        next_state = IDLE;
                    endaction
                    else action
                        // Bit de preenchimento detectado, ignora e continua processando o quadro
                        next_state = PROCESS_FRAME;
                        next_bit_index = bit_index;
                    endaction
            endcase
            // Atualização 
            recent_bits <= updated_recent_bits;
            bit_index <= next_bit_index;
            current_state <= next_state;
        endmethod
    endinterface
endmodule