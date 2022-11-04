/*
 * RVee decode unit.
 *
 * Copyright (C) 2022 Edgar E. Iglesias.
 * Written by Edgar E. Iglesias <edgar.iglesias@gmail.com>
 *
 * SPDX-License-Identifier: MIT
 */

/* verilator lint_off DECLFILENAME */
`include "rvee/rvee-config.svh"
`include "rvee/rvee-fetch.svh"
`include "rvee/rvee-decode.svh"
`include "rvee/rvee-exec.svh"
`include "rvee/rvee-mem.svh"
`include "rvee/rvee-pcgen.svh"
`include "rvee/rvee-csr-regs.vh"
`include "rvee/rvee-csr.svh"
`include "rvee/rvee-rf.svh"
`include "rvee/rvee-alu.svh"

`include "rvee/rvee-insn.svh"

module rvee_decode #(parameter XLEN=32) (
	input clk,
	input rst,
	rvee_rf_if.decode_port rf_if,
	rvee_pcgen_if.decode_port pcgen_if,
	rvee_fetch_if.decode_port fetch_if,
	rvee_exec_if.decode_port exec_if,
	rvee_mem_if.decode_port mem_if,
	rvee_csr_if.decode_port csr_if,
	rvee_decode_if.decode_port decode_if);

	wire flush_jmp = pcgen_if.jmp || pcgen_if.jmp_out;
	logic flush;
	logic flush_ff;

	wire	[XLEN - 1:0] iw = fetch_if.iw;
	wire	[XLEN - 1:0] pc = fetch_if.pc;
	rvee_decode_pkg::decoded_insn_t dec;
	logic [19:0] sign_ext;

	insn_t insn;
	assign insn = iw;

	always_comb begin
		rf_if.rs1 = insn.r.rs1;
		rf_if.rs2 = insn.r.rs2;

		dec.hazard = 0;
		dec.rd = insn.r.rd;
		sign_ext = {20{iw[31]}};

		// Defaults
		dec.rd_we = 0;
		dec.op = 3'dx;
		dec.a = 'dx;
		dec.b = 'dx;
		dec.c = 0;
		dec.sra = 1'bx;

		dec.mem_load = 0;
		dec.mem_store = 0;
		dec.mem_size = insn.i.funct3[1:0];
		dec.mem_sext = !insn.i.funct3[2];

		dec.jmp = 0;
		dec.jmp_base = 32'bx;
		dec.jmp_offset = 32'bx;
		dec.bcc = 0;
		dec.bcc_n = 1'bx;
		dec.ecall = 0;
		dec.ebreak = 0;
		dec.msb_xor = 0;
`ifdef RVEE_ZICSR
		csr_if.pc = pc;
		csr_if.exception = 0;
		csr_if.irq = 0;
		csr_if.n_cause = 0;
		csr_if.r_en = 0;
		csr_if.w_en = 0;
		csr_if.op = insn.i.funct3[1:0];
		csr_if.csr_reg = 0;
		csr_if.wdata = 0;

		csr_if.we_tval = 0;
		csr_if.n_tval = 0;
`endif
		case (insn.r.opcode)
		7'b0110111,
		7'b0010111: begin
			/* LUI/AUIPC  */
			dec.op = `ALU_ADD;
			dec.a = iw[5] ? 0 : pc;
			dec.b = {insn.u.imm, 12'b0};
			dec.msb_xor = dec.b[XLEN - 1];
			dec.rd_we = 1;
		end
		7'b1101111: begin
			/* JAL  */
			dec.op = `ALU_ADD;
			dec.a = pc;
			dec.b = 4;
			dec.rd_we = 1;
			dec.jmp = 1;
			dec.jmp_base = pc;
			/* Frankenstein immediate.  */
			dec.jmp_offset = {sign_ext[10:0], insn.j.imm4, insn.j.imm3,
						insn.j.imm2, insn.j.imm, 1'b0};
		end
		7'b1100011: begin
			/* BCC Conditional branches.  */
			dec.op = {1'b0, insn.b.funct3[2:1]};
			dec.a = rf_if.rs1_data;
			dec.b = ~rf_if.rs2_data;
			dec.msb_xor = rf_if.rs2_data[XLEN - 1];
			dec.c = 1;
			dec.bcc = 1;
			// FIXME: The RISCV encoding seems suboptimal here.
			dec.bcc_n = insn.b.funct3[0] ^ insn.b.funct3[2];
			dec.jmp_base = pc;
			dec.jmp_offset = {sign_ext[18:0], insn.b.imm4, insn.b.imm3,
						insn.b.imm2, insn.b.imm, 1'b0};
		end
		7'b0100011: begin
			/* Stores always do additions through the ALU.  */
			dec.op = `ALU_ADD;
			dec.a = rf_if.rs1_data;
			dec.b = {sign_ext, insn.s.imm2, insn.s.imm};
			dec.msb_xor = dec.b[XLEN - 1];
			dec.mem_store = 1;
			// Hax, we carry the store data in jmp_base.
			dec.jmp_base = rf_if.rs2_data;
		end
		7'b1100111, /* JALR.  */
		7'b0000011, /* Load.  */
		7'b0010011: begin /* I ALU.  */
			/* Loads always do additions through the ALU.  */
			dec.op = iw[4] ? insn.i.funct3 : `ALU_ADD;
			dec.a = rf_if.rs1_data;
			dec.b = {sign_ext, insn.i.imm};
			dec.sra = iw[30];

			dec.mem_load = ~iw[4] & ~iw[2];
			dec.rd_we = !dec.mem_load;
			dec.jmp = iw[2];
			dec.jmp_base = rf_if.rs1_data;
			dec.jmp_offset = {sign_ext, insn.i.imm};
			if (dec.jmp) begin
				dec.a = pc;
				dec.b = 4;
			end

			dec.msb_xor = dec.b[XLEN - 1];
			/* Prepare to subtract. op[1:0] is 01 for SLTI/SLTIU.  */
			if (dec.op[2:1] == 2'b01) begin
				dec.b = ~{sign_ext, insn.i.imm};
				dec.c = 1;
			end

		end
		/* R ALU.  */
		7'b0110011: begin
			dec.op = insn.r.funct3;
			dec.a = rf_if.rs1_data;
			dec.b = rf_if.rs2_data;
			dec.c = iw[30];
			dec.c = dec.c || dec.op[2:1] == 2'b01;
			dec.sra = iw[30];

			dec.msb_xor = dec.b[XLEN - 1];
			/* Prepare to subtract. op[1] is 1 for SRA.  */
			if (dec.c && dec.op[2] != 1'b1) begin
				dec.b = ~rf_if.rs2_data;
			end
			dec.rd_we = 1;
		end
		/* FENCE.  */
		7'b0001111: begin
		end
		/* SYSTEM.  */
		7'b1110011: begin
			case (insn.r.funct3)
			3'b000: begin
				case (insn.r.rs2)
				0: begin
					dec.ecall = 1;
				end
				1: begin
					dec.ebreak = 1;
				end
				2: begin
					case (iw[29:28])
					0: begin
					end
					1: begin
					end
					3: begin
`ifdef RVEE_ZICSR
//						$display("MRET %x", csr_if.mepc);
						dec.jmp = 1;
						dec.jmp_base = csr_if.mepc;
						dec.jmp_offset = 0;
`endif
					end
					default: begin end
					endcase
				end
				endcase
			end
			default: begin
`ifdef RVEE_ZICSR
				csr_if.r_en = insn.r.rd != 0;
				csr_if.w_en = insn.r.rs1 != 0;
				csr_if.csr_reg = iw[31:20];
				csr_if.wdata = rf_if.rs1_data;
				if (insn.r.funct3[2]) begin
					/* Immediate.  */
					csr_if.wdata = {27'b0, insn.r.rs1};
				end

				dec.op = `ALU_ADD;
				dec.a = csr_if.rdata;
				dec.b = 0;
				dec.rd_we = 1;
`endif
			end
			endcase
		end
		default: begin
			// unimp.
			if (fetch_if.valid) begin
`ifdef RVEE_ZICSR
				csr_if.exception = 1;
				csr_if.n_cause = `MCAUSE_ILLEGAL_INSN;
				$display("Illegal insn pc %x %x", fetch_if.pc, iw);
`ifndef YOSYS
				$finish;
				$finish;
`endif
`endif
			end
		end
		endcase

		// This is the original b_msb ^ a_msb. b prior to complement
		// prep for sub, that is.
		dec.msb_xor = rf_if.rs1_data[XLEN - 1] ^ dec.msb_xor;

		// Done decoding, now do hazard detection.
		if (decode_if.valid && (decode_if.rd_we || decode_if.mem_load)) begin
			if (rf_if.rs1 == decode_if.rd) begin
				dec.hazard = 1;
			end
			if (rf_if.rs2 == decode_if.rd) begin
				dec.hazard = 1;
			end
		end

		if (exec_if.valid &&
			(!`RVEE_CONFIG_MEM_REGFW || exec_if.mem_load)) begin
			if (rf_if.rs1 == exec_if.rd) begin
				dec.hazard = 1;
			end
			if (rf_if.rs2 == exec_if.rd) begin
				dec.hazard = 1;
			end
		end

		// If we're dropping this insn, clear any side-effects.
		if (dec.hazard || !fetch_if.valid) begin
			dec.jmp = 0;
`ifdef RVEE_ZICSR
			csr_if.exception = 0;
			csr_if.r_en = 0;
			csr_if.w_en = 0;
`endif
		end

		flush = flush_jmp | flush_ff;
		// Drop it after clearing side-effects to avoid surprises.
		if (flush) begin
			// Just drop this insn instead of backpressuring.
			dec.hazard = 0;
		end

`ifdef RVEE_ZICSR
		if (csr_if.irq_pending) begin
			$display("IRQ!");
			csr_if.pc = pc;
			csr_if.exception = 1;
			csr_if.irq = 1;
			csr_if.n_cause = 3;
		end

		// MEM exceptions trump everything since the insn is further
		// down the pipe and has already executed. If requested, raise
		// an exception and drop any other thing that may be going on.
		if (mem_if.exception) begin
			$display("MEM TRAP! flush=%d hazard=%d v%d-r%d",
				flush, dec.hazard, decode_if.valid, decode_if.ready);
			dec.hazard = 0;
			flush = 0;
			csr_if.pc = mem_if.fault_pc;
			csr_if.exception = 1;
			csr_if.irq = 0;
			csr_if.n_cause = mem_if.n_cause;
			csr_if.we_tval = 1;
			csr_if.n_tval = mem_if.fault_addr;
		end

		if (csr_if.exception) begin
			dec.jmp = 1;
			dec.jmp_base = {csr_if.mtvec[XLEN - 1:2], 2'b0};
			// TODO: Use jmp_offset for vectored interrupts.
			dec.jmp_offset = 0;

			// Cleanup.
			dec.hazard = 0;
			dec.rd_we = 0;
			dec.mem_load = 0;
			dec.mem_store = 0;
			$display("DEC: TRAP pc %x cause %x jmp to %x",
				csr_if.pc, csr_if.n_cause, dec.jmp_base + dec.jmp_offset);
		end
`endif
		fetch_if.ready = decode_if.idle && !dec.hazard;
	end

	always_ff @(posedge clk) begin
		flush_ff <= flush_jmp && !fetch_if.valid;

		if (decode_if.done) begin
			decode_if.valid <= 0;

			// To speed up the jmp paths, they don't check for valid
			decode_if.jmp <= 0;
			decode_if.bcc <= 0;
			decode_if.bcc_n <= 0;
		end

		if ((fetch_if.valid || csr_if.exception) && decode_if.idle) begin
`ifdef DEBUG_DECODE
		$display("DEC:  pc %x iw=%x fetch-v%d-r%d dec-v%d-r%d-h%d-f%d pcgen-j%d.%d-jout%d r%d=%x r%d=%x",
			fetch_if.pc, fetch_if.iw,
			fetch_if.valid, fetch_if.ready,
			decode_if.valid, decode_if.ready,
			dec.hazard, flush, pcgen_if.jmp_ff, pcgen_if.jmp, pcgen_if.jmp_out,
			rf_if.rs1, rf_if.rs1_data, rf_if.rs2, rf_if.rs2_data);
`endif
			decode_if.valid <= !dec.hazard && !flush;
			decode_if.pc <= fetch_if.pc;
			decode_if.rd_we <= dec.rd_we;
			decode_if.rd <= dec.rd;
			decode_if.op <= dec.op;
			decode_if.a <= dec.a;
			decode_if.b <= dec.b;
			decode_if.msb_xor <= dec.msb_xor;
			decode_if.c <= dec.c;
			decode_if.sra <= dec.sra;

			decode_if.mem_load <= dec.mem_load;
			decode_if.mem_store <= dec.mem_store;
			decode_if.mem_size <= dec.mem_size;
			decode_if.mem_sext <= dec.mem_sext;

			decode_if.jmp <= dec.jmp & !flush;
			decode_if.jmp_base <= dec.jmp_base;
			decode_if.jmp_offset <= dec.jmp_offset;
			decode_if.bcc <= dec.bcc;
			decode_if.bcc_n <= dec.bcc_n;

			decode_if.ecall <= dec.ecall;
		end

		if (rst) begin
			decode_if.valid <= 0;
			decode_if.jmp <= 0;
			decode_if.bcc <= 0;
			decode_if.bcc_n <= 0;
		end
	end
endmodule
