`ifndef __RVEE_PCGEN_SVH__
`define __RVEE_PCGEN_SVH__

interface rvee_pcgen_if #(parameter XLEN=32) (
	input clk,
	input rst);

	logic	valid;
	logic	ready_ff;
	logic	ready;
	logic	[XLEN - 1:0] pc;
	logic	[XLEN - 1:0] pc_ff;

	logic	jmp;
	logic	jmp_ff;
	logic	jmp_out;
	logic	bcc; // Combinational, delayed with one cycle.
	logic	[XLEN - 1:0] jmp_base;
	logic	[XLEN - 1:0] jmp_offset;

	modport fetch_port(input valid, pc, pc_ff, jmp, jmp_ff, jmp_out,
				output ready_ff, ready);
	modport decode_port(input jmp, jmp_ff, jmp_out, bcc);
	modport pcgen_port(input ready_ff, ready, jmp, bcc, jmp_base, jmp_offset,
			   output valid, pc, pc_ff, jmp_ff, jmp_out);
	modport exec_port(output jmp, bcc, jmp_base, jmp_offset);
endinterface
`endif
