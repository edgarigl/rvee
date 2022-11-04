/*
 * RVee ALU.
 *
 * Copyright (C) 2022 Edgar E. Iglesias.
 * Written by Edgar E. Iglesias <edgar.iglesias@gmail.com>
 */

/* verilator lint_off DECLFILENAME */
`include "rvee/rvee-alu.svh"

module rvee_alu #(parameter XLEN=32) (
	rvee_alu_if.alu_port alu_if);

	/* For readability.  */
	logic	[XLEN - 1:0] a;
	logic	[XLEN - 1:0] b;
	logic	[XLEN - 1:0] d;

	logic	[XLEN + 1:0] add_d;
	logic	[$clog2(XLEN) - 1:0] shift_b;
	logic	ignore;

	logic	[2:0] op;

	assign	alu_if.d = d;

	always_comb begin
		a = alu_if.a;
		b = alu_if.b;
		op = alu_if.op;

		/* Reuse the adder for add/sub.  */
		add_d = {1'b0, a, alu_if.c} + {1'b0, b, 1'b1};
		shift_b = b[$clog2(XLEN) - 1:0];

		/* Defaults to avoid latches.  */
		ignore = 0;

		case (op)
		`ALU_ADD:  d = add_d[XLEN:1];
		`ALU_SLL:  d = a << shift_b;
		`ALU_SLT: begin
			// Note that b got reversed by the decode stage so
			// we need to reverse it back here.
			if (alu_if.msb_xor)
				d = a[XLEN - 1] ? 1 : 0;
			else
				d = add_d[XLEN] ? 1 : 0;
		end
		`ALU_SLTU: d = add_d[XLEN + 1] ? 0 : 1;
		`ALU_SRL:  {ignore, d} = $signed({alu_if.sra & a[XLEN - 1], a}) >>> shift_b;
		`ALU_XOR:  d = a ^ b;
		`ALU_OR:   d = a | b;
		`ALU_AND:  d = a & b;
		endcase
	end
endmodule
