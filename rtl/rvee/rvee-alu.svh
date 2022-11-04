`ifndef __RVEE_ALU_SVH__
`define __RVEE_ALU_SVH__

// Yosys doesn't support enums yet.
`define ALU_ADD  3'b000
`define ALU_SLL  3'b001
`define ALU_SLT  3'b010
`define ALU_SLTU 3'b011
`define ALU_XOR  3'b100
`define ALU_SRL  3'b101
`define ALU_OR   3'b110
`define ALU_AND  3'b111

interface rvee_alu_if #(parameter XLEN=32) (input clk, input rst);
	logic	[2:0] op;
	logic	[XLEN - 1:0] a;
	logic	[XLEN - 1:0] b;
	logic	[XLEN - 1:0] d;
	logic	sra;
	// This holds a[XLEN - 1] ^ org_b[XLEN - 1] (i.e b prior to ~b)
	logic	msb_xor;
	logic	c;

	modport alu_port(
		input	op, a, b, msb_xor, c, sra,
		output	d);

	modport exec_port(
		output	op, a, b, msb_xor, c, sra,
		input	d);
endinterface
`endif
