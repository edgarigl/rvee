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
#include "utils.h"
#include "trace/trace.h"
#include "Vrvee_exec_tb.h"
#include "verilated_vcd_sc.h"

SC_MODULE(Top)
{
	sc_signal<bool> rst;
	sc_clock clk;

	Vrvee_exec_tb tb;

	sc_signal<bool> eip;
	sc_signal<bool> sip;
	sc_signal<bool> tip;

	sc_signal<bool> d_valid;
	sc_signal<bool> d_ready;
	sc_signal<sc_bv<XLEN> > d_pc;
	sc_signal<bool> d_rd_we;
	sc_signal<sc_bv<5> > d_rd;
	sc_signal<sc_bv<3> > d_op;
	sc_signal<sc_bv<XLEN> > d_a;
	sc_signal<sc_bv<XLEN> > d_b;
	sc_signal<bool> d_c;
	sc_signal<bool> d_msb_xor;
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

	sc_signal<bool> p_jmp;
	sc_signal<bool> p_jmp_ff;
	sc_signal<bool> p_jmp_out;
	sc_signal<sc_bv<XLEN> > p_jmp_base;
	sc_signal<sc_bv<XLEN> > p_jmp_offset;
	sc_signal<sc_bv<XLEN> > p_pc;

	sc_signal<bool> e_valid;
	sc_signal<bool> e_ready;
	sc_signal<sc_bv<XLEN> > e_pc;
	sc_signal<bool> e_rd_we;
	sc_signal<sc_bv<5> > e_rd;
	sc_signal<sc_bv<XLEN> > e_result;
	sc_signal<bool> e_mem_load;
	sc_signal<bool> e_mem_store;
	sc_signal<sc_bv<XLEN> > e_mem_data;
	sc_signal<sc_bv<2> > e_mem_size;
	sc_signal<bool> e_mem_sext;

	unsigned int rand_seed;

	class payload {
	public:
		xlen_t pc, a, b, org_b;
		bool rd_we;
		unsigned int rd;
		bool c;
		bool msb_xor;
		bool sra;
		rv_alu_op_t op;

		bool mem_load;
		bool mem_store;
		xlen_t mem_data;
		unsigned int mem_size;
		bool mem_sext;

		bool jmp;
		int jmp_base;
		int jmp_offset;
		bool bcc;
		bool bcc_n;

		bool next_jmp_bcc;
	};
	sc_fifo<payload *> queue;

	SC_HAS_PROCESS(Top);

	void wait_cycles(unsigned int n) {
		while (n--) {
			wait(clk.posedge_event());
		}
	}

	void wait_rand_cycles(void) {
		unsigned int rand_delay = rand_r(&rand_seed) & 0x1f;
		wait_cycles(rand_delay);
	}

	struct {
		int equal_ops;
		int negated_ops;
		int complemented_ops;
		int op_zero[2];
		int op_max[2];

		bool do_mem;
		bool do_jmp_bcc;
		bool next_jmp_bcc;
	} setup;

	void prep_setup(void) {
		int i;

		setup.equal_ops = (rand_r(&rand_seed) & 7) == 0;
		setup.negated_ops = (rand_r(&rand_seed) & 7) == 0;
		setup.complemented_ops = (rand_r(&rand_seed) & 7) == 0;
		setup.do_mem = (rand_r(&rand_seed) & 3) == 0;
		setup.do_jmp_bcc = setup.next_jmp_bcc;
		setup.next_jmp_bcc = (rand_r(&rand_seed) & 7) == 0;

		for (i = 0; i < 2; i++) {
			setup.op_zero[i] = (rand_r(&rand_seed) & 7) == 0;
			setup.op_max[i] = (rand_r(&rand_seed) & 7) == 0;
		}

//		setup.do_mem = 0;
//		setup.do_jmp_bcc = 0;

		printf("eq=%d neg=%d compl=%d\n",
			setup.equal_ops, setup.negated_ops, setup.complemented_ops);
	}

	xlen_t gen_op(int op) {
		if (setup.op_zero[op])
			return 0;
		if (setup.op_zero[op])
			return XLEN_MAX;
		return rand_r(&rand_seed);
	}

	void decode(void) {
		payload *p;

		wait(rst.negedge_event());
		while (true) {
			printf("rand_seed=%x\n", rand_seed);
			prep_setup();

			p = new payload();
			p->pc = rand_r(&rand_seed) & ~0x3;
			p->rd_we = rand_r(&rand_seed) & 1;
			p->rd = rand_r(&rand_seed) & 31;
			p->op = (rv_alu_op_t) ((int)rand_r(&rand_seed) & 7);
			printf("OP=%d\n", p->op);
			p->a = gen_op(0);
			if (setup.equal_ops)
				p->b = p->a;
			else
				p->b = gen_op(1);
			if (setup.negated_ops) {
				p->b = -p->a;
			}
			if (setup.complemented_ops) {
				p->b = - ~p->a;
			}
			p->c = rand_r(&rand_seed) & 1;
			p->sra = p->c;

			p->mem_load = 0;
			p->mem_store = 0;
			p->mem_data = rand_r(&rand_seed);
			p->mem_size = rand_r(&rand_seed) & 3;
			p->mem_sext = rand_r(&rand_seed) & 1;

			if (0) {
				p->jmp = 0;
				p->bcc = 0;
				p->op = ALU_SLTU;
			}
			if (0) {
				// Catches bug in ALU_SLT.
				p->jmp = 0;
				p->bcc = 0;
				p->op = ALU_SLT;
				p->a = 0x641299c3;
				p->b = 0x9bed663d;
			}

			p->org_b = p->b;
			p->next_jmp_bcc = setup.next_jmp_bcc;

			if (setup.do_mem) {
				p->mem_load = rand_r(&rand_seed) & 1;
				p->mem_store = !p->mem_load;
				p->op = ALU_ADD;
				// We carry mem_data over jmp_base.
				p->jmp_base = p->mem_data;
			} else if (setup.do_jmp_bcc) {
				p->jmp = rand_r(&rand_seed) & 1;
				p->bcc = !p->jmp;
				p->bcc_n = rand_r(&rand_seed) & 1;
				p->c = p->bcc;

				p->jmp_base = p->pc;
				if (p->bcc) {
					p->jmp_offset = rand_r(&rand_seed);
					p->jmp_offset &= ~1;
					p->jmp_offset &= 0x1fff;
					p->jmp_offset = rv_sext(13, p->jmp_offset);
				} else {
					p->jmp_offset = rand_r(&rand_seed);
				}

				if (p->jmp) {
					p->op = ALU_ADD;
					p->a = p->pc;
					p->b = 4;
				} else {
					rv_alu_op_t valid_ops[] = {
						ALU_ADD, ALU_SLT, ALU_SLTU,
					};
					p->op = valid_ops[rand_r(&rand_seed) % 3];
					printf("op=%x\n", p->op);
					if (p->op == ALU_ADD) {
						/* SLT/SLTU prepped below.  */
						p->b = ~p->b;
						p->c = 1;
					}
				}
			}

			switch (p->op) {
			case ALU_SLT:
			case ALU_SLTU:
				p->b = ~p->b;
				p->c = 1;
				break;
			default:
				break;
			}

			p->msb_xor = (p->a ^ p->org_b) >> (XLEN - 1);
			d_pc.write(p->pc);
			d_rd_we.write(p->rd_we);
			d_rd.write(p->rd);
			d_op.write(p->op);
			d_a.write(p->a);
			d_b.write(p->b);
			d_c.write(p->c);
			d_msb_xor.write(p->msb_xor);
			d_sra.write(p->sra);

			d_mem_load.write(p->mem_load);
			d_mem_store.write(p->mem_store);
			d_mem_size.write(p->mem_size);
			d_mem_sext.write(p->mem_sext);

			d_jmp.write(p->jmp);
			d_bcc.write(p->bcc);
			d_jmp_base.write(p->jmp_base);
			d_jmp_offset.write(p->jmp_offset);
			d_bcc_n.write(p->bcc_n);

			queue.write(p);
			printf("DEC: pc=%lx rd=%x op=%x a=%lx b=%lx org_b=%lx c=%d sra=%d "
				"mem ld=%d st=%d sz=%d ext=%d jmp=%d bcc=%d.%d j-b-o=%lx.%lx\n\n",
				(uint64_t) p->pc, p->rd, p->op,
				(uint64_t) p->a, (uint64_t) p->b, (uint64_t) p->org_b,
				p->c, p->sra,
				p->mem_load, p->mem_store, p->mem_size, p->mem_sext,
				p->jmp, p->bcc, p->bcc_n,
				(uint64_t)p->jmp_base, (uint64_t)p->jmp_offset);


			d_valid.write(1);
			wait(clk.posedge_event());
			while (d_ready.read() == 0) {
				wait(clk.posedge_event());
			}

			/* Apply randomized delay.  */
			d_valid.write(0);
			wait_rand_cycles();
		}
	}

	void mem(void) {
		xlen_t pc, result, d;
		bool rd_we;
		unsigned int rd;
		bool mem_load;
		bool mem_store;
		xlen_t mem_data;
		unsigned int mem_size;
		bool mem_sext;
		bool jmp;
		bool jmp_ff;
		bool jmp_out;
		xlen_t jmp_base;
		xlen_t jmp_offset;
		payload *p;

		wait(rst.negedge_event());
		while (true) {
			e_ready.write(1);
			wait(clk.posedge_event());
			while (e_valid.read() == 0) {
				wait(clk.posedge_event());
			}

			p = queue.read();
			pc = e_pc.read().to_uint();
			rd_we = e_rd_we.read();
			rd = e_rd.read().to_uint();
			result = e_result.read().to_uint();
			mem_load = e_mem_load.read();
			mem_store = e_mem_store.read();
			mem_data = e_mem_data.read().to_uint();
			mem_size = e_mem_size.read().to_uint();
			mem_sext = e_mem_sext.read();
			jmp = p_jmp.read();
			jmp_ff = p_jmp_ff.read();
			jmp_out = p_jmp_out.read();
			jmp_base = p_jmp_base.read().to_uint();
			jmp_offset = p_jmp_offset.read().to_uint();

			switch (p->op) {
			case ALU_ADD: d = p->a + p->b + p->c; break;
			case ALU_SLL: d = p->a << (p->b & (XLEN - 1)); break;
			case ALU_SLT: {
				xlen_t tmp, hw_d;

				d = (sxlen_t)p->a < (sxlen_t)p->org_b;

				tmp = p->a + p->b + p->c;
				// B got negated by the decoder.
//				if ((p->a ^ (~p->b)) & (1ULL << (XLEN - 1))) {
				if (p->msb_xor) {
					hw_d = p->a;
				} else {
					hw_d = tmp;
				}
				hw_d >>= XLEN - 1;
				printf("result=%d d=%d hw_d=%d a=%x b=%x.%x c=%d msb_xor=%x tmp=%x\n",
					result, d, hw_d, p->a, p->b, p->org_b, p->c,
					p->msb_xor, tmp);
				if (d != hw_d) {
					fflush(NULL);
					sc_assert(0);
				}
				if ((sxlen_t)p->a < 0 && (sxlen_t)p->org_b > 0) {
					sc_assert(d == 1);
				}
				if ((sxlen_t)p->a > 0 && (sxlen_t)p->org_b < 0) {
					sc_assert(d == 0);
				}
				break;
			}
			case ALU_SLTU: {
				uint64_t tmp;
				bool hw_d;

				d = p->a < p->org_b;

				tmp = (uint64_t) p->a + p->b + p->c;
				hw_d = !(tmp & (1ULL << 32));
				printf("a=%x b=%x c=%d d=%x hw_d=%x tmp=%lx\n",
					p->a, p->b, p->c, d, hw_d, tmp);
				sc_assert(d == hw_d);
				break;
			}
			case ALU_SRL:
				if (p->sra) {
					d = (sxlen_t)p->a >> (p->b & XLEN_CLOG2_MASK);
				} else {
					d = p->a >> (p->b & XLEN_CLOG2_MASK);
				}
				break;
			case ALU_XOR: d = p->a ^ p->b; break;
			case ALU_OR: d = p->a | p->b; break;
			case ALU_AND: d = p->a & p->b; break;
			default: d = 0; break;
			}

			printf("MEM: pc=%lx.%lx op=%d rd=%x result=%lx a=%lx b=%lx.%lx d=%lx c=%d sra=%d jmp_base=%lx jmp=%d.%d.%d\n",
				(uint64_t) pc, (uint64_t) p->pc, p->op, rd, (uint64_t) result,
				(uint64_t) p->a, (uint64_t) p->b, (uint64_t) p->org_b,
				(uint64_t) d, p->c, p->sra, (uint64_t) jmp_base,
				jmp, jmp_ff, jmp_out);

			if (p->jmp) {
				fflush(NULL);

				// jmp_out check only works if we didn't apply
				// random wait on the insn prior to the jump.
				sc_assert(p->jmp == jmp_out);
//				sc_assert(jmp_base + jmp_offset == (p->jmp_base + p->jmp_offset));
			} else if (p->bcc) {
				bool taken;

				switch (p->op) {
				case ALU_ADD:
					taken = p->a == p->org_b;
					break;
				case ALU_SLT:
					taken = (sxlen_t)p->a < (sxlen_t)p->org_b;
					// We implement these via the Z flag.
					taken = taken == 0;
					break;
				case ALU_SLTU:
					taken = p->a < p->org_b;
					// We implement these via the Z flag.
					taken = taken == 0;
					break;
				default:
					sc_assert(0);
					break;
				};

				if (p->bcc_n)
					taken = !taken;

				printf("bcc taken=%d pc=%lx op=%d a=%x b=%x org_b=%x bcc_n=%d jmp=%d.%d j-base=%lx.%lx j-offset=%lx.%lx\n",
					taken, (uint64_t)pc, p->op, p->a, p->b, p->org_b, p->bcc_n, jmp, taken,
					(uint64_t)jmp_base, (uint64_t)p->jmp_base,
					(uint64_t)jmp_offset, (uint64_t)p->jmp_offset);
				sc_assert(p_jmp_out.read() == taken);

				// After a bcc we need to ignore the next insns since
				// the EXEC stage will drop it.
				if (taken && d_valid.read()) {
					payload *p;
					p = queue.read();
					delete p;
				}
//				sc_assert(jmp_base + jmp_offset == p->jmp_base + p->jmp_offset);
			} else {
		//		sc_assert(jmp_ff == 0);
			}

			sc_assert(p->pc == pc);
			sc_assert(p->rd_we == rd_we);
			sc_assert(p->rd == rd);
			sc_assert(result == d);
			sc_assert(p->mem_load == mem_load);
			sc_assert(p->mem_store == mem_store);
			sc_assert(p->mem_size == mem_size);
			sc_assert(p->mem_sext == mem_sext);

			if (p->mem_store) {
				sc_assert(p->mem_data == mem_data);
			}

			/* Apply randomized delay.  */
			e_ready.write(0);
			if (!p->next_jmp_bcc && !p->jmp && !p->bcc) {
				wait_rand_cycles();
			}
			delete p;
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
		eip("eip"),
		sip("sip"),
		tip("tip"),
		d_valid("d_valid"),
		d_ready("d_ready"),
		d_pc("d_pc"),
		d_rd("d_rd"),
		d_op("d_op"),
		d_a("d_a"),
		d_b("d_b"),
		d_c("d_c"),
		d_msb_xor("d_msb_xor"),
		d_sra("d_sra"),
		d_mem_load("d_mem_load"),
		d_mem_store("d_mem_store"),
		d_mem_size("d_mem_size"),
		d_mem_sext("d_mem_sext"),
		d_jmp("d_jmp"),
		d_jmp_base("d_jmp_base"),
		d_jmp_offset("d_jmp_offset"),
		d_bcc("d_bcc"),
		d_bcc_n("d_bcc_m"),

		p_jmp("p_jmp"),
		p_jmp_ff("p_jmp_ff"),
		p_jmp_out("p_jmp_out"),
		p_jmp_base("p_jmp_base"),
		p_jmp_offset("p_jmp_offset"),
		p_pc("p_pc"),

		e_valid("e_valid"),
		e_ready("e_ready"),
		e_pc("e_pc"),
		e_rd_we("e_rd_we"),
		e_rd("e_rd"),
		e_result("e_result"),
		e_mem_load("e_mem_load"),
		e_mem_store("e_mem_store"),
		e_mem_data("e_mem_data"),
		e_mem_size("e_mem_size"),
		e_mem_sext("e_mem_sext"),
		rand_seed(rand_seed)
	{
		m_qk.set_global_quantum(quantum);

		SC_THREAD(pull_reset);
		SC_THREAD(decode);
		SC_THREAD(mem);

		tb.rst(rst);
		tb.clk(clk);

		tb.eip(eip);
		tb.sip(sip);
		tb.tip(tip);

		tb.d_valid(d_valid);
		tb.d_ready(d_ready);
		tb.d_pc(d_pc);
		tb.d_rd_we(d_rd_we);
		tb.d_rd(d_rd);
		tb.d_op(d_op);
		tb.d_a(d_a);
		tb.d_b(d_b);
		tb.d_c(d_c);
		tb.d_msb_xor(d_msb_xor);
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

		tb.p_jmp(p_jmp);
		tb.p_jmp_ff(p_jmp_ff);
		tb.p_jmp_out(p_jmp_out);
		tb.p_jmp_base(p_jmp_base);
		tb.p_jmp_offset(p_jmp_offset);
		tb.p_pc(p_pc);

		tb.e_valid(e_valid);
		tb.e_ready(e_ready);
		tb.e_pc(e_pc);
		tb.e_rd_we(e_rd_we);
		tb.e_rd(e_rd);
		tb.e_result(e_result);
		tb.e_mem_load(e_mem_load);
		tb.e_mem_store(e_mem_store);
		tb.e_mem_data(e_mem_data);
		tb.e_mem_size(e_mem_size);
		tb.e_mem_sext(e_mem_sext);
	}

private:
	tlm_utils::tlm_quantumkeeper m_qk;
};

#include "sc_main.h"
