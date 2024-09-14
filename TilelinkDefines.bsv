package TilelinkDefines;

`define _TLPACKAGES
`include "TilelinkHeader.bsv"

// A Channel definations
import Connectable::*;
import GetPut::*;

typedef enum {
    PutFullData    = 3'h0,
    PutPartialData = 3'h1,
    ArithmeticData = 3'h2,
    LogicalData    = 3'h3,
    Get            = 3'h4,
    Intent         = 3'h5,
    AcquireBlock   = 3'h6,
    AcquirePerm    = 3'h7
} TLA_OP deriving(Bits, Eq, FShow);

typedef struct {
    TLA_OP               opcode ;
    Bit#(3)              param  ;
    Bit#(size_width)     size   ;
    Bit#(source_width)   source ;
    Bit#(addr_width)     address;
    Bit#(TDiv#(data_width, 8)) mask   ;
    Bool                 corrupt;
    Bit#(data_width)     data   ;
} TLA #(`TLPARMSDEF) deriving(Bits, Eq, FShow);

// B Channel definations

typedef enum {
    ProbeBlock     = 3'h6,
    ProbePerm      = 3'h7
} TLB_OP deriving(Bits, Eq, FShow);

typedef struct {
    TLB_OP               opcode ;
    Bit#(3)              param  ;
    Bit#(size_width)     size   ;
    Bit#(source_width)   source ;
    Bit#(addr_width)     address;
} TLB #(`TLPARMSDEF) deriving(Bits, Eq, FShow);

// C Channel definations

typedef enum {
  ProbeAck     = 3'h4,
  ProbeAckData = 3'h5,
  Release      = 3'h6,
  ReleaseData  = 3'h7
} TLC_OP deriving(Bits, Eq, FShow);

typedef struct {
    TLC_OP               opcode ;
    Bit#(3)              param  ;
    Bit#(size_width)     size   ;
    Bit#(source_width)   source ;
    Bit#(addr_width)     address;
    Bool                 corrupt;
    Bit#(data_width)     data   ;
} TLC #(`TLPARMSDEF) deriving(Bits, Eq, FShow);

// D Channel definations

typedef enum {
  AccessAck     = 3'h0,
  AccessAckData = 3'h1,
  HintAck       = 3'h2,
  Grant         = 3'h4,
  GrantData     = 3'h5,
  ReleaseAck    = 3'h6
} TLD_OP deriving(Bits, Eq, FShow);

typedef struct {
    TLD_OP               opcode ;
    Bit#(3)              param  ;
    Bit#(size_width)     size   ;
    Bit#(source_width)   source ;
    Bit#(sink_width)     sink   ;
    Bool                 denied ;
    Bool                 corrupt;
    Bit#(data_width)     data   ;
} TLD #(`TLPARMSDEF) deriving(Bits, Eq, FShow);

// E Channel definations

typedef struct {
    Bit#(sink_width)     sink   ;
} TLE #(`TLPARMSDEF) deriving(Bits, Eq, FShow);


// Record of local Tilelink information

typedef struct {
    Bit#(source_width) source_id;
    Bit#(sink_width) sink_id;
} TLINFO #(`TLPARMSDEF) deriving(Bits, Eq, FShow);

interface TilelinkMST#(`TLPARMSDEF);
    interface Get#(TLA #(`TLPARMS)) tla;
    interface Put#(TLB #(`TLPARMS)) tlb;
    interface Get#(TLC #(`TLPARMS)) tlc;
    interface Put#(TLD #(`TLPARMS)) tld;
    interface Get#(TLE #(`TLPARMS)) tle;
endinterface

interface TilelinkSLV#(`TLPARMSDEF);
    interface Put#(TLA #(`TLPARMS)) tla;
    interface Get#(TLB #(`TLPARMS)) tlb;
    interface Put#(TLC #(`TLPARMS)) tlc;
    interface Get#(TLD #(`TLPARMS)) tld;
    interface Put#(TLE #(`TLPARMS)) tle;
endinterface

instance Connectable#(TilelinkMST#(`TLPARMS), TilelinkSLV#(`TLPARMS));
    module mkConnection#(
        TilelinkMST#(`TLPARMS) mst,
        TilelinkSLV#(`TLPARMS) slv
    )(Empty);
        rule tilelink_a_channel;
            let p <- mst.tla.get;
            slv.tla.put(p);
        endrule
        rule tilelink_c_channel;
            let p <- mst.tlc.get;
            slv.tlc.put(p);
        endrule
        rule tilelink_e_channel;
            let p <- mst.tle.get;
            slv.tle.put(p);
        endrule
        rule tilelink_b_channel;
            let p <- slv.tlb.get;
            mst.tlb.put(p);
        endrule
        rule tilelink_d_channel;
            let p <- slv.tld.get;
            mst.tld.put(p);
        endrule
    endmodule
endinstance

instance Connectable#(TilelinkSLV#(`TLPARMS), TilelinkMST#(`TLPARMS));
    module mkConnection#(
        TilelinkSLV#(`TLPARMS) slv,
        TilelinkMST#(`TLPARMS) mst
    )(Empty);
        mkConnection(mst, slv);
    endmodule
endinstance

endpackage : TilelinkDefines
