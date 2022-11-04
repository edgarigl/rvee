`ifndef __RVEE_INSN_SVH__
`define __RVEE_INSN_SVH__

`define CSR_RW	3'b001
`define CSR_RS	3'b010
`define CSR_RC	3'b011

typedef union packed {
	struct packed {
		logic [6:0] funct7;
		logic [4:0] rs2;
		logic [4:0] rs1;
		logic [2:0] funct3;
		logic [4:0] rd;
		logic [6:0] opcode;

	} r;

	struct packed {
		logic [11:0] imm;
		logic [4:0] rs1;
		logic [2:0] funct3;
		logic [4:0] rd;
		logic [6:0] opcode;
	} i;

	struct packed {
		logic [6:0] imm2;
		logic [4:0] rs2;
		logic [4:0] rs1;
		logic [2:0] funct3;
		logic [4:0] imm;
		logic [6:0] opcode;
	} s;

	struct packed {
		logic imm4;
		logic [5:0] imm2;
		logic [4:0] rs2;
		logic [4:0] rs1;
		logic [2:0] funct3;
		logic [3:0] imm;
		logic imm3;
		logic [6:0] opcode;
	} b;

	struct packed {
		logic imm4;
		logic [9:0]imm;
		logic imm2;
		logic [7:0] imm3;
		logic [4:0] rd;
		logic [6:0] opcode;
	} j;

	struct packed {
		logic [19:0] imm;
		logic [4:0] rd;
		logic [6:0] opcode;
	} u;
} insn_t;
`endif
