`ifndef __RVEE_MEM_SVH__
`define __RVEE_MEM_SVH__

interface rvee_mem_if #(parameter XLEN=32) (
	input clk,
	input rst);

	logic	[4:0] rd;
	logic	rd_we;
	logic	[XLEN - 1:0] rd_data;

	logic	exception;
	logic	[XLEN - 1:0] fault_pc;
	logic	[XLEN - 1:0] fault_addr;
	logic	[XLEN - 2:0] n_cause;

	modport mem_port(output	rd, rd_we, rd_data,
			 output exception, fault_pc, fault_addr, n_cause);
	modport wb_port(input rd, rd_we, rd_data);
	modport decode_port(input exception, fault_pc, fault_addr, n_cause);
	modport exec_port(input exception);
endinterface
`endif
