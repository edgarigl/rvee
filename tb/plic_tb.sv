`include "include/axi.svh"

module plic_tb #(parameter AWIDTH=32, DWIDTH=32, NUM_SOURCES=128, NUM_TARGETS=128) (
	input	clk,
	input	rst,
	input	[NUM_SOURCES - 1:0] source,
	output	[NUM_TARGETS - 1:0] target,
	`AXILITE_TARGET_PORT("regs", , AWIDTH, DWIDTH)
	);

	axi4lite_if axi_if();
	plic #(.NUM_SOURCES(NUM_SOURCES), .NUM_TARGETS(NUM_TARGETS)) ic(.*);

	`AXILITE_TARGET_PROPAGATE(axi_if, );
endmodule
