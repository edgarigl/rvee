/*
 * RVee Control/Status register file.
 *
 * Copyright (C) 2022 Edgar E. Iglesias.
 * Written by Edgar E. Iglesias <edgar.iglesias@gmail.com>
 *
 * SPDX-License-Identifier: MIT
 */

/* verilator lint_off DECLFILENAME */
`include "rvee/rvee-config.svh"
`include "rvee/rvee-csr-regs.vh"
`include "rvee/rvee-csr.svh"

`define CSR_OP_RW	2'b01
`define CSR_OP_RS	2'b10
`define CSR_OP_RC	2'b11

module rvee_csr #(parameter XLEN=32, N_REGS=32) (
	input clk,
	input rst,
	rvee_csr_if.csr_port csr_if);

`ifdef RVEE_ZICSR
	logic [XLEN - 1:0] r;
	logic [XLEN - 1:0] wdata;
	integer csr_reg = csr_if.csr_reg;
	integer op = csr_if.op;

always_comb begin
	r = 0;
	wdata = 0;
	csr_if.illegal = 0;

	// Only read if CSR enable and non-zero rs1/uimm.
	if (csr_if.r_en) begin
		case(csr_reg)
		`CSR_MSTATUS: begin
			r[3] = csr_if.mie;
		end
		`CSR_MISA: begin
			r[XLEN - 1:XLEN - 2] = XLEN == 32 ? 2'b01 : 2'b10;
			r[8] = 1'b1;
		end
		`CSR_MIE: begin
			r[3] = csr_if.msie;
			r[7] = csr_if.mtie;
			r[11] = csr_if.mtie;
		end
		`CSR_MTVEC: r = csr_if.mtvec;
		`CSR_MSCRATCH: r = csr_if.mscratch;
		`CSR_MEPC: r = csr_if.mepc;
		`CSR_MCAUSE: r = csr_if.mcause;
		`CSR_MTVAL: r = csr_if.mtval;
		default: r = 0;
		endcase

`ifdef DEBUG_CSR
		$display("CSR: pc %x read csr[%x]=%x", csr_if.pc, csr_if.csr_reg, r);
`endif
	end
	csr_if.rdata = r;

	// Now compute wdata
	case (op)
	`CSR_OP_RS: wdata = r | csr_if.wdata;
	`CSR_OP_RC: wdata = r & (~csr_if.wdata);
	default: wdata = csr_if.wdata;
	endcase

	// permission checks
	if (csr_if.csr_reg[9:8] < csr_if.mode) begin
		csr_if.illegal = 1;
	end
	if (csr_if.csr_reg[11:10] == 2'b11 && csr_if.w_en) begin
		csr_if.illegal = 1;
	end
end

always_ff @(posedge clk) begin
	// do writes based on OP.
	if (csr_if.w_en && !csr_if.illegal) begin
		case (csr_if.csr_reg)
		`CSR_MSTATUS: begin
			csr_if.mie <= wdata[3];
		end
		`CSR_MIE: begin
			csr_if.msie <= wdata[3];
			csr_if.mtie <= wdata[7];
			csr_if.mtie <= wdata[11];
		end
		`CSR_MTVEC: csr_if.mtvec <= {wdata[XLEN - 1:2], 2'b0};
		`CSR_MSCRATCH: csr_if.mscratch <= wdata;
		`CSR_MEPC: csr_if.mepc <= wdata;
		`CSR_MCAUSE: csr_if.mcause <= wdata;
		`CSR_MTVAL: csr_if.mtval <= wdata;
		default: begin end
		endcase
`ifdef DEBUG_CSR
		$display("CSR: pc %x write %x <= %x", csr_if.pc, csr_if.csr_reg, wdata);
`endif
	end

	if (csr_if.exception) begin
		csr_if.mepc <= csr_if.pc;
		csr_if.mcause <= {csr_if.irq, csr_if.n_cause};
		csr_if.mpie <= csr_if.mie;
		csr_if.mie <= 0;
	end

	if (csr_if.we_tval) begin
		csr_if.mtval <= csr_if.n_tval;
	end
	if (rst) begin
		csr_if.mode <= `RV_MACHINE_MODE;

		csr_if.mie <= 0;
		csr_if.sie <= 0;
	end
end
`endif
endmodule
