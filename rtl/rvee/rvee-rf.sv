/*
 * RVee register file.
 *
 * Copyright (C) 2022 Edgar E. Iglesias.
 * Written by Edgar E. Iglesias <edgar.iglesias@gmail.com>
 *
 * SPDX-License-Identifier: MIT
 */

/* verilator lint_off DECLFILENAME */
`include "rvee/rvee-config.svh"
`include "rvee/rvee-rf.svh"

//`define DEBUG_RF
module rvee_rf_ff #(parameter XLEN=32, N_REGS=32) (
	input clk,
	input rst,
	rvee_rf_if.rf_port rf_if);

	logic [XLEN - 1:0] R [N_REGS];

`define REGFW(valid, rd, rd_data, rs, rs_data)	\
	if (valid && rd == rs) begin		\
		rs_data = rd_data;		\
	end

always_comb begin
	rf_if.rs1_data = R[rf_if.rs1];
	rf_if.rs2_data = R[rf_if.rs2];

	// Register forwarding
	`REGFW(rf_if.wb_we, rf_if.wb_rd, rf_if.wb_data, rf_if.rs1, rf_if.rs1_data);
	`REGFW(rf_if.wb_we, rf_if.wb_rd, rf_if.wb_data, rf_if.rs2, rf_if.rs2_data);

	if (`RVEE_CONFIG_MEM_REGFW) begin
		`REGFW(rf_if.mem_we, rf_if.mem_rd, rf_if.mem_data, rf_if.rs1, rf_if.rs1_data);
		`REGFW(rf_if.mem_we, rf_if.mem_rd, rf_if.mem_data, rf_if.rs2, rf_if.rs2_data);
	end

	// Register x0.
	`REGFW(1, 0, 0, rf_if.rs1, rf_if.rs1_data);
	`REGFW(1, 0, 0, rf_if.rs2, rf_if.rs2_data);
end

always_ff @(posedge clk) begin
`ifdef DEBUG_RF
	$display("RF: R[%d]=%x R[%d]=%x wb-v%d-r%d-%x mem-v%d-r%d-%x",
		rf_if.rs1, R[rf_if.rs1],
		rf_if.rs2, R[rf_if.rs2],
		rf_if.wb_we, rf_if.wb_rd, rf_if.wb_data,
		rf_if.mem_we, rf_if.mem_rd, rf_if.mem_data);
`endif
	if (rf_if.wb_we) begin
		R[rf_if.wb_rd] <= rf_if.wb_data;
	end
end
endmodule
