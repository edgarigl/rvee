`timescale 1ns / 1ps
`include "include/axi.vh"

module top();
	wire    ACLK;
	wire    ARESETN;

	`AXILITE_NETS(m00_, 32, 32);
	`AXILITE_NETS(m01_, 32, 32);

	wire [31:0] resetv = 32'h00000000;

	rvee_wrapper_v corew_v(
			.aclk(ACLK),
			.aresetn(ARESETN),
			.resetv(resetv),
			`AXILITE_CONNECT_PORT(m00_, m00_),
			`AXILITE_CONNECT_PORT(m01_, m01_));

	design_1_wrapper bd(.ACLK(ACLK), .ARESETN(ARESETN),
			`AXILITE_CONNECT_PORT(S00_AXI_0_, m00_),
			`AXILITE_CONNECT_PORT(S01_AXI_0_, m01_),

			// Tie-off
			.S00_AXI_0_arsize(2),
			.S00_AXI_0_arlen(0),
			.S00_AXI_0_arburst(`AXI_BURST_INCR),
			.S00_AXI_0_awsize(2),
			.S00_AXI_0_awlen(0),
			.S00_AXI_0_awburst(0),
			.S00_AXI_0_wlast(1),

			.S01_AXI_0_arsize(2),
			.S01_AXI_0_arlen(0),
			.S01_AXI_0_arburst(`AXI_BURST_INCR),
			.S01_AXI_0_awsize(2),
			.S01_AXI_0_awlen(0),
			.S01_AXI_0_awburst(`AXI_BURST_INCR),
			.S01_AXI_0_wlast(1)
			);

	assign	S00_AXI_0_arprot = `AXI_PROT_NS | `AXI_PROT_INSN;
	assign	S00_AXI_0_awprot = `AXI_PROT_NS;
	assign	S01_AXI_0_arprot = `AXI_PROT_NS;
	assign	S01_AXI_0_awprot = `AXI_PROT_NS;
endmodule
