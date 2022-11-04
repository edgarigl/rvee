/*
 * RVee memory (load/store) unit.
 *
 * TODO: Add support for multiple out-standing transactions.
 *
 * Copyright (C) 2022 Edgar E. Iglesias.
 * Written by Edgar E. Iglesias <edgar.iglesias@gmail.com>
 *
 * SPDX-License-Identifier: MIT
 */

/* verilator lint_off DECLFILENAME */
`include "include/axi.svh"
`include "rvee/rvee-config.svh"
`include "rvee/rvee-exec.svh"
`include "rvee/rvee-mem.svh"
`include "rvee/rvee-csr-regs.vh"
`include "rvee/rvee-rf.svh"

module rvee_mem #(parameter XLEN=32, AWIDTH=32, DWIDTH=32) (
	input clk,
	input rst,
	axi4lite_if.master_port axi_mem_if,
	rvee_rf_if.mem_port rf_if,
	rvee_exec_if.mem_port exec_if,
	rvee_mem_if.mem_port mem_if);

	integer exec_if_mem_size = exec_if.mem_size;
	assign	axi_mem_if.arprot = 0;
	assign	axi_mem_if.awprot = 0;

`ifdef RVEE_CONFIG_MEM_BPU
	wire	[XLEN - 1:0] ea;
	wire	fault;
	mem_bpu bpu(exec_if.valid && (exec_if.mem_load | exec_if.mem_store), exec_if.result, ea, fault);
`else
	wire	fault = 0;
	wire	[XLEN - 1:0] ea = exec_if.result;
`endif

	logic	axi_pending;
	logic	n_axi_pending;

always_comb begin
	// Register forwarding.
	rf_if.wb_we = mem_if.rd_we;
	rf_if.wb_rd = mem_if.rd;
	rf_if.wb_data = mem_if.rd_data;
end

// Back-pressure handling.
always_comb begin
	exec_if.ready = 0;

	if (exec_if.valid) begin
		if (axi_pending) begin
			exec_if.ready = axi_mem_if.rdone | axi_mem_if.bdone;
		end else begin
			exec_if.ready = !(exec_if.mem_load | exec_if.mem_store) || mem_if.exception;
		end
	end

	if (rst) begin
		exec_if.ready = 0;
	end
end

// Compute wstrb
	logic	[3:0] wstrb;
always_comb begin
	case (exec_if_mem_size)
	0: wstrb = 4'b0001;
	1: wstrb = 4'b0011;
	2: wstrb = 4'b1111;
	default: wstrb = 4'd0;
	endcase

	case (ea[1:0])
	0: wstrb = wstrb;
	1: wstrb = {wstrb[2:0], 1'b0};
	2: wstrb = {wstrb[1:0], 2'b0};
	3: wstrb = {wstrb[0], 3'b0};
	default: wstrb = 4'd0;
	endcase
end

// Compute wdata
	logic	[XLEN - 1:0] wdata;
always_comb begin
	wdata = exec_if.mem_data;
	case (ea[1:0])
	0: wdata = wdata;
	1: wdata = {wdata[XLEN - 1 - 8:0], 8'dx};
	2: wdata = {wdata[XLEN - 1 - 16:0], 16'dx};
	3: wdata = {wdata[XLEN - 1 - 24:0], 24'dx};
	endcase
end

// Compute rdata
	logic	[XLEN - 1:0] rdata;
always_comb begin
	rdata = axi_mem_if.rdata;
	case (ea[1:0])
	0: rdata = rdata;
	1: rdata = {8'dx, rdata[XLEN - 1:8]};
	2: rdata = {16'dx, rdata[XLEN - 1:16]};
	3: rdata = {24'dx, rdata[XLEN - 1:24]};
	endcase

	case (exec_if_mem_size)
	0: rdata = {{24{rdata[7] & exec_if.mem_sext}}, rdata[7:0]};
	1: rdata = {{16{rdata[15] & exec_if.mem_sext}}, rdata[15:0]};
	default: rdata = rdata;
	endcase
end

// We can handle some unaligned accesses, but not all.
	logic	addr_unaligned;
always_comb begin
	case (exec_if_mem_size)
	1: addr_unaligned = ea[1:0] == 3;
	2: addr_unaligned = ea[1:0] != 0;
	default: addr_unaligned = 0;
	endcase

end

	logic	issue_ax;
always_comb begin
	n_axi_pending = axi_pending;
	if (axi_mem_if.rdone || axi_mem_if.bdone) begin
		n_axi_pending = 0;
	end

	issue_ax = !axi_pending;
	if (exec_if.valid && issue_ax) begin
		n_axi_pending = exec_if.mem_load | exec_if.mem_store;
	end

	mem_if.exception = 0;
`ifdef RVEE_ZICSR
	mem_if.fault_pc = exec_if.pc;
	mem_if.fault_addr = ea;
	mem_if.n_cause = 0;
	if (n_axi_pending && fault) begin
		n_axi_pending = 0;
		issue_ax = 0;
		mem_if.exception = 1;
		if (exec_if.mem_load) begin
			mem_if.n_cause = `MCAUSE_LOAD_ADDRESS_FAULT;
		end else begin
			mem_if.n_cause = `MCAUSE_STORE_ADDRESS_FAULT;
		end
	end
	if (n_axi_pending && addr_unaligned) begin
		n_axi_pending = 0;
		issue_ax = 0;

		// Raise an address exception
		mem_if.exception = 1;
		if (exec_if.mem_load) begin
			mem_if.n_cause = `MCAUSE_LOAD_ADDRESS_MISALIGNED;
		end else begin
			mem_if.n_cause = `MCAUSE_STORE_ADDRESS_MISALIGNED;
		end
	end
`endif
end

always_ff @(posedge clk) begin
	mem_if.rd_we <= exec_if.rd_we && !mem_if.exception;
	mem_if.rd <= exec_if.rd;
	mem_if.rd_data <= exec_if.result;

	axi_mem_if.araddr <= ea;
	axi_mem_if.awaddr <= ea;
	axi_mem_if.wdata <= wdata;
	axi_mem_if.wstrb <= wstrb;
	axi_mem_if.rready <= 1;
	axi_mem_if.bready <= 1;
	axi_pending <= n_axi_pending;

	if (axi_mem_if.ardone) begin
		axi_mem_if.arvalid <= 0;
	end
	if (axi_mem_if.awdone) begin
		axi_mem_if.awvalid <= 0;
	end
	if (axi_mem_if.wdone) begin
		axi_mem_if.wvalid <= 0;
	end
	if (axi_mem_if.rdone) begin
		mem_if.rd_we <= 1;
		mem_if.rd_data <= rdata;
	end

	if (exec_if.valid & issue_ax) begin
		axi_mem_if.arvalid <= exec_if.mem_load;
		axi_mem_if.awvalid <= exec_if.mem_store;
		axi_mem_if.wvalid <= exec_if.mem_store;
	end

	if (rst) begin
		axi_mem_if.arvalid <= 0;
		axi_mem_if.awvalid <= 0;
		axi_mem_if.wvalid <= 0;
		mem_if.rd_we <= 0;
		axi_pending <= 0;
	end

`ifdef DEBUG_MEM_LD
	if (axi_mem_if.rdone) begin
		$display("MEM: loaded m[%x]=%x %x mem_size=%d\n",
			exec_if.result, rdata, axi_mem_if.rdata, exec_if.mem_size);
	end
`endif
	if (exec_if.valid && !axi_pending) begin
		if (exec_if.mem_store) begin
`ifdef DEBUG_MEM_ST
			$display("MEM:  pc %x store addr %x mem-sz=%d memdata=%x wdata=%x addr-low=%b wstrb=%b",
				exec_if.pc, exec_if.result,
				exec_if.mem_size, exec_if.mem_data, wdata, exec_if.result[1:0],
				wstrb);
`endif
		end else begin
`ifdef DEBUG_MEM
			$display("MEM:  pc %x reg-wb rd=%d rd_we=%d rd_data=%x axi_pending=%d ex%d-pc%x",
				exec_if.pc, exec_if.rd, exec_if.rd_we, exec_if.result, axi_pending,
				mem_if.exception, mem_if.fault_pc);
`endif
		end
	end
end
endmodule
