/*
 * RVee PC generator.
 *
 * Copyright (C) 2022 Edgar E. Iglesias.
 * Written by Edgar E. Iglesias <edgar.iglesias@gmail.com>
 *
 * SPDX-License-Identifier: MIT
 */

/* verilator lint_off DECLFILENAME */
`include "rvee/rvee-pcgen.svh"

module rvee_pcgen #(parameter XLEN=32) (
	input clk,
	input rst,
	input [XLEN - 1:0] resetv,
	rvee_pcgen_if.pcgen_port pcgen_if);

	logic	[XLEN - 1:0] jmp_base_ff;
	logic	[XLEN - 1:0] jmp_offset_ff;

	logic	[XLEN - 1:0] a;
	logic	[XLEN - 1:0] b;
	logic	[XLEN - 1:0] d;
always_comb begin
	// Jump and branch logic.
	//
	// pcgen_if.bcc is presented to us from EX, one cycle late.
	// pcgen_if.jmp presented to us from EX.
	//
	// For both jmp and bcc, EX presents jmp_base and jmp_offset.
	//
	// To align bcc and jmp, we flop all the jmp* signals into
	// jmp*_ff versions.
	// So we're using jmp_ff | bcc and jmp_base_ff + jmp_offset_ff.
	//
	// jmp and bcc have no back-pressure. They are presented for a
	// single cycle.
	// 
	a = pcgen_if.pc_ff;
	b = pcgen_if.ready_ff ? 4 : 0;
	// bcc is combinatonal and arrives one cycle late.
	pcgen_if.jmp_out = pcgen_if.jmp_ff | pcgen_if.bcc;
	if (pcgen_if.jmp_out) begin
		a = jmp_base_ff;
		b = jmp_offset_ff;
	end

	d = a + b;
	pcgen_if.pc = {d[XLEN - 1:1], 1'b0};
end

always_ff @(posedge clk) begin
	pcgen_if.valid <= 1;
	pcgen_if.jmp_ff <= pcgen_if.jmp;
	jmp_base_ff <= pcgen_if.jmp_base;
	jmp_offset_ff <= pcgen_if.jmp_offset;

	if (pcgen_if.ready_ff | pcgen_if.jmp_out) begin
		pcgen_if.pc_ff <= pcgen_if.pc;
	end

	if (rst) begin
		pcgen_if.valid <= 0;
		pcgen_if.pc_ff <= {resetv[XLEN - 1:1], 1'b0};
		pcgen_if.jmp_ff <= 0;
	end
`ifdef DEBUG_PCGEN
	$display("PG: pc=%x r=%d jmp=%d.%d.%d bcc=%d",
		pcgen_if.pc, pcgen_if.ready,
		pcgen_if.jmp, pcgen_if.jmp_ff, pcgen_if.jmp_out, pcgen_if.bcc);
`endif
end
endmodule
