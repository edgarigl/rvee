/*
 * RVee execute unit.
 *
 * Copyright (C) 2022 Edgar E. Iglesias.
 * Written by Edgar E. Iglesias <edgar.iglesias@gmail.com>
 *
 * SPDX-License-Identifier: MIT
 */

/* verilator lint_off DECLFILENAME */
`include "rvee/rvee-decode.svh"
`include "rvee/rvee-pcgen.svh"
`include "rvee/rvee-exec.svh"
`include "rvee/rvee-mem.svh"
`include "rvee/rvee-alu.svh"
`include "rvee/rvee-rf.svh"

module rvee_exec #(parameter XLEN=32) (
	input clk,
	input rst,
	rvee_rf_if.exec_port rf_if,
	rvee_pcgen_if.exec_port pcgen_if,
	rvee_decode_if.exec_port decode_if,
	rvee_mem_if.exec_port mem_if,
	rvee_exec_if.exec_port exec_if);

	rvee_alu_if alu_if(clk, rst);
	rvee_alu alu(.*);

	always_comb begin
		alu_if.op = decode_if.op;
		alu_if.a = decode_if.a;
		alu_if.b = decode_if.b;
		alu_if.c = decode_if.c;
		alu_if.msb_xor = decode_if.msb_xor;
		alu_if.sra = decode_if.sra;
	end

	assign	decode_if.ready = exec_if.idle;

	// Branches and jumps.
	logic	z_dly;
	logic	bcc_ff;
	logic	bcc_n_ff;
	always_comb begin
		// Direct jumps.
		pcgen_if.jmp = decode_if.jmp & !flush;
		pcgen_if.jmp_base = decode_if.jmp_base;
		pcgen_if.jmp_offset = decode_if.jmp_offset;

		// BCCs are delayed with one cycle. PCGEN merges them with jmp.
		// Moving z computation to the EXEC stage makes things worse.
		z_dly = exec_if.result == 0;
		pcgen_if.bcc = bcc_ff ? bcc_n_ff ^ z_dly : 0;
	end

	always_comb begin
		// Register forwarding.
		rf_if.mem_we = exec_if.rd_we;
		rf_if.mem_rd = exec_if.rd;
		rf_if.mem_data = exec_if.result;
	end

	// Flush/drop this insn
	wire	flush = pcgen_if.bcc || mem_if.exception;

	always_ff @(posedge clk) begin
		bcc_ff <= 0;
		bcc_n_ff <= 0;

		if (exec_if.done) begin
			exec_if.valid <= 0;
		end

		if (decode_if.valid && exec_if.idle) begin
			exec_if.valid <= !flush;
			exec_if.pc <= decode_if.pc;
			exec_if.rd_we <= decode_if.rd_we & !flush;
			exec_if.rd <= decode_if.rd;
			exec_if.result <= alu_if.d;
			exec_if.mem_data <= decode_if.jmp_base;

			exec_if.mem_load <= decode_if.mem_load;
			exec_if.mem_store <= decode_if.mem_store;
			exec_if.mem_size <= decode_if.mem_size;
			exec_if.mem_sext <= decode_if.mem_sext;

			bcc_ff <= decode_if.bcc & !flush;
			bcc_n_ff <= decode_if.bcc_n;
`ifdef SIM_ECALL
			if (decode_if.ecall) begin
				$display("ecall pc %x %x %x", decode_if.pc, decode_if.a, decode_if.b);
				$finish();
				$finish();
			end
`endif
		end

		if (rst) begin
			exec_if.valid <= 0;
			exec_if.rd_we <= 0;
		end
`ifdef DEBUG_EXEC
		$display("\nEXEC: pc %x op=%x sra=%d dec-v%d-r%d-j%d-bcc%d exe-v%d-r%d a=%x b=%x c=%d d=%x jb/sd=%x pcgen_if.bcc=%d flush=%d",
			decode_if.pc, decode_if.op, decode_if.sra,
			decode_if.valid, decode_if.ready, decode_if.jmp, decode_if.bcc,
			exec_if.valid, exec_if.ready,
			alu_if.a, alu_if.b, alu_if.c, alu_if.d,
			decode_if.jmp_base, pcgen_if.bcc, flush);
			if (decode_if.jmp) begin
				$display("EXE: jmp=%d.%d %x (%x + %x)",
					decode_if.jmp, pcgen_if.jmp,
					decode_if.jmp_base + decode_if.jmp_offset,
					decode_if.jmp_base, decode_if.jmp_offset);
			end
`endif
	end
endmodule
