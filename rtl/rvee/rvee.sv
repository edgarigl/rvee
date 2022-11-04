`include "include/axi.svh"
`include "rvee/rvee-pcgen.svh"
`include "rvee/rvee-fetch.svh"
`include "rvee/rvee-decode.svh"
`include "rvee/rvee-exec.svh"
`include "rvee/rvee-mem.svh"
`include "rvee/rvee-rf.svh"

module rvee_core #(parameter AWIDTH=32, DWIDTH=32, XLEN=32) (
	input	clk,
	input	rst,

	input	[XLEN - 1:0] resetv,
	input	meip,	// External interrupt pending
	input	msip,	// Software interrupt pending
	input	mtip,	// Timer interrupt pending
	input	seip,	// External interrupt pending
	input	ssip,	// Software interrupt pending
	input	stip,	// Timer interrupt pending
	axi4lite_if.master_port axi_fetch_if,
	axi4lite_if.master_port axi_mem_if);

	rvee_pcgen_if pcgen_if(.*);
	rvee_rf_if rf_if(.*);

	rvee_fetch_if fetch_if(.*);
	rvee_decode_if decode_if(.*);
	rvee_exec_if exec_if(.*);
	rvee_mem_if mem_if(.*);

	rvee_csr_if csr_if(.*);
	rvee_rf_ff rf(.*);
	rvee_pcgen pcgen(.*);

	rvee_fetch fetch(.*);
	rvee_decode decode(.*);
	rvee_csr csr(.*);
	rvee_exec exec(.*);
	rvee_mem mem(.*);
endmodule
