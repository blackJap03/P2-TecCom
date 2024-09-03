import GetPut::*;
import FIFOF::*;
import Assert::*;

interface HDLCUnframer;
    interface Put#(Bit#(1)) in;
    interface Get#(Tuple2#(Bool, Bit#(8))) out;
endinterface

module mkHDLCUnframer(HDLCUnframer);
    FIFOF#(Tuple2#(Bool, Bit#(8))) fifo_out <- mkFIFOF;
    Reg#(Bool) start_of_frame <- mkReg(True);
    Bit#(9) octet_reset_value = 9'b1_0000_0000;
    Reg#(Bit#(9)) octet <- mkReg(octet_reset_value);
    Reg#(Bit#(7)) recent_bits <- mkReg(0);

    interface out = toGet(fifo_out);

    interface Put in;
        method Action put(Bit#(1) b);
            Bool is_flag = (recent_bits == 7'b1111110);
            Bool is_bit_stuffed = (recent_bits[6:2] == 5'b11111) && (b == 0);

            Bit#(9) next_octet = octet;
            Bit#(7) next_recent_bits = (recent_bits << 1) | zeroExtend(b);

            if (is_flag) begin
                start_of_frame <= True;
                next_octet = octet_reset_value;
                next_recent_bits = 0;
            end else if (!is_bit_stuffed) begin
                next_octet = (octet << 1) | zeroExtend(b);

                if (next_octet[8] == 1'b1) begin
                    if (start_of_frame) begin
                        fifo_out.enq(tuple2(True, next_octet[7:0]));
                        start_of_frame <= False;
                    end else begin
                        fifo_out.enq(tuple2(False, next_octet[7:0]));
                    end
                    next_octet = octet_reset_value;
                end
            end
            
            octet <= next_octet;
            recent_bits <= next_recent_bits;
        endmethod
    endinterface
endmodule
