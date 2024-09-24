
`define TLPARMSDEF numeric type addr_width, numeric type data_width, numeric type size_width, numeric type source_width, numeric type sink_width, numeric type max_size
`define TLPARMS addr_width, data_width, size_width, source_width, sink_width, max_size

`ifndef _TLPACKAGES
`define _TLPACKAGES
import TilelinkDefines::*;
import TilelinkBurstTracker::*;
import TilelinkCrossBar::*;
import TilelinkFake::*;
import TilelinkBurstTracker::*;
// import TilelinkWidthConverter::*;
`endif
