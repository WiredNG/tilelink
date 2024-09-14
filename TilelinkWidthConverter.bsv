package TilelinkWidthConverter;

import Vector::*;
import GetPut::*;

// Master port width is bigger than Slave port
module mkTLXWidthDownsizer (
    Tuple2#(
        Put#(Tuple3#(ptr_t, ptr_t, payload_mst_t)),
        Get#(payload_slv_t)
    )
) provisos (
    Bits#(payload_mst_t, mst_width),
    Bits#(payload_slv_t, slv_width),
    Div#(mst_width, slv_width, muler),
    Bits#(ptr_t, TLog#(muler))
);

Reg#(Bool) v[2] <- mkCReg(2, False);
Reg#(ptr_t) rptr[2] <- mkCReg(2, ?);
Reg#(ptr_t) left[2] <- mkCReg(2, ?);
Reg#(Vector#(muler, Bit#(slv_width))) buffer [2] <- mkCReg(2, ?);

Wire#(Bit#(slv_width)) slv_data <- mkWire;
rule slv_read(v[1]);
    slv_data <= buffer[1][rptr[1]];
endrule

Wire#(Bool) put_barrier <- mkWire;
rule put_guard(!v[0]);
    put_barrier <= True;
endrule

let p = (
interface Put#(Tuple3#(ptr_t, ptr_t, payload_mst_t));
    method Action put(Tuple3#(ptr_t, ptr_t, payload_mst_t) payload);
        match {.rshift, .length, .data} = payload;
        if(put_barrier) begin
            v[0] <= True;
            rptr[0] <= rshift;
            left[0] <= length;
            buffer[0] <= unpack(data);
        end
    endmethod
endinterface
);

let g = (
interface Get#(payload_slv_t);
    method ActionValue#(payload_slv_t) get();
        if(left[1] == 0) begin
            v[1] <= False;
        end
        rptr[1] <= rptr[1] + 1;
        left[1] <= left[1] - 1;
        return slv_data;
    endmethod
endinterface
);

return tuple2(p, g);

endmodule

module mkTLXWidthUpsizer (
    Tuple2#(
        Put#(Tuple3#(ptr_t, ptr_t, payload_mst_t)),
        Get#(payload_slv_t)
    )
) provisos (
    Bits#(payload_mst_t, mst_width),
    Bits#(payload_slv_t, slv_width),
    Div#(slv_width, mst_width, muler),
    Bits#(ptr_t, TLog#(muler))
);

Reg#(Bool) v[2] <- mkCReg(2, False);
Reg#(ptr_t) rptr[2] <- mkCReg(2, ?);
Reg#(ptr_t) left[2] <- mkCReg(2, ?);
Reg#(Vector#(muler, Bit#(mst_width))) buffer [2] <- mkCReg(2, ?);

Wire#(Bit#(slv_width)) slv_data <- mkWire;
rule slv_read(v[1] && left[1] == 0);
    slv_data <= buffer[1];
endrule

// No on-going transfer.
Wire#(Bool) put_barrier <- mkWire;
rule put_guard(!v[0] || left[0] != 0);
    put_barrier <= True;
endrule

let p = (
interface Put#(Tuple3#(ptr_t, ptr_t, payload_mst_t));
    method Action put(Tuple3#(ptr_t, ptr_t, payload_mst_t) payload);
        match {.rshift, .length, .data} = payload;
        if(put_barrier) begin
            if(!v[0]) begin
                // First beat
                v[0] <= True;
                rptr[0] <= rshift + 1;
                left[0] <= length;
                buffer[0][rshift] <= data;
            end else begin
                v[0] <= left[0] == 1;
                rptr[0] <= rptr[0] + 1;
                left[0] <= left[0] - 1;
                buffer[0][rptr[0]] <= data;
            end
        end
    endmethod
endinterface
);

let g = (
interface Get#(payload_slv_t);
    method ActionValue#(payload_slv_t) get();
        return slv_data;
    endmethod
endinterface
);

return tuple2(p, g);

endmodule

endpackage : TilelinkWidthConverter
