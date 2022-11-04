`include "rvee/rvee-config.svh"
`include "rvee/rvee-decode.svh"
`include "rvee/rvee-exec.svh"
`include "rvee/rvee-rf.svh"

module rvee_exec_tb #(parameter AWIDTH=32, DWIDTH=32, XLEN=32) (
	input	clk,
	input	rst,

	input	eip, sip, tip,

	input	d_valid,
	output	d_ready,
	input	[XLEN - 1:0] d_pc,
	input	d_rd_we,
	input	[4:0] d_rd,
	input	[2:0] d_op,
	input	[XLEN - 1:0] d_a,
	input	[XLEN - 1:0] d_b,
	input	d_msb_xor,
	input	d_c,
	input	d_sra,
	input	d_mem_load,
	input	d_mem_store,
	input	[1:0] d_mem_size,
	input	d_mem_sext,
	input	d_jmp,
	input	[XLEN - 1:0] d_jmp_base,
	input	[XLEN - 1:0] d_jmp_offset,
	input	d_bcc, d_bcc_n,

	output	p_jmp,
	output	p_jmp_ff,
	output	p_jmp_out,
	output	[XLEN - 1:0] p_jmp_base,
	output	[XLEN - 1:0] p_jmp_offset,
	output	[XLEN - 1:0] p_pc,

	output	e_valid,
	input	e_ready,
	output	[XLEN - 1:0] e_pc,
	output	e_rd_we,
	output	[4:0] e_rd,
	output	[XLEN - 1:0] e_result,
	output	e_mem_load,
	output	e_mem_store,
	output	[XLEN - 1:0] e_mem_data,
	output	[1:0] e_mem_size,
	output	e_mem_sext);

	wire	[XLEN - 1:0] resetv = 0;

	rvee_decode_if decode_if(.*);
	rvee_pcgen_if pcgen_if(.*);
	rvee_exec_if exec_if(.*);
	rvee_mem_if mem_if(.*);
	rvee_rf_if rf_if(.*);

	rvee_pcgen pcgen(.*);
	rvee_exec exec(.*);

	// Connect the interface to the outside world.
	assign	decode_if.valid = d_valid;
	assign	d_ready = decode_if.ready;
	assign	decode_if.pc = d_pc;
	assign	decode_if.rd_we = d_rd_we;
	assign	decode_if.rd = d_rd;
	assign	decode_if.op = d_op;
	assign	decode_if.a = d_a;
	assign	decode_if.b = d_b;
	assign	decode_if.c = d_c;
	assign	decode_if.msb_xor = d_msb_xor;
	assign	decode_if.sra = d_sra;
	assign	decode_if.mem_load = d_mem_load;
	assign	decode_if.mem_store = d_mem_store;
	assign	decode_if.mem_size = d_mem_size;
	assign	decode_if.mem_sext = d_mem_sext;
	assign	decode_if.jmp = d_jmp;
	assign	decode_if.jmp_base = d_jmp_base;
	assign	decode_if.jmp_offset = d_jmp_offset;
	assign	decode_if.bcc = d_bcc;
	assign	decode_if.bcc_n = d_bcc_n;

	assign	p_jmp = pcgen_if.jmp;
	assign	p_jmp_ff = pcgen_if.jmp_ff;
	assign	p_jmp_out = pcgen_if.jmp_out;
	assign	p_jmp_base = pcgen_if.jmp_base;
	assign	p_jmp_offset = pcgen_if.jmp_offset;
	assign	p_pc = pcgen_if.pc;

	assign	e_valid = exec_if.valid;
	assign	exec_if.ready = e_ready;
	assign	e_pc = exec_if.pc;
	assign	e_rd_we = exec_if.rd_we;
	assign	e_rd = exec_if.rd;
	assign	e_result = exec_if.result;
	assign	e_mem_load = exec_if.mem_load;
	assign	e_mem_store = exec_if.mem_store;
	assign	e_mem_data = exec_if.mem_data;
	assign	e_mem_size = exec_if.mem_size;
	assign	e_mem_sext = exec_if.mem_sext;
endmodule
