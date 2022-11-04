`include "include/axi.svh"
`include "rvee/rvee-pcgen.svh"
`include "rvee/rvee-fetch.svh"

module rvee_fetch_tb #(parameter AWIDTH=32, DWIDTH=32, XLEN=32) (
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

	output	p_ready,
	input	p_jmp,
	output	p_jmp_ff,
	input	[XLEN - 1:0] p_jmp_base,
	input	[XLEN - 1:0] p_jmp_offset,

	output	f_valid,
	input	f_ready,
	output	[31:0] f_iw,
	output	[XLEN - 1:0] f_pc,
	output	f_flush);

	wire    [XLEN - 1:0] resetv;

	axi4lite_if axi_fetch_if();
	rvee_pcgen_if pcgen_if(.*);
	rvee_fetch_if fetch_if(.*);

	rvee_pcgen pcgen(.*);
	rvee_fetch fetch(.*);

	// Connect the interface to the outside world.
	assign	awvalid = axi_fetch_if.awvalid;
	assign	axi_fetch_if.awready = awready;
	assign	awaddr = axi_fetch_if.awaddr;
	assign	awprot = axi_fetch_if.awprot;

	assign	arvalid = axi_fetch_if.arvalid;
	assign	axi_fetch_if.arready = arready;
	assign	araddr = axi_fetch_if.araddr;
	assign	arprot = axi_fetch_if.arprot;

	assign	wvalid = axi_fetch_if.wvalid;
	assign	axi_fetch_if.wready = wready;
	assign	wdata = axi_fetch_if.wdata;
	assign	wstrb = axi_fetch_if.wstrb;

	assign	axi_fetch_if.bvalid = bvalid;
	assign	bready = axi_fetch_if.bready;
	assign	axi_fetch_if.bresp = bresp;

	assign	axi_fetch_if.rvalid = rvalid;
	assign	rready = axi_fetch_if.rready;
	assign	axi_fetch_if.rdata = rdata;
	assign	axi_fetch_if.rresp = rresp;

	assign	p_ready = pcgen_if.ready;
	assign	p_jmp_ff = pcgen_if.jmp_ff;
	assign	pcgen_if.jmp = p_jmp;
	assign	pcgen_if.jmp_base = p_jmp_base;
	assign	pcgen_if.jmp_offset = p_jmp_offset;

	assign	f_valid = fetch_if.valid;
	assign	f_iw = fetch_if.iw;
	assign	f_pc = fetch_if.pc;
	assign	f_flush = fetch_if.flush;
	assign	fetch_if.ready = f_ready;
endmodule
