package TilelinkFake;

`define _TLPACKAGES
`include "TilelinkHeader.bsv"

import Vector::*;
import XArbiter::*;
import Arbiter::*;
import TilelinkDefines::*;
import TilelinkBurstTracker::*;
import GetPut::*;
import CrossBar::*;
import FIFO::*;
import FIFOF::*;
import StmtFSM::*;

// Do a ping pong transaction between Mst and Slv
// Mst issue Tilelink-A with arbiter posible size
// Slv receive Tilelink-A and issue Tilelink-B,
// Mst receive Tilelink-B and issue Tilelink-C with arbiter posible size,
// Slv receive Tilelink-C and issue Tilelink-D with arbiter posible size,
// Mst receive Tilelink-D and issue Tilelink-E with release of ID
module mkTilelinkPingPongMst #(
    TLINFO#(`TLPARMS) info,
    FIFO#(TLA#(`TLPARMS)) tla_src, // A Request queue
    FIFO#(Bit#(source_width)) id_dst, // ID Release queue
    Bool verbose
)(
    TilelinkMST#(`TLPARMS)
) provisos (
    NumAlias#(non_burst_size, TSub#(TLog#(data_width), 3)),
    NumAlias#(max_burst_size, TSub#(max_size, non_burst_size)),
    Bits#(Int#(TAdd#(TSub#(max_size, TSub#(TLog#(data_width), 3)), 1)), size_width)
);

    // Forward logic for TLB.
    FIFOF#(TLB#(`TLPARMS)) tlb_dst <- mkFIFOF;
    FIFO#(TLC#(`TLPARMS)) tlc_src <- mkFIFO;
    Reg#(Int#(TAdd#(max_burst_size,1))) tlc_burst_count <- mkRegU;
    // Transfer tlb to tlc
    let b2c_fsm <- mkFSM(
        seq
            action
                Bit#(max_burst_size) tmp = (1 << (tlb_dst.first.size - fromInteger(valueOf(non_burst_size)))) - 1;
                if(verbose) $display("%x Forward message %x tlb to tlc with burst support, beats count: %d", info.source, tlb_dst.first.source, tmp + 1);
                tlc_burst_count <= unpack({1'b0,tmp});
            endaction
            while (tlc_burst_count >= 0) seq
                action
                    let payload = TLC {
                            opcode  : ProbeAckData,
                            param   : tlb_dst.first.param,
                            size    : tlb_dst.first.size,
                            source  : tlb_dst.first.source,
                            address : tlb_dst.first.address,
                            corrupt : False,
                            data    : '0
                    };
                    tlc_src.enq(payload);
                    if(tlb_dst.notEmpty && tlc_burst_count == 0) begin
                        // Keep FSM Running From stop.
                        Bit#(max_burst_size) tmp = (1 << (tlb_dst.first.size - fromInteger(valueOf(non_burst_size)))) - 1;
                        if(verbose) $display("%x Forward message %x tlb to tlc with burst support, beats count: %d", info.source, tlb_dst.first.source, tmp + 1);
                        tlc_burst_count <= unpack({1'b0,tmp});
                        tlb_dst.deq();
                    end else begin
                        tlc_burst_count <= tlc_burst_count - 1;
                    end
                endaction
            endseq
            tlb_dst.deq();
        endseq
    );
    rule start_fsm(tlb_dst.notEmpty);
        b2c_fsm.start;
    endrule

    Wire#(Bool) d_ready <- mkWire;
    Wire#(TLD#(`TLPARMS)) tld_wire <- mkWire;
    FIFOF#(TLE#(`TLPARMS)) tle_src <- mkFIFOF;
    // Burst tracker here.
    TLBurstTracker #(data_width, size_width, max_size) tld_tracker <- mkTLBurstTracker;

    rule d_ready_handle(tle_src.notFull);
        d_ready <= True;
    endrule
    rule e_handle(tld_tracker.last);
        let ret = TLE {
            sink : tld_wire.sink
        };
        id_dst.enq(tld_wire.source);
        tle_src.enq(ret);
    endrule

    interface tla = (
        interface Get#(TLA #(`TLPARMS));
            method ActionValue#(TLA #(`TLPARMS)) get();
                let tla <- toGet(tla_src).get();
                return tla;
            endmethod
        endinterface
    );
    interface tlb = (
        interface Put#(TLB #(`TLPARMS));
            method Action put(TLB#(`TLPARMS) p);
                toPut(tlb_dst).put(p);
                if(verbose) $display("MST TLB Get request %x", p.source);
            endmethod
        endinterface
    );
    interface tlc = (
        interface Get#(TLC #(`TLPARMS));
            method ActionValue#(TLC #(`TLPARMS)) get();
                let tlc <- toGet(tlc_src).get();
                return tlc;
            endmethod
        endinterface
    );
    interface tld = (
        interface Put#(TLD #(`TLPARMS));
            method Action put(TLD#(`TLPARMS) p);
                if(d_ready) begin
                    tld_tracker.handshake(p.size);
                    tld_wire <= p;
                    if(verbose) $display("MST TLD Get request %x", p.source);
                end
            endmethod
        endinterface
    );
    interface tle = (
        interface Get#(TLE #(`TLPARMS));
            method ActionValue#(TLE #(`TLPARMS)) get();
                let tle <- toGet(tle_src).get();
                return tle;
            endmethod
        endinterface
    );

endmodule

module mkTilelinkPingPongSlv #(
    TLINFO#(`TLPARMS) info,
    Bool verbose
)(
    TilelinkSLV#(`TLPARMS)
);
    // TLA Maybe burstify
    Wire#(Bool) a_ready <- mkWire;
    Wire#(TLA#(`TLPARMS)) tla_wire <- mkWire;
    FIFOF#(TLB#(`TLPARMS)) tlb_src <- mkFIFOF;
    // Burst tracker here.
    TLBurstTracker #(data_width, size_width, max_size) tla_tracker <- mkTLBurstTracker;
    rule a_ready_handle(tlb_src.notFull);
        a_ready <= True;
    endrule
    rule a_handle(tla_tracker.last);
        let ret = TLB {
            opcode  : ProbeBlock,
            param   : tla_wire.param,
            size    : tla_wire.size,
            source  : tla_wire.source,
            address : tla_wire.address
        };
        tlb_src.enq(ret);
    endrule

    // TLC Maybe burstify, So we directly pass it to TLD.
    FIFO#(TLC#(`TLPARMS)) tlc_dst <- mkFIFO;
    FIFO#(TLD#(`TLPARMS)) tld_src <- mkFIFO;
    rule c_handle;
        let tlc = tlc_dst.first;
        let ret = TLD {
            opcode  : AccessAckData,
            param   : tlc.param,
            size    : tlc.size,
            source  : tlc.source,
            sink    : info.sink,
            denied  : False,
            corrupt : tlc.corrupt,
            data    : tlc.data
        };
        $display("Enq TLD Request %x with size %d", tlc.source, tlc.size);
        tld_src.enq(ret);
        tlc_dst.deq();
    endrule

    // Put interface for tla
    interface Put tla;
        method Action put(TLA#(`TLPARMS) p);
            if(a_ready) begin
                Bit#(3) op = pack(p.opcode);
                tla_wire <= p;
                tla_tracker.handshake(unpack(op[2]) ? '0 : p.size);
                if(verbose) $display("SLV TLA Get request %x", p.source);
            end
        endmethod
    endinterface
    interface tlb = (
        interface Get#(TLB #(`TLPARMS));
            method ActionValue#(TLB #(`TLPARMS)) get();
                let tlb <- toGet(tlb_src).get();
                return tlb;
            endmethod
        endinterface
    );
    interface tlc = (
        interface Put#(TLC #(`TLPARMS));
            method Action put(TLC#(`TLPARMS) p);
                toPut(tlc_dst).put(p);
                if(verbose) $display("SLV TLC Get request %x", p.source);
            endmethod
        endinterface
    );
    interface tld = (
        interface Get#(TLD #(`TLPARMS));
            method ActionValue#(TLD #(`TLPARMS)) get();
                let tld <- toGet(tld_src).get();
                return tld;
            endmethod
        endinterface
    );
    interface tle = (
        interface Put#(TLE #(`TLPARMS));
            method Action put(TLE#(`TLPARMS) p);
                if(verbose) $display("E final packet received.");
            endmethod
        endinterface
    );

endmodule

endpackage