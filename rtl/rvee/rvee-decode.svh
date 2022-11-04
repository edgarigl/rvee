`ifndef __RVEE_DECODE_SVH__
`define __RVEE_DECODE_SVH__
`include "rvee/rvee-config.svh"

`define DECODED_INSN_MEMBERS		\
	logic [XLEN - 1:0] pc;		\
	logic [4:0] rd;			\
	logic rd_we;			\
	logic [2:0] op;			\
	logic [XLEN - 1:0] a;		\
	logic [XLEN - 1:0] b;		\
	logic msb_xor;			\
	logic c;			\
	logic sra;			\
	logic mem_load;			\
	logic mem_store;		\
	logic [1:0] mem_size;		\
	logic mem_sext;			\
	logic jmp;			\
	logic [XLEN - 1:0] jmp_base;	\
	logic [XLEN - 1:0] jmp_offset;	\
	logic bcc;			\
	logic bcc_n;			\
	logic ecall;			\
	logic ebreak;			\
	logic hazard

package rvee_decode_pkg;
	localparam XLEN=`XLEN;
        typedef struct packed {
		`DECODED_INSN_MEMBERS;
        } decoded_insn_t;
endpackage

interface rvee_decode_if #(parameter XLEN=32) (
	input clk,
	input rst);

	// Unfortunately yosys doesn't support structures in interfaces.
	//	rvee_decode_pkg::decoded_insn_t dec;
	`DECODED_INSN_MEMBERS;

	logic valid;
	logic ready;
	wire	idle = !valid || ready;
	wire	done = valid && ready;

	modport decode_port(
		input	idle, done,
		input	ready,
		output	valid, pc, rd_we, rd, op, a, b, msb_xor, c, sra,
			mem_load, mem_store, mem_size, mem_sext,
			jmp, jmp_base, jmp_offset, bcc, bcc_n, 
			ecall, ebreak
			);

	modport exec_port(
		input	idle, done,
		output	ready,
		input	valid, pc, rd_we, rd, op, a, b, msb_xor, c, sra,
			mem_load, mem_store, mem_size, mem_sext,
			jmp, jmp_base, jmp_offset, bcc, bcc_n,
			ecall, ebreak
			);
endinterface
`endif
