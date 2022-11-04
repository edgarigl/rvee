/*
 * Top level of the RVee TB.
 *
 * Copyright (c) 2022 Edgar E. Iglesias.
 * Written by Edgar E. Iglesias <edgar.iglesias@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#define SC_INCLUDE_DYNAMIC_PROCESSES

#include <inttypes.h>
#include <stdio.h>
#include <signal.h>
#include <unistd.h>

#include "systemc.h"
#include "tlm_utils/simple_initiator_socket.h"
#include "tlm_utils/simple_target_socket.h"
#include "tlm_utils/tlm_quantumkeeper.h"

using namespace sc_core;
using namespace sc_dt;
using namespace std;

#include "rvee.h"
#include "trace/trace.h"
#include "Vrvee_decode_tb.h"
#include "verilated_vcd_sc.h"
enum {
	INSN_R_ALU,
	INSN_I_ALU,
	INSN_I_LD,
	INSN_ST,
	INSN_BCC,
	INSN_JAL,
	INSN_I_JALR,
	INSN_LUI,
	INSN_AUIPC,
	INSN_MAX
};
 
SC_MODULE(Top)
{
	sc_signal<bool> rst;
	sc_clock clk;

	Vrvee_decode_tb tb;

	sc_signal<bool> meip;
	sc_signal<bool> msip;
	sc_signal<bool> mtip;
	sc_signal<bool> seip;
	sc_signal<bool> ssip;
	sc_signal<bool> stip;

	sc_signal<bool> f_valid;
	sc_signal<bool> f_ready;
	sc_signal<sc_bv<32> > f_iw;
	sc_signal<sc_bv<32> > f_pc;

	sc_signal<bool> d_valid;
	sc_signal<bool> d_ready;
	sc_signal<sc_bv<XLEN> > d_pc;
	sc_signal<bool> d_rd_we;
	sc_signal<sc_bv<5> > d_rd;
	sc_signal<sc_bv<3> > d_op;
	sc_signal<sc_bv<XLEN> > d_a;
	sc_signal<sc_bv<XLEN> > d_b;
	sc_signal<bool> d_c;
	sc_signal<bool> d_sra;
	sc_signal<bool> d_mem_load;
	sc_signal<bool> d_mem_store;
	sc_signal<sc_bv<2> > d_mem_size;
	sc_signal<bool> d_mem_sext;
	sc_signal<bool> d_jmp;
	sc_signal<sc_bv<XLEN> > d_jmp_base;
	sc_signal<sc_bv<XLEN> > d_jmp_offset;
	sc_signal<bool> d_bcc;
	sc_signal<bool> d_bcc_n;

	unsigned int rand_seed;

	class payload {
	public:
		int kind;
		xlen_t pc;
		xlen_t a;
		xlen_t b;
		uint32_t iw;

		rv_alu_op_t op;
		bool rd_we;
		unsigned int rd;
		unsigned int rs1;
		unsigned int rs2;
		bool c;
		bool sra;
		bool mem_load;
		bool mem_store;
		unsigned int mem_size;
		bool mem_sext;
		bool jmp;
		xlen_t jmp_base;
		xlen_t jmp_offset;
		bool bcc;
		bool bcc_n;
		uint32_t imm;

		rv_cc_t cc;
	};
	sc_fifo<payload *> queue;

	SC_HAS_PROCESS(Top);

	void wait_cycles(unsigned int n) {
		while (n--) {
			wait(clk.posedge_event());
		}
	}

	void wait_rand_cycles(void) {
		unsigned int rand_delay = rand_r(&rand_seed) & 0xff;
		wait_cycles(rand_delay);
	}

	void fetch(void) {
		const char *kind_names[INSN_MAX];
		payload *p;

		kind_names[INSN_R_ALU] = "r-alu";
		kind_names[INSN_I_ALU] = "i-alu";
		kind_names[INSN_I_LD] = "ld";
		kind_names[INSN_ST] = "st";
		kind_names[INSN_BCC] = "bcc";
		kind_names[INSN_JAL] = "jal";
		kind_names[INSN_I_JALR] = "jalr";
		kind_names[INSN_LUI] = "lui";
		kind_names[INSN_AUIPC] = "auipc";

		wait(rst.negedge_event());
		while (true) {
			p = new payload();

			p->kind = rand_r(&rand_seed) % INSN_MAX;

			p->pc = rand_r(&rand_seed) & ~3;
			p->op = (rv_alu_op_t)(rand_r(&rand_seed) & 7);
			p->rd = rand_r(&rand_seed) & 31;
			p->rs1 = rand_r(&rand_seed) & 31;
			p->rs2 = rand_r(&rand_seed) & 31;
			p->imm = rand_r(&rand_seed);
			p->rd_we = 0;
			p->jmp = 0;
			p->bcc = 0;
			p->bcc_n = 0;
			p->a = 0;
			p->c = 0;
			p->sra = 0;
			p->mem_load = 0;
			p->mem_store = 0;
			p->jmp_base = 0;
			p->jmp_offset = 0;

			printf("%s:\n", kind_names[p->kind]);
			switch (p->kind) {
			case INSN_LUI: {
				p->imm &= ~0xfff;
				p->rd_we = 1;
				p->op = ALU_ADD;
				p->a = 0;
				p->b = p->imm;
				p->iw = rvee_encode_u(LUI_TYPE, p->rd, p->imm);
				break;
			}
			case INSN_BCC: {
				rv_cc_t valid_cc[] = {
					CC_EQ, CC_NE,
					CC_LT, CC_GE,
					CC_LTU, CC_GEU
				};
				p->imm &= ~1;
				p->imm &= 0x1fff;
				p->jmp_base = p->pc;
				p->jmp_offset = rv_sext(13, p->imm);

				p->cc = valid_cc[rand_r(&rand_seed) % 6];
				p->c = 1;
				p->bcc = 1;

				switch (p->cc) {
				case CC_EQ:
					p->op = ALU_ADD;
					break;
				case CC_NE:
					p->op = ALU_ADD;
					p->bcc_n = 1;
					break;
				case CC_LT:
					p->op = ALU_SLT;
					p->bcc_n = 1;
					break;
				case CC_LTU:
					p->op = ALU_SLTU;
					p->bcc_n = 1;
					break;
				case CC_GE:
					p->op = ALU_SLT;
					break;
				case CC_GEU:
					p->op = ALU_SLTU;
					break;
				}

				printf("BCC cc=%d imm=%x\n", p->cc, p->imm);
				p->iw = rvee_encode_bcc(p->rs1, p->rs2, p->cc, p->imm);
				break;
			}
			case INSN_JAL: {
				p->imm &= ~1;
				p->imm &= 0x1fffff;
				p->rd_we = 1;
				p->op = ALU_ADD;
				p->a = p->pc;
				p->b = 4;
				p->c = 0;
				p->jmp_base = p->pc;
				p->jmp_offset = rv_sext(21, p->imm);
				p->jmp = 1;
				p->iw = rvee_encode_jal(p->rd, p->imm);
				break;
			}
			case INSN_I_JALR: {
				p->imm &= 0xfff;
				p->rd_we = 1;
				p->op = ALU_ADD;
				p->a = p->pc;
				p->b = 4;
				p->c = 0;
				p->jmp_base = p->pc;
				p->jmp_offset = rv_sext(12, p->imm);
				p->jmp = 1;
				p->iw = rvee_encode_i(I_JALR_TYPE, p->op, p->rd, p->rs1, p->imm);
				break;
			}
			case INSN_AUIPC: {
				p->imm &= ~0xfff;
				p->rd_we = 1;
				p->op = ALU_ADD;
				p->a = p->pc;
				p->b = p->imm;
				p->iw = rvee_encode_u(AUIPC_TYPE, p->rd, p->imm);
				break;
			}
			case INSN_I_LD: {
				p->imm &= 0xfff;
				// Loads enable the write at the MEM stage
				// to avoid polluting the register forwarding.
				p->rd_we = 0;
				p->b = rv_sext(12, p->imm);
				p->mem_load = 1;
				p->mem_size = rand_r(&rand_seed) & 3;
				p->mem_sext = rand_r(&rand_seed) & 1;

				p->op = (rv_alu_op_t)(!p->mem_sext << 2 | p->mem_size);
				p->iw = rvee_encode_i(I_LD_TYPE, p->op, p->rd, p->rs1, p->imm);
				break;
			}
			case INSN_ST: {
				p->imm &= 0xfff;
				p->b = rv_sext(12, p->imm);
				p->mem_store = 1;
				p->mem_size = rand_r(&rand_seed) % 3;

				p->op = (rv_alu_op_t)(p->mem_sext << 2 | p->mem_size);
				p->iw = rvee_encode_s(p->rs1, p->rs2, p->mem_size, p->imm);
				break;
			}
			case INSN_I_ALU: {
				p->imm &= 0xfff;
				p->sra = p->imm & (1 << 10);
				p->rd_we = 1;
				p->b = rv_sext(12, p->imm);
				if (p->op == ALU_SLT || p->op == ALU_SLTU) {
					p->b = ~p->b;
					p->c = 1;
				}

				p->iw = rvee_encode_i(I_ALU_TYPE, p->op, p->rd, p->rs1, p->imm);
				break;
			}
			case INSN_R_ALU:
			default:
				if (p->op == ALU_ADD || p->op == ALU_SRL) {
					p->c = rand_r(&rand_seed) & 1;
					p->sra = p->c;
				}
				p->rd_we = 1;

				p->iw = rvee_encode_r(p->op, p->rd, p->rs1, p->rs2, p->c);
				if (p->op == ALU_SLT || p->op == ALU_SLTU) {
					p->c = 1;
				}
				break;
			}

			queue.write(p);

			printf("FETCH: pc=%lx iw=%x\n", (uint64_t) p->pc, p->iw);

			f_pc.write(p->pc);
			f_iw.write(p->iw);
			f_valid.write(1);
			wait(clk.posedge_event());
			while (f_ready.read() == 0) {
				wait(clk.posedge_event());
			}

			/* Apply randomized delay.  */
			f_valid.write(0);
			wait_rand_cycles();
		}
	}

	void exec(void) {
		xlen_t pc, a, b;
		unsigned int op;
		bool rd_we;
		unsigned int rd;
		bool c;
		bool sra;
		bool mem_load;
		bool mem_store;
		unsigned int mem_size;
		bool mem_sext;
		bool jmp;
		xlen_t jmp_base;
		xlen_t jmp_offset;
		bool bcc;
		bool bcc_n;
		payload *p;

		wait(rst.negedge_event());
		while (true) {
			d_ready.write(1);
			wait(clk.posedge_event());
			while (d_valid.read() == 0) {
				wait(clk.posedge_event());
			}

			pc = d_pc.read().to_uint();
			op = d_op.read().to_uint();
			a = d_a.read().to_uint();
			b = d_b.read().to_uint();
			rd_we = d_rd_we.read();
			rd = d_rd.read().to_uint();
			c = d_c.read();
			sra = d_sra.read();
			mem_load = d_mem_load.read();
			mem_store = d_mem_store.read();
			mem_size = d_mem_size.read().to_uint();
			mem_sext = d_mem_sext.read();
			jmp = d_jmp.read();
			jmp_base = d_jmp_base.read().to_uint();
			jmp_offset = d_jmp_offset.read().to_uint();
			bcc = d_bcc.read();
			bcc_n = d_bcc_n.read();

			p = queue.read();

			printf("EX: pc=%lx op=%x rd_we=%d.%d rd=%d.%d a=%lx.%lx b=%lx.%lx c%d.%d sra=%d.%d ld=%d.%d st=%d.%d jb=%lx.%lx jo=%lx.%lx\n",
				(uint64_t)pc, op, rd_we, p->rd_we, rd, p->rd,
				(uint64_t) a, (uint64_t) p->a,
				(uint64_t) b, (uint64_t) p->b,
				c, p->c, sra, p->sra,
				mem_load, p->mem_load,
				mem_store, p->mem_store,
				(uint64_t) jmp_base, (uint64_t) p->jmp_offset,
				(uint64_t) jmp_offset, (uint64_t) p->jmp_offset);

			sc_assert(p->pc == pc);
			sc_assert(p->op == p->op);
			sc_assert(p->rd_we == rd_we);
			if (rd_we)
				sc_assert(p->rd == rd);
			sc_assert(p->jmp == jmp);
			sc_assert(p->bcc == bcc);
			sc_assert(p->mem_load == mem_load);
			sc_assert(p->mem_store == mem_store);

			switch (p->kind) {
			case INSN_LUI:
			case INSN_AUIPC:
				sc_assert(p->c == c);
				sc_assert(p->a == a);
				sc_assert(p->b == b);
				break;
			case INSN_BCC:
				sc_assert(p->c == c);
				sc_assert(p->jmp_base == jmp_base);
				sc_assert(p->jmp_offset == jmp_offset);
				sc_assert(p->sra == sra);
				sc_assert(p->bcc_n == bcc_n);
				break;
			case INSN_JAL:
				sc_assert(p->a == p->pc);
				sc_assert(p->b == 4);
				sc_assert(p->c == 0);
				sc_assert(p->jmp_base == jmp_base);
				sc_assert(p->jmp_offset == jmp_offset);
				break;
			case INSN_I_JALR:
				sc_assert(p->a == a);
				sc_assert(p->b == b);
				sc_assert(p->c == c);
				// jmp_base comes from rs1 whis is unknown at
				// fetch.
				// sc_assert(p->jmp_base == jmp_base);
				sc_assert(p->jmp_offset == jmp_offset);
				break;
			case INSN_I_LD:
				sc_assert(p->mem_size == mem_size);
				sc_assert(p->mem_sext == mem_sext);
				sc_assert(p->b == b);
				sc_assert(p->c == c);
				break;
			case INSN_ST:
				sc_assert(p->mem_size == mem_size);
				sc_assert(p->b == b);
				sc_assert(p->c == c);
				break;
			case INSN_I_ALU:
				sc_assert(p->b == b);
				sc_assert(p->c == c);
				sc_assert(p->sra == sra);
				break;
			case INSN_R_ALU:
				sc_assert(p->c == c);
				sc_assert(p->sra == sra);
				break;
			default:
				break;
			}

			delete p;

			/* Apply randomized delay.  */
			d_ready.write(0);
			wait_rand_cycles();
		}
	}

	void pull_reset(void) {
		/* Pull the reset signal.  */
		rst.write(true);
		wait(1, SC_US);
		rst.write(false);
	}

	Top(sc_module_name name, sc_time quantum, unsigned int rand_seed) :
		rst("rst"),
		clk("clk", sc_time(10, SC_NS)),
		tb("tb"),
		meip("meip"),
		msip("msip"),
		mtip("mtip"),
		seip("seip"),
		ssip("ssip"),
		stip("stip"),
		f_valid("f_valid"),
		f_ready("f_ready"),
		f_iw("f_iw"),
		f_pc("f_pc"),
		d_valid("d_valid"),
		d_ready("d_ready"),
		d_pc("d_pc"),
		d_rd_we("d_rd_we"),
		d_rd("d_rd"),
		d_op("d_op"),
		d_a("d_a"),
		d_b("d_b"),
		d_c("d_c"),
		d_sra("d_sra"),
		d_mem_load("d_mem_load"),
		d_mem_store("d_mem_store"),
		d_mem_size("d_mem_size"),
		d_mem_sext("d_mem_sext"),
		d_jmp("d_jmp"),
		d_jmp_base("d_jmp_base"),
		d_jmp_offset("d_jmp_offset"),
		d_bcc("d_bcc"),
		d_bcc_n("d_bcc_n"),
		rand_seed(rand_seed)
	{
		m_qk.set_global_quantum(quantum);

		SC_THREAD(pull_reset);
		SC_THREAD(fetch);
		SC_THREAD(exec);

		tb.rst(rst);
		tb.clk(clk);

		tb.meip(meip);
		tb.msip(msip);
		tb.mtip(mtip);
		tb.seip(seip);
		tb.ssip(ssip);
		tb.stip(stip);

		tb.f_valid(f_valid);
		tb.f_ready(f_ready);
		tb.f_iw(f_iw);
		tb.f_pc(f_pc);

		tb.d_valid(d_valid);
		tb.d_ready(d_ready);
		tb.d_pc(d_pc);
		tb.d_rd_we(d_rd_we);
		tb.d_rd(d_rd);
		tb.d_op(d_op);
		tb.d_a(d_a);
		tb.d_b(d_b);
		tb.d_c(d_c);
		tb.d_sra(d_sra);
		tb.d_mem_load(d_mem_load);
		tb.d_mem_store(d_mem_store);
		tb.d_mem_size(d_mem_size);
		tb.d_mem_sext(d_mem_sext);
		tb.d_jmp(d_jmp);
		tb.d_jmp_base(d_jmp_base);
		tb.d_jmp_offset(d_jmp_offset);
		tb.d_bcc(d_bcc);
		tb.d_bcc_n(d_bcc_n);
	}

private:
	tlm_utils::tlm_quantumkeeper m_qk;
};

#include "sc_main.h"
