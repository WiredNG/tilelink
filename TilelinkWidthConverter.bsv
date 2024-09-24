package TilelinkWidthConverter;

// This module is still WIP, because WiredNG dont need it.

`define _TLPACKAGES
`include "TilelinkHeader.bsv"

import TilelinkDefines::*;
import TilelinkBurstTracker::*;
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
        v[1] <= 0;
        return slv_data;
    endmethod
endinterface
);

return tuple2(p, g);

endmodule

module mkTLWidthUpsizer #(
    TilelinkMST#(addr_width, mdata_width, size_width, source_width, sink_width, max_size) mst_if,
    TilelinkSLV#(addr_width, sdata_width, size_width, source_width, sink_width, max_size) slv_if
)(Empty) provisos (
    Div#(sdata_width, mdata_width, muler),
    Alias#(ptr_t, Bit#(TLog#(muler))),
    NumAlias#(mst_non_burst_size, TSub#(TLog#(mdata_width), 3)),
    NumAlias#(slv_non_burst_size, TSub#(TLog#(sdata_width), 3))
);
    // B-E Pass through
    rule pass_b;
        let slv_b <- slv_if.tlb.get();
        mst_if.tlb.put(TLB#(addr_width, mdata_width, size_width, source_width, sink_width, max_size){
            opcode  : slv_b.opcode,
            param   : slv_b.param,
            size    : slv_b.size,
            source  : slv_b.source,
            address : slv_b.address
        });
    endrule
    rule pass_e;
        let mst_e <- mst_if.tle.get();
        slv_if.tle.put(TLE#(addr_width, sdata_width, size_width, source_width, sink_width, max_size){
            sink : mst_e.sink
        });
    endrule

    // A Pass through
    // RSHIFT LENGTH DATA
    Tuple2#(Put#(Tuple3#(ptr_t, ptr_t, Bit#(mdata_width))),Get#(Bit#(sdata_width))) tla_upsizer <- mkTLXWidthUpsizer();
    matches {tla_upsizer_put, tla_upsizer_get} = tla_upsizer;
    Reg#(TLA#(addr_width, sdata_width, size_width, source_width, sink_width, max_size)) tla_meta_buffer [2] <- mkCReg(2, ?);
    rule mst_a_handle;
        let mst_a <- mst_if.tla.get();
        Bit#(3) op = pack(mst_a.opcode);
        Bit#(TExp#(size_width)) req_size = 0;
        req_size[mst_a.size] = 1;
        ptr_t rshift = mst_a.address[TAdd#(mst_non_burst_size,TLog#(muler)):mst_non_burst_size];
        ptr_t length = ?;
        if(mst_a.size < mst_non_burst_size || unpack(op[3])) begin
            // No burst size in case size is smaller than width or Write request.
            length = 0;
        end else begin
            // Burstify size
            length = req_size[TAdd#(mst_non_burst_size,TLog#(muler)):mst_non_burst_size] - 1;
        end
        Bit#(mdata_width) data = mst_a.data;
        tla_upsizer_put.put(tuple3(rshift, length, data));
        tla_meta_buffer[0] <= {
            opcode  : mst_a.opcode,
            param   : mst_a.param,
            size    : mst_a.size,
            source  : mst_a.source,
            address : mst_a.address,
            mask    : mst_a.mask,
            corrupt : mst_a.corrupt,
            data    : ?
        };
    endrule
    rule slv_a_handle;
        let data <- tla_upsizer_get.get();
        let req <- tla_meta_buffer[1];
        req.data = data;
        slv_if.tla.put(req);
    endrule

    // C Pass through
    TLBurstTracker#(mdata_width, size_width, max_size) tlc_tracker <- mkTLBurstTracker;
    Tuple2#(Put#(Tuple3#(ptr_t, ptr_t, Bit#(mdata_width))),Get#(Bit#(sdata_width))) c = mkTLXWidthUpsizer();
    Tuple2#(Put#(Tuple3#(ptr_t, ptr_t, Bit#(sdata_width))),Get#(Bit#(mdata_width))) d = mkTLXWidthDownsizer();

    // D Pass through
    TLBurstTracker#(sdata_width, size_width, max_size) tld_tracker <- mkTLBurstTracker;

endmodule

endpackage : TilelinkWidthConverter
