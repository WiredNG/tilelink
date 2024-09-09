package TilelinkCrossBar;

import Vector::*;
import XArbiter::*;
import Arbiter::*;
import Tilelink::*;
import TilelinkTracker::*;
import CrossBar::*;

// Note: Tileilnk Burst should not be interrupted.
// So we need to rewrite arbiter to keep track of Burst request.
module mkTLXArbiter#(
    numeric type max_size, numeric type data_width,
    function Bit#(size_width) getInfoFromTLx(tlx_t payload),
    module #(Arbiter_IFC#(mst_num)) mkArb
)(
    XArbiter#(mst_num, tlx_t)
);

    TLBurstTracker #(data_width, size_width) tracker <- mkTLBurstTracker(max_size);
    Arbiter_IFC#(mst_num) arb <- mkArb;

    Reg#(Bool) locked <- mkReg(0);
    Reg#(Vector#(mst_num, Bool)) lock_vec <- mkReg(0);
    Reg#(Bit#(TLog#(mst_num))) lock_idx <- mkReg(0);
    Wire#(Vector#(mst_num, tlx_t)) payloads <- mkWire;

    // Update locked status
    rule upd_lock_handshake;
        if(arb.clients[arb.grant_id]) begin
            // Handshaked
            tracker.handshake(getInfoFromTLx(payload[arb.grant_id]));
        end
    endrule

    // Update locked status
    rule upd_lock_regwrite;
        if(tracker.busrt && tracker.first) begin
            // Lock in first beat
            Bit#(TLog#(mst_num)) idx = 0;
            locked <= True;
            for(Integer m = 0 ; m < mst_num ; m = m + 1) begin
                lock_vec[m] <= arb.clients[m].grant;
                if(arb.clients[m].grant) idx = idx | fromInteger(m);
            end
            lock_idx <= idx;
        end else if(tracker.last) begin
            // Unlock in last beat
            locked <= False;
            lock_vec <= '0;
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

module mkTilelinkConnection #(
    numeric type max_size,
    function Bit#(slv_num) routeAddress(mst_index_t mst, Bit#(addr_width) addr),
    function Bit#(mst_num) routeSource(slv_index_t slv, Bit#(source_width) source),
    function Bit#(slv_num) routeSink(mst_index_t mst, Bit#(sink_width) sink),
    module #(Arbiter_IFC#(mst_num)) mkArbMst,
    module #(Arbiter_IFC#(slv_num)) mkArbSlv,
    Vector#(mst_num, TilelinkMST#(addr_width, data_width, size_width, source_width, sink_width)) mst_if,
    Vector#(slv_num, TilelinkSLV#(addr_width, data_width, size_width, source_width, sink_width)) slv_if
)(Empty) provisos(
    Alias#(mst_index_t, Bit#(TLog#(mst_num))),
    Alias#(slv_index_t, Bit#(TLog#(slv_num)))
);

    typedef TLA#(addr_width, data_width, size_width, source_width, sink_width) X_TLA;
    typedef TLB#(addr_width, data_width, size_width, source_width, sink_width) X_TLB;
    typedef TLC#(addr_width, data_width, size_width, source_width, sink_width) X_TLC;
    typedef TLD#(addr_width, data_width, size_width, source_width, sink_width) X_TLD;
    typedef TLE#(addr_width, data_width, size_width, source_width, sink_width) X_TLE;

    function Bit#(size_width) getSizeFromTLA(X_TLA tla);
        Bit#(3) op = pack(tla.opcode);
        return op[3] ? '0 : tla.size;
    endfunction

    function Bit#(size_width) getSizeFromTLD(X_TLD tld);
        return tld.size;
    endfunction

    Vector#(mst_num, Get#(X_TLA)) mst_a_intf = ?;
    Vector#(mst_num, Put#(X_TLB)) mst_b_intf = ?;
    Vector#(mst_num, Get#(X_TLC)) mst_c_intf = ?;
    Vector#(mst_num, Put#(X_TLD)) mst_d_intf = ?;
    Vector#(mst_num, Get#(X_TLE)) mst_e_intf = ?;
    Vector#(slv_num, Put#(X_TLA)) slv_a_intf = ?;
    Vector#(slv_num, Get#(X_TLB)) slv_b_intf = ?;
    Vector#(slv_num, Put#(X_TLC)) slv_c_intf = ?;
    Vector#(slv_num, Get#(X_TLD)) slv_d_intf = ?;
    Vector#(slv_num, Put#(X_TLE)) slv_e_intf = ?;

    for(integer m = 0 ; m < valueOf(mst_num) ; m = m + 1) begin
        // Extract master intf
        mst_a_intf[m] = mst_if[m].tla;
        mst_b_intf[m] = mst_if[m].tlb;
        mst_c_intf[m] = mst_if[m].tlc;
        mst_d_intf[m] = mst_if[m].tld;
        mst_e_intf[m] = mst_if[m].tle;
    end

    for(integer s = 0 ; s < valueOf(slv_num) ; s = s + 1) begin
        // Extract slave intf
        slv_a_intf[m] = slv_if[m].tla;
        slv_b_intf[m] = slv_if[m].tlb;
        slv_c_intf[m] = slv_if[m].tlc;
        slv_d_intf[m] = slv_if[m].tld;
        slv_e_intf[m] = slv_if[m].tle;
    end
    
    // Create routing function
    // Channel A and Channel C are routed by address.
    function Bit#(slv_num) routeA(mst_index_t mst, X_TLA tla);
        return routeAddress(mst, tla.address);
    endfunction
    function Bit#(slv_num) routeC(mst_index_t mst, X_TLC tlc);
        return routeAddress(mst, tlc.address);
    endfunction

    // Channel B and Channel D are routed by source.
    function Bit#(mst_num) routeB(slv_index_t slv, X_TLB tlb);
        return routeSource(slv, tlb.address);
    endfunction
    function Bit#(mst_num) routeD(slv_index_t slv, X_TLD tld);
        return routeSource(slv, tld.address);
    endfunction

    // Channel E are routed by sink
    function Bit#(slv_num) routeE(mst_index_t mst, X_TLE tle);
        return routeSink(mst, tle.sink);
    endfunction

    // Create 5 Crossbar
    tla_crossbar <- mkCrossbarConnect(routeA, mkTLXArbiter(max_size, data_width, getSizeFromTLA, mkArbMst), mst_a_intf, slv_a_intf);
    tlb_crossbar <- mkCrossbarConnect(routeB, mkXArbiter(mkArbSlv), slv_b_intf, mst_b_intf);
    tlc_crossbar <- mkCrossbarConnect(routeC, mkXArbiter(mkArbMst), mst_c_intf, slv_c_intf);
    tld_crossbar <- mkCrossbarConnect(routeD, mkTLXArbiter(max_size, data_width, getSizeFromTLD, mkArbSlv), slv_d_intf, mst_d_intf);
    tle_crossbar <- mkCrossbarConnect(routeE, mkXArbiter(mkArbMst), mst_e_intf, slv_e_intf);

endmodule

endpackage : TilelinkCrossBar