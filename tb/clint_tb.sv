`include "include/axi.svh"

module clint_tb #(parameter AWIDTH=32, DWIDTH=32, NUM_TARGETS=1024) (
	input	clk,
	input	rst,
	output	[NUM_TARGETS - 1:0] target_sip,
	output	[NUM_TARGETS - 1:0] target_tip,
	`AXILITE_TARGET_PORT("regs", , AWIDTH, DWIDTH)
	);

	axi4lite_if axi_if();
	clint #(.NUM_TARGETS(NUM_TARGETS)) ic(.*);

	`AXILITE_TARGET_PROPAGATE(axi_if, );
endmodule
