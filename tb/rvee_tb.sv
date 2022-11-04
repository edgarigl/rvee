`include "include/axi.svh"
`include "rvee/rvee-pcgen.svh"
`include "rvee/rvee-fetch.svh"
`include "rvee/rvee-decode.svh"
`include "rvee/rvee-exec.svh"
`include "rvee/rvee-mem.svh"
`include "rvee/rvee-rf.svh"

module rvee_tb #(parameter AWIDTH=32, DWIDTH=32, XLEN=32) (
	input	aclk,
	input	aresetn,
	input	[XLEN - 1:0] resetv,
	`AXILITE_MASTER_PORT("FETCH", m00_, AWIDTH, DWIDTH),
	`AXILITE_MASTER_PORT("MEM", m01_, AWIDTH, DWIDTH),
	`AXILITE_TARGET_PORT("CLINT", s00_, AWIDTH, DWIDTH)
	);

	wire	clk = aclk;
	wire	rst = !aresetn;

	wire	target_sip;
	wire	target_tip;
	wire	meip = 0;
	wire	seip = 0;
	wire	ssip = 0;
	wire	stip = 0;

	axi4lite_if axi_fetch_if(.*);
	axi4lite_if axi_mem_if(.*);
	axi4lite_if axi_if(.*);

	rvee_wrapper corew(.*, .msip(target_sip), .mtip(target_tip));

	clint #(.NUM_TARGETS(1)) lic(.*);

	`AXILITE_MASTER_PROPAGATE(axi_fetch_if, m00_);
	`AXILITE_MASTER_PROPAGATE(axi_mem_if, m01_);
	`AXILITE_TARGET_PROPAGATE(axi_if, s00_);
endmodule
