package Tilelink

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
    Bit#(data_width / 8) mask   ;
    Bool                 corrupt;
    Bit#(data_width)     data   ;
} TLA #(numeric type addr_width, numeric type data_width, numeric type size_width, numeric type source_width, numeric type sink_width) deriving(Bits, Eq, FShow);

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
} TLB #(numeric type addr_width, numeric type data_width, numeric type size_width, numeric type source_width, numeric type sink_width) deriving(Bits, Eq, FShow);

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
} TLC #(numeric type addr_width, numeric type data_width, numeric type size_width, numeric type source_width, numeric type sink_width) deriving(Bits, Eq, FShow);

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
} TLD #(numeric type addr_width, numeric type data_width, numeric type size_width, numeric type source_width, numeric type sink_width) deriving(Bits, Eq, FShow);

// E Channel definations

typedef struct {
    Bit#(sink_width)     sink   ;
} TLE #(numeric type addr_width, numeric type data_width, numeric type size_width, numeric type source_width, numeric type sink_width) deriving(Bits, Eq, FShow);

interface TilelinkMST#(numeric type addr_width, numeric type data_width, numeric type size_width, numeric type source_width, numeric type sink_width);
    Get#(TLA #(addr_width, data_width, size_width, source_width, sink_width)) tla;
    Put#(TLB #(addr_width, data_width, size_width, source_width, sink_width)) tlb;
    Get#(TLC #(addr_width, data_width, size_width, source_width, sink_width)) tlc;
    Put#(TLD #(addr_width, data_width, size_width, source_width, sink_width)) tld;
    Get#(TLE #(addr_width, data_width, size_width, source_width, sink_width)) tle;
endinterface

interface TilelinkSLV#(numeric type addr_width, numeric type data_width, numeric type size_width, numeric type source_width, numeric type sink_width);
    Put#(TLA #(addr_width, data_width, size_width, source_width, sink_width)) tla;
    Get#(TLB #(addr_width, data_width, size_width, source_width, sink_width)) tlb;
    Put#(TLC #(addr_width, data_width, size_width, source_width, sink_width)) tlc;
    Get#(TLD #(addr_width, data_width, size_width, source_width, sink_width)) tld;
    Put#(TLE #(addr_width, data_width, size_width, source_width, sink_width)) tle;
endinterface

instance Connectable#(TilelinkMST#(addr_width, data_width, size_width, source_width, sink_width), TilelinkSLV#(addr_width, data_width, size_width, source_width, sink_width));
    module mkConnection#(
        TilelinkMST#(addr_width, data_width, size_width, source_width, sink_width) mst,
        TilelinkSLV#(addr_width, data_width, size_width, source_width, sink_width) slv
    )(Empty);
        rule tilelink_a_channel;
            slv.tla.put(mst.tla.get);
        endrule
        rule tilelink_c_channel;
            slv.tlc.put(mst.tlc.get);
        endrule
        rule tilelink_e_channel;
            slv.tle.put(mst.tle.get);
        endrule
        rule tilelink_b_channel;
            mst.tlb.put(slv.tlb.get);
        endrule
        rule tilelink_d_channel;
            mst.tld.put(slv.tld.get);
        endrule
    endmodule
endinstance

instance Connectable#(TilelinkSLV#(addr_width, data_width, size_width, source_width, sink_width), TilelinkMST#(addr_width, data_width, size_width, source_width, sink_width));
    module mkConnection#(
        TilelinkSLV#(addr_width, data_width, size_width, source_width, sink_width) slv,
        TilelinkMST#(addr_width, data_width, size_width, source_width, sink_width) mst
    )(Empty);
        mkConnection(mst, slv);
    endmodule
endinstance

endpackage : Tilelink
