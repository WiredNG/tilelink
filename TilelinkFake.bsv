package TilelinkFake;


// Do a ping pong transaction between Mst and Slv
// Mst issue Tilelink-A with arbiter posible size
// Slv receive Tilelink-A and issue Tilelink-B,
// Mst receive Tilelink-B and issue Tilelink-C with arbiter posible size,
// Slv receive Tilelink-C and issue Tilelink-D with arbiter posible size,
// Mst receive Tilelink-D and issue Tilelink-E with release of ID
module mkTilelinkPingPongMst (

);

endmodule

module mkTilelinkPingPongSlv (

);

endmodule

endpackage