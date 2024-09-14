package TilelinkBurstTracker;

`define _TLPACKAGES
`include "TilelinkHeader.bsv"

interface TLBurstTracker #(numeric type data_width, numeric type size_width, numeric type max_size);
    method Action handshake(Bit#(size_width) req_size);
    method Bool valid;
    method Bool burst;
    method Bool first;
    method Bool last;
endinterface

module mkTLBurstTracker (
    TLBurstTracker #(data_width, size_width, max_size)
) provisos (
    NumAlias#(non_burst_size, TSub#(TLog#(data_width), 3)),
    NumAlias#(max_burst_size, TSub#(max_size, non_burst_size))
);

function Bit#(max_burst_size) get_burst_len(Bit#(size_width) size);
    UInt#(size_width) usize = unpack(size);
    if(usize < fromInteger(valueOf(non_burst_size))) usize = fromInteger(valueOf(non_burst_size));
    return (1 << (usize - fromInteger(valueOf(non_burst_size)))) - 1;
endfunction

Reg#(Bit#(max_burst_size))  burst_counter <- mkReg('1);
Wire#(Bit#(max_burst_size)) req_burst_size <- mkWire;
Wire#(Bit#(max_burst_size)) req_burst_left <- mkWire;

rule calc_left;
    req_burst_left <= req_burst_size & burst_counter;
endrule

rule upd_counter;
    burst_counter <= req_burst_left - 1;
endrule

Wire#(Bool) valid_wire <- mkDWire(False);
Wire#(Bool) burst_wire <- mkDWire(False);
Wire#(Bool) first_wire <- mkDWire(False);
Wire#(Bool) last_wire  <- mkDWire(False);

rule gen_status;
    valid_wire <= True;
    burst_wire <= req_burst_size != 0;
    first_wire <= req_burst_left == req_burst_size;
    last_wire  <= req_burst_left == 0;
endrule

method Action handshake (Bit#(size_width) req_size);
    req_burst_size <= get_burst_len(req_size);
endmethod

method valid = valid_wire;
method burst = burst_wire;
method first = first_wire;
method last = last_wire;

endmodule

endpackage : TilelinkBurstTracker
