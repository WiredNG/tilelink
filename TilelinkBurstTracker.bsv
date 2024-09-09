package TilelinkBurstTracker;

interface TLBurstTracker #(numeric type data_width, numeric type size_width);
    method Action handshake(Bit#(size_width) req_size);
    method Bool burst;
    method Bool first;
    method Bool last;
endinterface

module mkTLBurstTracker #(
    numeric type max_size
)(
    TLBurstTracker #(numeric type data_width, numeric type size_width)
);

typedef TSub#(TLog#(data_width), 3) non_burst_size;
typedef TSub#(max_size, non_burst_size) max_burst_size;

function Bit#(max_burst_size) get_burst_len(Bit#(size_width) size);
    UInt#(size_width) usize = unpack(size);
    if(usize < valueOf(non_burst_size)) return 0;
    return (1 << (usize - valueOf(non_burst_size))) - 1;
endfunction

Reg#(Bit#(max_burst_size))  burst_counter <- mkReg('1);
Wire#(Bit#(max_burst_size)) req_burst_size <- mkWire;
Wire#(Bit#(max_burst_size)) req_burst_left <- mkWire;

rule calc_left;
    req_burst_left = req_burst_size & counter;
endrule

rule upd_counter;
    burst_counter <= req_burst_left - 1;
endrule

Wire#(Bool) burst <- mkWire;
Wire#(Bool) first <- mkWire;
Wire#(Bool) last <- mkWire;

rule gen_status;
    burst <= req_burst_size != 0;
    first <= req_burst_left == req_burst_size;
    last  <= req_burst_left == 0;
endrule

method Action handshake (Bit#(size_width) req_size);
    req_burst_size <= get_burst_len(req_size);
endmethod

method burst = burst;
method first = first;
method last = last;

endpackage : TilelinkBurstTracker
