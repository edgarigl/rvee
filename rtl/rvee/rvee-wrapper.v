// Clean Verilog wrapper.
`include "include/axi.vh"
module rvee_wrapper_v #(parameter AWIDTH=32, DWIDTH=32, XLEN=32) (
	input	aclk,
	input	aresetn,
	input	[XLEN - 1:0] resetv,
	input	meip, msip, mtip,
	`AXILITE_MASTER_PORT("FETCH", m00_, AWIDTH, DWIDTH),
	`AXILITE_MASTER_PORT("MEM", m01_, AWIDTH, DWIDTH)
	);

	rvee_wrapper corew(.aclk(aclk),
			   .aresetn(aresetn),
			   .resetv(resetv),
			   .meip(meip),
			   .msip(msip),
			   .mtip(mtip),
			   `AXILITE_CONNECT_PORT(m00_, m00_),
			   `AXILITE_CONNECT_PORT(m01_, m01_));
endmodule
