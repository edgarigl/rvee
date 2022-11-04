/*
 * Core Local INTerruptor (CLINT)
 *
 * Copyright (C) 2022 Edgar E. Iglesias.
 * Written by Edgar E. Iglesias <edgar.iglesias@gmail.com>
 *
 * SPDX-License-Identifier: MIT
 */

`include "include/axi.svh"

/*
Address		Width	Attr.	Description		Notes
0x0200_0000	4B	RW	msip for hart 0		MSIP Registers (1 bit wide)
0x0200_4008			Reserved...
0x0200_BFF7
0x0200_4000	8B	RW	mtimecmp for hart 0	MTIMECMP Registers
0x0200_4008			Reserved...
0x0200_BFF7
0x0200_BFF8	8B	RW	mtime			Timer Register
0x0200_C000			Reserved...
*/

module clint #(AWIDTH=32, DWIDTH=32, NUM_TARGETS=1) (
	input clk,
	input rst,
	output logic [NUM_TARGETS - 1:0] target_sip,
	output logic [NUM_TARGETS - 1:0] target_tip,
	axi4lite_if.target_port axi_if);

	typedef struct packed {
		logic sip;
		logic [63:0] timecmp;
	} clint_target_t;

	clint_target_t target[NUM_TARGETS];
	clint_target_t n_target[NUM_TARGETS];

	logic [63:0] mtime;
	logic [63:0] n_mtime;

	logic [DWIDTH - 1:0] rdata;
	typedef struct packed {
		logic [1:0] v;
		logic bv;
		logic [AWIDTH - 1:0] addr;
	} trans_slot_t;

	trans_slot_t ts_r, ts_w;
	trans_slot_t n_ts_r, n_ts_w;
always_comb begin
	n_ts_r.v[0] = ts_r.v[0];
	n_ts_r.v[1] = 0;
	n_ts_r.addr = ts_r.addr;
	n_ts_w.v = ts_w.v;
	n_ts_w.addr = ts_w.addr;

	// Done?
	if (axi_if.rdone) begin
		n_ts_r.v[0] = 0;
	end
	if (axi_if.wdone) begin
		n_ts_w.v[0] = 0;
	end
	if (axi_if.bdone) begin
		n_ts_w.v[1] = 0;
	end
	if (axi_if.ardone) begin
		n_ts_r.v = 1;
		n_ts_r.addr = axi_if.araddr;
	end
	if (axi_if.awdone) begin
		n_ts_w.v = 2'b11;
		n_ts_w.addr = axi_if.awaddr;
	end
end

	integer t;
always_comb begin
	rdata = 0;
	for (t = 0; t < NUM_TARGETS; t++) begin
		n_target[t].sip = target[t].sip;
		n_target[t].timecmp = target[t].timecmp;
	end
//	n_target[0].sip = target[0].sip;
	n_mtime = mtime + 1;

	case (n_ts_r.addr[15:14])
	2'b00: begin // IPI
		for (t = 0; t < NUM_TARGETS; t++) begin
			if (n_ts_r.addr[$clog2(NUM_TARGETS) + 2:2] == t[$clog2(NUM_TARGETS):0]) begin
				rdata = {{(DWIDTH - 1){1'b0}}, target[t].sip};
			end
		end
	end
	2'b01: begin // TIMECMP
		for (t = 0; t < NUM_TARGETS; t++) begin
			if (n_ts_r.addr[$clog2(NUM_TARGETS) + 3:3] == t[$clog2(NUM_TARGETS):0]) begin
				rdata = target[t].timecmp[DWIDTH - 1:0];
				if (n_ts_r.addr[2]) begin
					rdata = target[t].timecmp[63:32];
				end
			end
		end
	end
	default: begin
		rdata = mtime[DWIDTH - 1:0];
		if (n_ts_r.addr[2]) begin
			rdata = mtime[63:32];
		end
	end
	endcase

	case (n_ts_w.addr[15:14])
	2'b00: begin
		for (t = 0; t < NUM_TARGETS; t++) begin
			if (axi_if.wdone &&
			    n_ts_w.addr[$clog2(NUM_TARGETS) + 2:2] == t[$clog2(NUM_TARGETS):0]) begin
				n_target[t].sip = axi_if.wdata[0];
			end
		end
	end
	2'b01: begin
		for (t = 0; t < NUM_TARGETS; t++) begin
			if (axi_if.wdone &&
			    n_ts_w.addr[$clog2(NUM_TARGETS) + 3:3] == t[$clog2(NUM_TARGETS):0]) begin
				if (n_ts_w.addr[2]) begin
					n_target[t].timecmp[63:32] = axi_if.wdata[31:0];
				end else begin
					n_target[t].timecmp[DWIDTH - 1:0] = axi_if.wdata;
				end
			end
		end
	end
	default: begin
		if (axi_if.wdone) begin
			if (n_ts_w.addr[2]) begin
				n_mtime[63:32] = axi_if.wdata[31:0];
			end else begin
				n_mtime[DWIDTH - 1:0] = axi_if.wdata;
			end
		end
	end
	endcase

	for (t = 0; t < NUM_TARGETS; t++) begin
		target_sip[t] = target[t].sip;
		target_tip[t] = mtime >= target[t].timecmp;
	end
end

always_ff @(posedge clk) begin
	mtime <= n_mtime;

	axi_if.arready <= !n_ts_r.v[0];
	axi_if.awready <= !(|n_ts_r.v);

	axi_if.rvalid <= n_ts_r.v[0];
	axi_if.rdata <= rdata;
	axi_if.rresp <= `AXI_OKAY;

	axi_if.wready <= n_ts_w.v[0] && axi_if.wvalid;
	axi_if.bvalid <= n_ts_w.v[1];
	axi_if.bresp <= `AXI_OKAY;

	ts_r.v <= n_ts_r.v;
	ts_r.addr <= n_ts_r.addr;
	ts_w.v <= n_ts_w.v;
	ts_w.addr <= n_ts_w.addr;

`ifdef YOSYS
	for (t = 0; t < NUM_TARGETS; t++) begin
		target[t] <= n_target[t];
	end
`else
	target <= n_target;
`endif

	if (rst) begin
		mtime <= 0;
		ts_r.v <= 0;
		ts_w.v <= 0;

		axi_if.arready <= 0;
		axi_if.awready <= 0;
		axi_if.rvalid <= 0;
		axi_if.wready <= 0;
		axi_if.bvalid <= 0;
	end
end
endmodule
