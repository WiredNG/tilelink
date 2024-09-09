package TilelinkCrossBar;

import Vector::*;
import XArbiter::*;
import Tilelink::*;
import CrossBar::*;

module mkTilelinkConnection #(
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
    tla_crossbar <- mkCrossbarConnect(routeA, mkArbMst, mst_a_intf, slv_a_intf);
    tlb_crossbar <- mkCrossbarConnect(routeB, mkArbSlv, slv_b_intf, mst_b_intf);
    tlc_crossbar <- mkCrossbarConnect(routeC, mkArbMst, mst_c_intf, slv_c_intf);
    tld_crossbar <- mkCrossbarConnect(routeD, mkArbSlv, slv_d_intf, mst_d_intf);
    tle_crossbar <- mkCrossbarConnect(routeE, mkArbMst, mst_e_intf, slv_e_intf);

endmodule

endpackage : TilelinkCrossBar