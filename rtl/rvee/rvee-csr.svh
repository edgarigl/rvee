`ifndef __RVEE_CSR_SVH__
`define __RVEE_CSR_SVH__

`define RV_USER_MODE		0
`define RV_SUPERVISOR_MODE	1
`define RV_MACHINE_MODE		3

`define CSR_MODE_REGS(mode)			\
	logic	[XLEN - 1:0] mode``tvec;	\
	logic	[XLEN - 1:0] mode``scratch;	\
	logic	[XLEN - 1:0] mode``epc;		\
	logic	[XLEN - 1:0] mode``cause;	\
	logic	[XLEN - 1:0] mode``tval;	\
	logic	[3:0] mode``_n_irq_cause;		\
	logic	mode``ip;			\
	logic	mode``pie;			\
	logic	mode``ie;			\
	logic	mode``eie;			\
	logic	mode``sie;			\
	logic	mode``tie

`define CSR_MODE_REGS_PORT(dir, mode)		\
	dir	mode``tvec,			\
	dir	mode``scratch,			\
	dir	mode``epc,			\
	dir	mode``cause,			\
	dir	mode``tval,			\
	dir	mode``ip,			\
	dir	mode``pie,			\
	dir	mode``ie,			\
	dir	mode``eie,			\
	dir	mode``sie,			\
	dir	mode``tie

`define CSR_COMPUTE_IP(mode, offset)				\
	mode``ip = 0;						\
	mode``_n_irq_cause = 0;					\
	if (mode``ie) begin					\
		if (mode``eie & mode``eip) begin		\
			mode``ip = 1;				\
			mode``_n_irq_cause = 8 + offset;	\
		end						\
		if (mode``tie & mode``tip) begin		\
			mode``ip = 1;				\
			mode``_n_irq_cause = 4 + offset;	\
		end						\
		if (mode``sie & mode``sip) begin		\
			mode``ip = 1;				\
			mode``_n_irq_cause = 0 + offset;	\
		end						\
	end

interface rvee_csr_if #(parameter N_REGS=32, XLEN=32) (
	input clk,
	input rst,
	input meip, msip, mtip,
	input seip, ssip, stip);

	logic r_en;
	logic w_en;
	logic [1:0] op;
	logic [11:0] csr_reg;
	logic [XLEN - 1:0] rdata;
	logic [XLEN - 1:0] wdata;
	logic [XLEN - 1:0] pc;
	logic illegal;

	logic we_tval;
	logic [XLEN - 1:0] n_tval;

	logic exception;
	logic irq;
	logic irq_pending;
	logic [XLEN - 2:0] n_cause;

	logic	[1:0] mode;

	`CSR_MODE_REGS(m);
	`CSR_MODE_REGS(s);

	always_comb begin
		sip = 0;
		mip = 0;

		`CSR_COMPUTE_IP(s, `RV_SUPERVISOR_MODE);
		`CSR_COMPUTE_IP(m, `RV_MACHINE_MODE);

		// Lower privilege levels never interrupt higher ones.
		if (mode == `RV_MACHINE_MODE) begin
			sip = 0;
		end

		irq_pending = mip | sip;
	end

	modport decode_port(input rdata,
			`CSR_MODE_REGS_PORT(input, m),
			`CSR_MODE_REGS_PORT(input, s),
			input mode, irq_pending, illegal,
			output pc, r_en, w_en, op, csr_reg, wdata,
			output exception, irq, n_cause, we_tval, n_tval);
	modport csr_port(output rdata,
			`CSR_MODE_REGS_PORT(output, m),
			`CSR_MODE_REGS_PORT(output, s),
			output mode, illegal,
			input pc, r_en, w_en, op, csr_reg, wdata,
			input exception, irq, irq_pending, n_cause, we_tval, n_tval);
endinterface
`endif
