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
// Note: mst_num >= 2
module mkCoreTLXArbiter #(
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

    // Two status: lock / unlock
    // When Arbiter is unlock, select one request and feed to tracker.
    // When Arbiter is locked, feed to tracker directly without further step.
    Reg#(Bool) locked[2] <- mkCReg(2, False);
    Reg#(Bit#(mst_num)) lock_vec[2] <- mkCReg(2, 0);
    Reg#(Bit#(TLog#(mst_num))) lock_idx[2] <- mkCReg(2, ?);
    Vector#(mst_num, Wire#(tlx_t)) payloads <- replicateM(mkDWire(?));
    Vector#(mst_num, Wire#(Bool)) valid <- replicateM(mkDWire(False));
    Wire#(tlx_t) sel_payload <- mkWire;

    rule lock_vec_update_handle;
        Bit#(mst_num) tmp = 0;
        tmp[arb.grant_id] = 1;
        if(!locked[0]) begin
            lock_vec[0] <= tmp;
            lock_idx[0] <= arb.grant_id;
        end
    endrule

    rule locked_update_handle;
        if(tracker.valid && tracker.burst && tracker.first) locked[0] <= True; // Lock
        else if(tracker.valid && tracker.last) locked[0] <= False; // Unlock
    endrule

    rule sel_payload_handle;
        sel_payload <= payloads[lock_idx[1]];
    endrule

    rule handshake_handle;
        Bit#(mst_num) judge = 0;
        for(Integer m = 0 ; m < valueOf(mst_num) ; m = m + 1) begin
            judge[m] = pack(valid[m] && unpack(lock_vec[1][m]));
        end
        if(judge != 0) begin
            tracker.handshake(getInfoFromTLx(sel_payload));
        end
    endrule

    Vector#(mst_num, XArbiterClient#(tlx_t)) ifs = ?;
    for(Integer m = 0 ; m < valueOf(mst_num) ; m = m + 1) begin
        ifs[m] = (
            interface XArbiterClient#(tlx_t);
                method Action request(tlx_t payload);
                    payloads[m] <= payload;
                    valid[m] <= True;
                    if(!locked[0]) arb.clients[m].request;
                endmethod

                method Bool grant;
                    return unpack(lock_vec[1][m]) && valid[m];
                endmethod
            endinterface
        );
    end
    interface clients = ifs;
    method Bit#(TLog#(mst_num)) grant_id;
        return lock_idx[1];
    endmethod

endmodule

module mkTLXArbiter #(
    TLINFO#(`TLPARMS) info,
    function Bit#(size_width) getInfoFromTLx(tlx_t payload),
    module #(Arbiter_IFC#(mst_num)) mkArb
)(
    XArbiter#(mst_num, tlx_t)
) provisos (
    Bits#(tlx_t, tlx_size_t)
);
    XArbiter#(mst_num, tlx_t) intf;
    if(valueOf(mst_num) < 2) begin
        intf <- mkXArbiter(mkArb);
    end else begin
        intf <- mkCoreTLXArbiter(info, getInfoFromTLx, mkArb);
    end
    return intf;
endmodule

module mkTilelinkCrossBar #(
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
        mst_a_intf[m] = mst_if[m].tla;
        mst_b_intf[m] = mst_if[m].tlb;
        mst_c_intf[m] = mst_if[m].tlc;
        mst_d_intf[m] = mst_if[m].tld;
        mst_e_intf[m] = mst_if[m].tle;
    end

    for(Integer s = 0 ; s < valueOf(slv_num) ; s = s + 1) begin
        slv_a_intf[s] = slv_if[s].tla;
        slv_b_intf[s] = slv_if[s].tlb;
        slv_c_intf[s] = slv_if[s].tlc;
        slv_d_intf[s] = slv_if[s].tld;
        slv_e_intf[s] = slv_if[s].tle;
    end

    // Create routing function
    // Channel A and Channel C are routed by address.
    function Bit#(slv_num) routeA(mst_index_t mst, TLA#(`TLPARMS) tla) = routeAddress(mst, tla.address);
    function Bit#(slv_num) routeC(mst_index_t mst, TLC#(`TLPARMS) tlc) = routeAddress(mst, tlc.address);

    // Channel B and Channel D are routed by source.
    function Bit#(mst_num) routeB(slv_index_t slv, TLB#(`TLPARMS) tlb) = routeSource(slv, tlb.source);
    function Bit#(mst_num) routeD(slv_index_t slv, TLD#(`TLPARMS) tld) = routeSource(slv, tld.source);

    // Channel E are routed by sink
    function Bit#(slv_num) routeE(mst_index_t mst, TLE#(`TLPARMS) tle) = routeSink(mst, tle.sink);

    function Bit#(size_width) getSizeFromTLA(TLA#(`TLPARMS) tla) = unpack(pack(tla.opcode)[2]) ? '0 : tla.size;
    function Bit#(size_width) getSizeFromTLC(TLC#(`TLPARMS) tlc) = tlc.size;
    function Bit#(size_width) getSizeFromTLD(TLD#(`TLPARMS) tld) = tld.size;

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