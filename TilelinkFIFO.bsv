package TilelinkFIFO;

`define _TLPACKAGES
`include "TilelinkHeader.bsv"

import Vector::*;
import TilelinkDefines::*;
import TilelinkBurstTracker::*;
import GetPut::*;
import FIFO::*;

module mkTilelinkFIFO #(
    module #(FIFO#(TLA#(`TLPARMS))) mkFA,
    module #(FIFO#(TLB#(`TLPARMS))) mkFB,
    module #(FIFO#(TLC#(`TLPARMS))) mkFC,
    module #(FIFO#(TLD#(`TLPARMS))) mkFD,
    module #(FIFO#(TLE#(`TLPARMS))) mkFE
)(
    Tuple2#(TilelinkMST#(`TLPARMS), TilelinkSLV#(`TLPARMS))
);

    FIFO#(TLA#(`TLPARMS)) fifo_a <- mkFA;
    FIFO#(TLB#(`TLPARMS)) fifo_b <- mkFB;
    FIFO#(TLC#(`TLPARMS)) fifo_c <- mkFC;
    FIFO#(TLD#(`TLPARMS)) fifo_d <- mkFD;
    FIFO#(TLE#(`TLPARMS)) fifo_e <- mkFE;

    TilelinkMST#(`TLPARMS) slv_socket;
    TilelinkSLV#(`TLPARMS) mst_socket;
    
    slv_socket.tla = toGet(fifo_a);
    slv_socket.tlb = toPut(fifo_b);
    slv_socket.tlc = toGet(fifo_c);
    slv_socket.tld = toPut(fifo_d);
    slv_socket.tle = toGet(fifo_e);

    mst_socket.tla = toPut(fifo_a);
    mst_socket.tlb = toGet(fifo_b);
    mst_socket.tlc = toPut(fifo_c);
    mst_socket.tld = toGet(fifo_d);
    mst_socket.tle = toPut(fifo_e);

    return tuple2(slv_socket, mst_socket);

endmodule
endpackage