/*
 * Parameterized Platform Interrupt Controller (PLIC).
 *
 * Copyright (C) 2022 Edgar E. Iglesias.
 * Written by Edgar E. Iglesias <edgar.iglesias@gmail.com>
 *
 * SPDX-License-Identifier: MIT
 */

`include "include/axi.svh"

/*
base + 0x000000: Reserved (interrupt source 0 does not exist)
base + 0x000004: Interrupt source 1 priority
base + 0x000008: Interrupt source 2 priority
...
base + 0x000FFC: Interrupt source 1023 priority
base + 0x001000: Interrupt Pending bit 0-31
base + 0x00107C: Interrupt Pending bit 992-1023
...
base + 0x002000: Enable bits for sources 0-31 on context 0
base + 0x002004: Enable bits for sources 32-63 on context 0
...
base + 0x00207F: Enable bits for sources 992-1023 on context 0
base + 0x002080: Enable bits for sources 0-31 on context 1
base + 0x002084: Enable bits for sources 32-63 on context 1
...
base + 0x0020FF: Enable bits for sources 992-1023 on context 1
base + 0x002100: Enable bits for sources 0-31 on context 2
base + 0x002104: Enable bits for sources 32-63 on context 2
...
base + 0x00217F: Enable bits for sources 992-1023 on context 2
...
base + 0x1F1F80: Enable bits for sources 0-31 on context 15871
base + 0x1F1F84: Enable bits for sources 32-63 on context 15871
base + 0x1F1FFF: Enable bits for sources 992-1023 on context 15871
...
base + 0x1FFFFC: Reserved
base + 0x200000: Priority threshold for context 0
base + 0x200004: Claim/complete for context 0
base + 0x200008: Reserved
...
base + 0x200FFC: Reserved
base + 0x201000: Priority threshold for context 1
base + 0x201004: Claim/complete for context 1
...
base + 0x3FFE000: Priority threshold for context 15871
base + 0x3FFE004: Claim/complete for context 15871
base + 0x3FFE008: Reserved
...
base + 0x3FFFFFC: Reserved
*/

module plic #(AWIDTH=32, DWIDTH=32, NUM_SOURCES=32, NUM_TARGETS=1, MAX_PRIO=3) (
	input clk,
	input rst,
	input  [NUM_SOURCES - 1:0] source,
	output logic [NUM_TARGETS - 1:0] target,
	axi4lite_if.target_port axi_if);

	typedef union packed {
		logic [NUM_SOURCES - 1:0] b;
		logic [((NUM_SOURCES + 31) / 32) - 1:0] [31:0] r32;
	} bitv_t;

	logic [$clog2(MAX_PRIO) - 1:0] prio [NUM_SOURCES - 1:0];
	logic [$clog2(MAX_PRIO) - 1:0] n_prio [NUM_SOURCES - 1:0];

	logic [$clog2(MAX_PRIO) - 1:0] target_prio [NUM_TARGETS - 1:0];
	logic [$clog2(MAX_PRIO) - 1:0] n_target_prio [NUM_TARGETS - 1:0];

	logic [$clog2(NUM_TARGETS) - 1:0] claim_target [NUM_SOURCES - 1:0];
	logic [$clog2(NUM_TARGETS) - 1:0] n_claim_target [NUM_SOURCES - 1:0];

	bitv_t enable[NUM_TARGETS];
	bitv_t n_enable[NUM_TARGETS];
	bitv_t pending;
	bitv_t claim;
	bitv_t n_claim;
	logic [NUM_TARGETS - 1:0] claim_we;

	logic [DWIDTH - 1:0] rdata_prio;
	logic [DWIDTH - 1:0] rdata_target_prio;
	logic [DWIDTH - 1:0] rdata_pending;
	logic [DWIDTH - 1:0] rdata_enable;
	logic [DWIDTH - 1:0] rdata;

	logic [$clog2(NUM_SOURCES) - 1:0] irq_id [NUM_TARGETS - 1:0];
	logic [$clog2(MAX_PRIO) - 1:0] irq_prio;

	integer i, t;

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

// PLIC Gateway
always_comb begin
	for (i = 0; i < NUM_SOURCES; i++) begin
		pending.b[i] = source[i] & !claim[i];
	//	$display("%d: pend%d s%d c%d prio%d", i, pending.b[i], source[i], claim[i], prio[i]);
	end
end

always_comb begin
	rdata_prio = 0;
	rdata_pending = 0;
	rdata_enable = 0;

	i = {22'd0, n_ts_r.addr[11:2]};
	rdata_pending = pending.r32[i];
	rdata_prio = {{(DWIDTH - $clog2(MAX_PRIO)){1'b0}}, prio[i]};

	i = {27'd0, n_ts_r.addr[6:2]};
	rdata_target_prio = {{(DWIDTH - $clog2(MAX_PRIO)){1'b0}}, target_prio[i]};

	for (t = 0; t < NUM_TARGETS; t++) begin
		if ((t + 32'h40) == {18'd0, n_ts_r.addr[20:7]}) begin
			rdata_enable = enable[t].r32[i];
		end
		if ((t + 32'h200) == {18'd0, n_ts_r.addr[25:12]}) begin
		end
	end
end

always_comb begin
	rdata = 0;
	n_claim = claim;
	claim_we = {NUM_TARGETS{1'b0}};
	for (i = 0; i < NUM_SOURCES; i++) begin
		n_prio[i] = prio[i];
		n_claim_target[i] = claim_target[i];
	end
	for (t = 0; t < NUM_TARGETS; t++) begin
		n_enable[t] = enable[t];
		n_target_prio[t] = target_prio[t];
	end

	for (t = 0; t < NUM_TARGETS; t++) begin
		irq_id[t] = 0;
		irq_prio = target_prio[t];

		for (i = 0; i < NUM_SOURCES; i++) begin
			if (pending.b[i] && enable[t].b[i] && prio[i] > irq_prio) begin
				irq_id[t] = i[$clog2(NUM_SOURCES) - 1:0];
				irq_prio = prio[i];
			end
		end
		//$display("irq_id[%d]=%d prio=%d", t, irq_id[t], target_prio[t]);
	end

	case (n_ts_r.addr[25:12])
	14'h00000: begin
		rdata = rdata_prio;
		//$display("read prio %x", rdata_prio);
	end
	14'h00001: begin
		rdata = rdata_pending;
		//$display("read pending %x", rdata_pending);
	end
	default: begin
		case (n_ts_r.addr[25:20])
		6'h00,
		6'h01: begin
			rdata = rdata_enable;
			$display("rdata_enable=%x", rdata);
		end
		default: begin
			if (n_ts_r.addr[11:0] == 12'h000) begin
				rdata = rdata_target_prio;
			end else if (n_ts_r.addr[11:0] == 12'h004) begin
				for (t = 0; t < NUM_TARGETS; t++) begin
					if ((t + 32'h200) == {18'd0, n_ts_r.addr[25:12]}) begin
						$display("claimed t=%d i=%d", t, irq_id[t]);
						claim_we[t] = 1;
						rdata = {{(DWIDTH - $clog2(NUM_SOURCES)){1'b0}}, irq_id[t]};
					end
				end
			end
		end
		endcase
	end
	endcase

	case (n_ts_w.addr[25:12])
	14'h00000: begin
		i = {22'd0, n_ts_w.addr[11:2]};
		n_prio[i] = axi_if.wdata[$clog2(MAX_PRIO) - 1:0];
		$display("prio[%d] <= %x", i, axi_if.wdata);
	end
	14'h00001: begin
	end
	default: begin
		case (n_ts_w.addr[25:20])
		6'h00,
		6'h01: begin
			i = {27'd0, n_ts_w.addr[6:2]};
			for (t = 0; t < NUM_TARGETS; t++) begin
				if ((t + 32'h40) == {18'd0, n_ts_w.addr[20:7]}) begin
					n_enable[t].r32[i] = axi_if.wdata;
					$display("enable[%d][%d] <= %x", t, i, axi_if.wdata);
				end
			end
		end
		default: begin
			if (n_ts_w.addr[11:0] == 12'h000) begin
				for (t = 0; t < NUM_TARGETS; t++) begin
					if ((t + 32'h200) == {18'd0, n_ts_w.addr[25:12]}) begin
						$display("target_prio[%d] <= %x", t, axi_if.wdata);
						n_target_prio[t] = axi_if.wdata[$clog2(MAX_PRIO) - 1:0];
					end
				end
			end else if (n_ts_w.addr[11:0] == 12'h004) begin
				for (i = 0; i < NUM_SOURCES; i++) begin
					if (axi_if.wdone && i == axi_if.wdata) begin
						$display("complete_we src=%d", i);
						for (t = 0; t < NUM_TARGETS; t++) begin
							if (claim.b[i]
							    && (t + 32'h200) == {18'd0, n_ts_w.addr[25:12]}
							    && claim_target[i] == t[$clog2(NUM_TARGETS) - 1:0]) begin
								n_claim.b[i] = 0;
							end
						end
					end
				end
			end
		end
		endcase
	end
	endcase

	for (t = 0; t < NUM_TARGETS; t++) begin
		for (i = 0; i < NUM_SOURCES; i++) begin
			if (claim_we[t] && axi_if.rdone
			    && i[$clog2(NUM_SOURCES) - 1:0] == irq_id[t]) begin
				$display("n_claim.b[%d] <= 1", i);
				n_claim.b[i] = 1;
				n_claim_target[i] = t[$clog2(NUM_TARGETS) - 1:0];
			end
		end
	end

	for (t = 0; t < NUM_TARGETS; t++) begin
		target[t] = |irq_id[t];
	end
end

always_ff @(posedge clk) begin
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
	for (i = 0; i < NUM_SOURCES; i++) begin
		prio[i] <= n_prio[i];
		claim_target[i] <= n_claim_target[i];
	end
	for (t = 0; t < NUM_TARGETS; t++) begin
		enable[t] <= n_enable[t];
		target_prio[t] <= n_target_prio[t];
	end
`else
	prio <= n_prio;
	enable <= n_enable;
	target_prio <= n_target_prio;
	claim_target <= n_claim_target;
`endif
	claim <= n_claim;

	if (rst) begin
		claim.b <= {NUM_SOURCES{1'b0}};
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
