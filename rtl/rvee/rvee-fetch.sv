/*
 * RVee fetch unit.
 *
 * Issues up to 2 multiple outstanding transactions.
 *
 * Copyright (C) 2022 Edgar E. Iglesias.
 * Written by Edgar E. Iglesias <edgar.iglesias@gmail.com>
 *
 * SPDX-License-Identifier: MIT
 */

/* verilator lint_off DECLFILENAME */
`include "include/axi.svh"
`include "rvee/rvee-config.svh"
`include "rvee/rvee-pcgen.svh"
`include "rvee/rvee-fetch.svh"

module rvee_fetch #(parameter XLEN=32, AWIDTH=32, DWIDTH=32) (
	input clk,
	input rst,
	axi4lite_if.master_port axi_fetch_if,
	rvee_pcgen_if.fetch_port pcgen_if,
	rvee_fetch_if.fetch_port fetch_if);

	/* Since the fetcher never writes we can tie these off.  */
	assign	axi_fetch_if.awvalid = 0;
	assign	axi_fetch_if.awaddr = 0;
	assign	axi_fetch_if.awprot = 0;
	assign	axi_fetch_if.wvalid = 0;
	assign	axi_fetch_if.wdata = 0;
	assign	axi_fetch_if.wstrb = 0; 
	assign	axi_fetch_if.bready = 1;
	assign	axi_fetch_if.arprot = 0;

	typedef struct packed {
		logic v;
		logic [XLEN - 1:0] pc;
	} fetch_slot_t;

	fetch_slot_t fs_ff[2];
	fetch_slot_t fs[2];

	// Shift-reg used to drop instructions after jumps.
	logic	[1:0] flush_ff;
	logic	[1:0] flush;

	// issue_ar is true when we can issue a new fetch onto the AR-channel.
	wire	issue_ar = pcgen_if.valid && axi_fetch_if.aridle && (!fs_ff[1].v || (axi_fetch_if.rdone));
	assign	pcgen_if.ready = issue_ar;
	assign	fetch_if.flush = flush[0] | flush_ff[0];
	assign	axi_fetch_if.rready = fetch_if.idle;

	integer i;
always_comb begin
	for (i = 0; i < 2; i++) begin
		fs[i].v = fs_ff[i].v;
		fs[i].pc = fs_ff[i].pc;
	end
	flush = flush_ff;

	// R-channel is done, shift out.
	if (axi_fetch_if.rdone) begin
		fs[0].v = fs[1].v;
		fs[0].pc = fs[1].pc;
		fs[1].v = 0;
	end

	// If we're ready to issue a new transaction, shift one in.
	if (issue_ar) begin
		if (!fs[0].v) begin
			fs[0].v = 1;
		end else begin
			fs[1].v = 1;
		end
	end

	/*
	 * This is really:
	if (issue_ar) begin
		if (!fs[0].v]) begin
			fs[0].pc = pcgen_if.pc;
		end else begin
			fs[1].pc = pcgen_if.pc;
		end
	end

	* But since pc doesn't matter if .v is 0, we can flatten it out a little.
	* The following optimizes the path for FPGA's.
	*/
	if (!fs[0].v) begin
		fs[0].pc = pcgen_if.pc;
	end
	if (issue_ar) begin
		fs[1].pc = pcgen_if.pc;
	end

	// Flush logic.
	if (axi_fetch_if.rdone) begin
		flush = flush_ff >> 1;
	end
	if (pcgen_if.jmp_out) begin
		// The fetch stage is responsible for dropping any fetched insns
		// that have not yet validly been presented to the decoder.
		//
		// That means {fs[1].v, fs[0].v}
		// But since fs[1].v & issue_ar means fs[1] now holds the
		// current issue, i.e the jmp, we must not flush if issue_ar
		// is set.
		flush = {fs[1].v & !issue_ar, fs[0].v};
	end
end

	logic n_arvalid;
	logic [XLEN - 1:0] n_araddr;
always_comb begin
	n_arvalid = axi_fetch_if.arvalid;
	n_araddr = axi_fetch_if.araddr;
	if (issue_ar) begin
		n_arvalid = 1;
		n_araddr = pcgen_if.pc;
	end else if (axi_fetch_if.ardone) begin
		n_arvalid = 0;
	end
end

always_ff @(posedge clk) begin
	pcgen_if.ready_ff <= pcgen_if.ready;
	fs_ff[0].v <= fs[0].v;
	fs_ff[1].v <= fs[1].v;
	fs_ff[0].pc <= fs[0].pc;
	fs_ff[1].pc <= fs[1].pc;
	flush_ff <= flush;

	axi_fetch_if.arvalid <= n_arvalid;
	axi_fetch_if.araddr <= n_araddr;

	if (axi_fetch_if.rdone) begin
		fetch_if.valid <= !(flush[0] | flush_ff[0]);
		fetch_if.iw <= axi_fetch_if.rdata;
		fetch_if.pc <= fs_ff[0].pc;
	end else if (fetch_if.done) begin
		fetch_if.valid <= 0;
	end

	if (rst) begin
		axi_fetch_if.arvalid <= 0;
		fs_ff[0].v <= 0;
		fs_ff[1].v <= 0;
		fs_ff[0].pc <= {XLEN{1'bx}};
		fs_ff[1].pc <= {XLEN{1'bx}};

		fetch_if.valid <= 0;
		fetch_if.iw <= 0;
		fetch_if.pc <= 0;

		pcgen_if.ready_ff <= 0;
		flush_ff <= 0;
	end
`ifdef DEBUG_FETCH
	$display("FT:  fs-pc0-%x-v%d-pc1-%x-v%d npc=%x.%x pcgen=%x-r%d-j%d.%d ft-%x-v%d-r%d-i%d ar-v%d-r%d-%x r-v%d-r%d issue_ar=%d flush=%b.%b RST=%d",
		fs_ff[0].pc, fs_ff[0].v, fs_ff[1].pc, fs_ff[1].v, fs[0].pc,
		fs[1].pc, pcgen_if.pc, pcgen_if.ready,
		pcgen_if.jmp_ff, pcgen_if.jmp,
		fetch_if.pc, fetch_if.valid, fetch_if.ready, fetch_if.idle,
		axi_fetch_if.arvalid, axi_fetch_if.arready, axi_fetch_if.araddr,
		axi_fetch_if.rvalid, axi_fetch_if.rready,
		issue_ar, flush_ff, flush, rst);

	if (issue_ar) begin
		$display("FT: issue_ar pc %x rst=%d", pcgen_if.pc, rst);
	end
	if (axi_fetch_if.rdone) begin
		$display("FT: rdone: fetched pc %x flush=%d",
			fs_ff[0].pc, flush[0] | flush_ff[0]);
	end
`endif
`ifdef DEBUG_FETCH_JMP
	if (pcgen_if.jmp_out) begin
		// We need to flush 
		$display("FT: JMP to %x flush=%b.%b", pcgen_if.pc, flush_ff, flush);
	end
`endif
end
endmodule
