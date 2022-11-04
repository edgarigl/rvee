`ifndef __RVEE_FETCH_SVH__
`define __RVEE_FETCH_SVH__

interface rvee_fetch_if #(parameter XLEN=32) (
	input clk,
	input rst);

	logic	[XLEN - 1:0] pc;	// PC of submitted IW (REMOVE).
	logic	[31:0] iw;		// Instruction word.
	logic	valid, ready;
	logic	flush;			// Combinational to indicate that we're flushing.

	/* Yosys doesn't support interface functions.  */
	wire	idle = !valid || ready;
	wire	done = valid && ready;

	modport fetch_port(
		input	idle, done,
		input	ready,
		output	valid, iw, pc, flush);

	modport decode_port(
		input	idle, done,
		output	ready,
		input	valid, iw, pc, flush);
endinterface
`endif
