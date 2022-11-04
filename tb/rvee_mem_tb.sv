`include "include/axi.svh"
`include "rvee/rvee-mem.svh"

module rvee_mem_tb #(parameter AWIDTH=32, DWIDTH=32, XLEN=32) (
	input	clk,
	input	rst,

	output	awvalid,
	input	awready,
	output	[AWIDTH - 1:0] awaddr,
	output	[2:0] awprot,

	output	arvalid,
	input	arready,
	output	[AWIDTH - 1:0] araddr,
	output	[2:0] arprot,

	output	wvalid,
	input	wready,
	output	[DWIDTH - 1:0] wdata,
	output	[(DWIDTH/8) - 1:0] wstrb,

	input	bvalid,
	output	bready,
	input	[1:0] bresp,

	input	rvalid,
	output	rready,
	input	[DWIDTH - 1:0] rdata,
	input	[1:0] rresp,

	input	e_valid,
	output	e_ready,
	input	[XLEN - 1: 0] e_pc,
	input	e_rd_we,
	input	[4:0] e_rd,
	input	[XLEN - 1:0] e_result,
	input	e_mem_load,
	input	e_mem_store,
	input	[XLEN - 1:0] e_mem_data,
	input	[1:0] e_mem_size,
	input	e_mem_sext,

	output	m_rd_we,
	output	[4:0] m_rd,
	output	[XLEN - 1:0] m_rd_data);

	axi4lite_if axi_mem_if();
	rvee_exec_if exec_if(.*);
	rvee_mem_if mem_if(.*);
	rvee_rf_if rf_if(.*);

	rvee_mem mem(.*);

	// Connect the interface to the outside world.
	assign	awvalid = axi_mem_if.awvalid;
	assign	axi_mem_if.awready = awready;
	assign	awaddr = axi_mem_if.awaddr;
	assign	awprot = axi_mem_if.awprot;

	assign	arvalid = axi_mem_if.arvalid;
	assign	axi_mem_if.arready = arready;
	assign	araddr = axi_mem_if.araddr;
	assign	arprot = axi_mem_if.arprot;

	assign	wvalid = axi_mem_if.wvalid;
	assign	axi_mem_if.wready = wready;
	assign	wdata = axi_mem_if.wdata;
	assign	wstrb = axi_mem_if.wstrb;

	assign	axi_mem_if.bvalid = bvalid;
	assign	bready = axi_mem_if.bready;
	assign	axi_mem_if.bresp = bresp;

	assign	axi_mem_if.rvalid = rvalid;
	assign	rready = axi_mem_if.rready;
	assign	axi_mem_if.rdata = rdata;
	assign	axi_mem_if.rresp = rresp;

	assign	exec_if.valid = e_valid;
	assign	e_ready = exec_if.ready;
	assign	exec_if.pc = e_pc;
	assign	exec_if.rd_we = e_rd_we;
	assign	exec_if.rd = e_rd;
	assign	exec_if.result = e_result;
	assign	exec_if.mem_data = e_mem_data;
	assign	exec_if.mem_load = e_mem_load;
	assign	exec_if.mem_store = e_mem_store;
	assign	exec_if.mem_size = e_mem_size;
	assign	exec_if.mem_sext = e_mem_sext;

	assign	m_rd_we = mem_if.rd_we;
	assign	m_rd = mem_if.rd;
	assign	m_rd_data = mem_if.rd_data;
endmodule
