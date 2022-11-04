`include "include/axi.svh"
`include "rvee/rvee-pcgen.svh"
`include "rvee/rvee-fetch.svh"
`include "rvee/rvee-decode.svh"
`include "rvee/rvee-exec.svh"
`include "rvee/rvee-mem.svh"
`include "rvee/rvee-rf.svh"

module rvee_wrapper #(parameter AWIDTH=32, DWIDTH=32, XLEN=32) (
	input	aclk,
	input	aresetn,
	input	[XLEN - 1:0] resetv,
	input	meip, msip, mtip,
	input	seip, ssip, stip,
	`AXILITE_MASTER_PORT("FETCH", m00_, AWIDTH, DWIDTH),
	`AXILITE_MASTER_PORT("MEM", m01_, AWIDTH, DWIDTH)
	);

	wire	clk = aclk;
	wire	rst = !aresetn;

	axi4lite_if axi_fetch_if(.*);
	axi4lite_if axi_mem_if(.*);

	rvee_core core(.*);

	`AXILITE_MASTER_PROPAGATE(axi_fetch_if, m00_);
	`AXILITE_MASTER_PROPAGATE(axi_mem_if, m01_);
endmodule
