`ifndef __RVEE_EXEC_SVH__
`define __RVEE_EXEC_SVH__

interface rvee_exec_if #(parameter XLEN=32) (
	input clk,
	input rst);

	logic	valid, ready;
	logic	[XLEN - 1:0] pc;
	logic	rd_we;
	logic	[4:0] rd;
	logic	[XLEN - 1:0] result; 
	logic	mem_load;
	logic	mem_store;
	logic	[XLEN - 1:0] mem_data;
	logic	[1:0] mem_size;
	logic	mem_sext;

	wire	idle = !valid || ready;
	wire	done = valid && ready;

	modport decode_port(
		input	idle, done,
		input	ready, 
		input	valid, pc, rd_we, rd, result,
			mem_load, mem_store, mem_data, mem_size, mem_sext);

	modport exec_port(
		input	idle, done,
		input	ready, 
		output	valid, pc, rd_we, rd, result,
			mem_load, mem_store, mem_data, mem_size, mem_sext);

	modport mem_port(
		input	idle, done,
		output	ready,
		input	valid, pc, rd_we, rd, result,
			mem_load, mem_store, mem_data, mem_size, mem_sext);
endinterface
`endif
