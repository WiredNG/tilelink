package TilelinkCrossBar;

`define _TLPACKAGES
`include "TilelinkHeader.bsv"

import Vector::*;
import XArbiter::*;
import Arbiter::*;
import TilelinkDefines::*;
import TilelinkBurstTracker::*;
import GetPut::*;
import CrossBar::*;

// Note: Tileilnk Burst should not be interrupted.
// So we need to rewrite arbiter to keep track of Burst request.
module mkTLXArbiter #(
    TLINFO#(`TLPARMS) info,
    function Bit#(size_width) getInfoFromTLx(tlx_t payload),
    module #(Arbiter_IFC#(mst_num)) mkArb
)(
    XArbiter#(mst_num, tlx_t)
) provisos (
    Bits#(tlx_t, tlx_size_t)
);

    TLBurstTracker #(data_width, size_width, max_size) tracker <- mkTLBurstTracker;
    Arbiter_IFC#(mst_num) arb <- mkArb;

    Reg#(Bool) locked <- mkReg(False);
    Reg#(Vector#(mst_num, Bool)) lock_vec <- mkReg(unpack('0));
    Reg#(Bit#(TLog#(mst_num))) lock_idx <- mkReg('0);
    Wire#(Vector#(mst_num, tlx_t)) payloads <- mkWire;

    // Update locked status
    rule upd_lock_handshake;
        if(arb.clients[arb.grant_id].grant) begin
            // Handshaked
            tracker.handshake(getInfoFromTLx(payloads[arb.grant_id]));
        end
    endrule

    // Update locked status
    rule upd_lock_regwrite;
        if(tracker.burst && tracker.first) begin
            // Lock in first beat
            Bit#(TLog#(mst_num)) idx = 0;
            locked <= True;
            for(Integer m = 0 ; m < valueOf(mst_num) ; m = m + 1) begin
                lock_vec[m] <= arb.clients[m].grant;
                if(arb.clients[m].grant) idx = idx | fromInteger(m);
            end
            lock_idx <= idx;
        end else if(tracker.last) begin
            // Unlock in last beat
            locked <= False;
            lock_vec <= unpack('0);
        end
    endrule

    Vector#(mst_num, XArbiterClient#(tlx_t)) ifs = ?;
    for(Integer m = 0 ; m < valueOf(mst_num) ; m = m + 1) begin
        ifs[m] = (
            interface XArbiterClient#(tlx_t);
                method Action request(tlx_t payload);
                    payloads[m] <= payload;
                    if(!locked || lock_vec[m]) begin
                        arb.clients[m].request;
                    end
                endmethod

                method Bool grant;
                    if(!locked) return arb.clients[m].grant;
                    else return lock_vec[m];
                endmethod
            endinterface
        );
    end
    interface clients = ifs;
    method Bit#(TLog#(mst_num)) grant_id;
        if(!locked) return arb.grant_id;
        else return lock_idx;
    endmethod

endmodule

module mkTLXConnection #(
    function Bit#(slv_num) routeAddress(mst_index_t mst, Bit#(addr_width) addr),
    function Bit#(mst_num) routeSource(slv_index_t slv, Bit#(source_width) source),
    function Bit#(slv_num) routeSink(mst_index_t mst, Bit#(sink_width) sink),
    module #(Arbiter_IFC#(mst_num)) mkArbMst,
    module #(Arbiter_IFC#(slv_num)) mkArbSlv,
    Vector#(mst_num, TilelinkMST#(`TLPARMS)) mst_if,
    Vector#(slv_num, TilelinkSLV#(`TLPARMS)) slv_if
)(Empty) provisos(
    Alias#(mst_index_t, Bit#(TLog#(mst_num))),
    Alias#(slv_index_t, Bit#(TLog#(slv_num)))
);

    Vector#(mst_num, Get#(TLA#(`TLPARMS))) mst_a_intf = ?;
    Vector#(mst_num, Put#(TLB#(`TLPARMS))) mst_b_intf = ?;
    Vector#(mst_num, Get#(TLC#(`TLPARMS))) mst_c_intf = ?;
    Vector#(mst_num, Put#(TLD#(`TLPARMS))) mst_d_intf = ?;
    Vector#(mst_num, Get#(TLE#(`TLPARMS))) mst_e_intf = ?;
    Vector#(slv_num, Put#(TLA#(`TLPARMS))) slv_a_intf = ?;
    Vector#(slv_num, Get#(TLB#(`TLPARMS))) slv_b_intf = ?;
    Vector#(slv_num, Put#(TLC#(`TLPARMS))) slv_c_intf = ?;
    Vector#(slv_num, Get#(TLD#(`TLPARMS))) slv_d_intf = ?;
    Vector#(slv_num, Put#(TLE#(`TLPARMS))) slv_e_intf = ?;

    for(Integer m = 0 ; m < valueOf(mst_num) ; m = m + 1) begin
        // Extract master intf
        mst_a_intf[m] = mst_if[m].tla;
        mst_b_intf[m] = mst_if[m].tlb;
        mst_c_intf[m] = mst_if[m].tlc;
        mst_d_intf[m] = mst_if[m].tld;
        mst_e_intf[m] = mst_if[m].tle;
    end

    for(Integer s = 0 ; s < valueOf(slv_num) ; s = s + 1) begin
        // Extract slave intf
        slv_a_intf[s] = slv_if[s].tla;
        slv_b_intf[s] = slv_if[s].tlb;
        slv_c_intf[s] = slv_if[s].tlc;
        slv_d_intf[s] = slv_if[s].tld;
        slv_e_intf[s] = slv_if[s].tle;
    end

    // Create routing function
    // Channel A and Channel C are routed by address.
    function Bit#(slv_num) routeA(mst_index_t mst, TLA#(`TLPARMS) tla);
        return routeAddress(mst, tla.address);
    endfunction
    function Bit#(slv_num) routeC(mst_index_t mst, TLC#(`TLPARMS) tlc);
        return routeAddress(mst, tlc.address);
    endfunction

    // Channel B and Channel D are routed by source.
    function Bit#(mst_num) routeB(slv_index_t slv, TLB#(`TLPARMS) tlb);
        return routeSource(slv, tlb.source);
    endfunction
    function Bit#(mst_num) routeD(slv_index_t slv, TLD#(`TLPARMS) tld);
        return routeSource(slv, tld.source);
    endfunction

    // Channel E are routed by sink
    function Bit#(slv_num) routeE(mst_index_t mst, TLE#(`TLPARMS) tle);
        return routeSink(mst, tle.sink);
    endfunction

    function Bit#(size_width) getSizeFromTLA(TLA#(`TLPARMS) tla);
        Bit#(3) op = pack(tla.opcode);
        return unpack(op[3]) ? '0 : tla.size;
    endfunction

    function Bit#(size_width) getSizeFromTLC(TLC#(`TLPARMS) tlc);
        return tlc.size;
    endfunction

    function Bit#(size_width) getSizeFromTLD(TLD#(`TLPARMS) tld);
        return tld.size;
    endfunction

    // Create Empty INFO to pass parameters.
    TLINFO#(`TLPARMS) tInfo = unpack('0);

    // Create 5 Crossbar
    mkCrossbarConnect(routeA, mkTLXArbiter(tInfo, getSizeFromTLA, mkArbMst), mst_a_intf, slv_a_intf);
    mkCrossbarConnect(routeB, mkXArbiter(mkArbSlv), slv_b_intf, mst_b_intf);
    mkCrossbarConnect(routeC, mkTLXArbiter(tInfo, getSizeFromTLC, mkArbMst), mst_c_intf, slv_c_intf);
    mkCrossbarConnect(routeD, mkTLXArbiter(tInfo, getSizeFromTLD, mkArbSlv), slv_d_intf, mst_d_intf);
    mkCrossbarConnect(routeE, mkXArbiter(mkArbMst), mst_e_intf, slv_e_intf);

endmodule

endpackage : TilelinkCrossBar