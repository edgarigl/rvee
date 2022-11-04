`ifndef __RVEE_RF_SVH__
`define __RVEE_RF_SVH__

interface rvee_rf_if #(parameter N_REGS=32, XLEN=32) (
	input clk,
	input rst);

	logic	[$clog2(N_REGS) - 1: 0] rs1;
	logic	[$clog2(N_REGS) - 1: 0] rs2;

	logic	[XLEN - 1:0] rs1_data;
	logic	[XLEN - 1:0] rs2_data;

	logic	wb_we;
	logic	[$clog2(N_REGS) - 1: 0] wb_rd;
	logic	[XLEN - 1:0] wb_data;

	logic	mem_we;
	logic	[$clog2(N_REGS) - 1: 0] mem_rd;
	logic	[XLEN - 1:0] mem_data;

	modport rf_port(input rs1, rs2,
			input wb_we, wb_rd, wb_data,
			input mem_we, mem_rd, mem_data,
			output rs1_data, rs2_data);
	modport decode_port(input rs1_data, rs2_data, output rs1, rs2);
	modport exec_port(output mem_we, mem_rd, mem_data);
	modport mem_port(output wb_we, wb_rd, wb_data);
endinterface
`endif
