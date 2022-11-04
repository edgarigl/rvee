`default_nettype none
`include "rvee/rvee-config.svh"
`include "rvee/rvee-fetch.svh"
`include "rvee/rvee-decode.svh"
`include "rvee/rvee-exec.svh"
`include "rvee/rvee-mem.svh"
`include "rvee/rvee-csr.svh"

module rvee_decode_tb #(parameter AWIDTH=32, DWIDTH=32, XLEN=32) (
	input	clk,
	input	rst,

	input	f_valid,
	output	f_ready,
	input	[31:0] f_iw,
	input	[XLEN - 1:0] f_pc,

	input	meip, msip, mtip,
	input	seip, ssip, stip,

	output	d_valid,
	input	d_ready,
	output	[XLEN - 1:0] d_pc,
	output	d_rd_we,
	output	[4:0] d_rd,
	output	[2:0] d_op,
	output	[XLEN - 1:0] d_a,
	output	[XLEN - 1:0] d_b,
	output	d_c,
	output	d_sra,
	output	d_mem_load,
	output	d_mem_store,
	output	[1:0] d_mem_size,
	output	d_mem_sext,
	output	d_jmp,
	output	[XLEN - 1:0] d_jmp_base,
	output	[XLEN - 1:0] d_jmp_offset,
	output	d_bcc,
	output	d_bcc_n
	);

	rvee_rf_if rf_if(.*);
	rvee_pcgen_if pcgen_if(.*);
	rvee_fetch_if fetch_if(.*);
	rvee_decode_if decode_if(.*);
	rvee_exec_if exec_if(.*);
	rvee_mem_if mem_if(.*);
	rvee_csr_if csr_if(.*);

	rvee_csr csr(.*);
	rvee_rf_ff rf(.*);
	rvee_decode decode(.*);

	assign	rf_if.wb_we = 0;
	assign	rf_if.wb_rd = 0;
	assign	rf_if.wb_data = 0;

	// Connect the interface to the outside world.
	assign	fetch_if.valid = f_valid;
	assign	f_ready = fetch_if.ready;
	assign	fetch_if.iw = f_iw;
	assign	fetch_if.pc = f_pc;

	assign	d_valid = decode_if.valid;
	assign	decode_if.ready = d_ready;
	assign	d_pc = decode_if.pc;
	assign	d_rd_we = decode_if.rd_we;
	assign	d_rd = decode_if.rd;
	assign	d_op = decode_if.op;
	assign	d_a = decode_if.a;
	assign	d_b = decode_if.b;
	assign	d_c = decode_if.c;
	assign	d_sra = decode_if.sra;
	assign	d_mem_load = decode_if.mem_load;
	assign	d_mem_store = decode_if.mem_store;
	assign	d_mem_size = decode_if.mem_size;
	assign	d_mem_sext = decode_if.mem_sext;
	assign	d_jmp = decode_if.jmp;
	assign	d_jmp_base = decode_if.jmp_base;
	assign	d_jmp_offset = decode_if.jmp_offset;
	assign	d_bcc = decode_if.bcc;
	assign	d_bcc_n = decode_if.bcc_n;
endmodule
