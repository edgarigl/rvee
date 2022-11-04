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
#include "Vrvee_fetch_tb.h"
#include "verilated_vcd_sc.h"

#include "test-modules/signals-axilite.h"
#include "tlm-bridges/axilite2tlm-bridge.h"
#include "checkers/pc-axilite.h"

AXILitePCConfig checker_config()
{
        AXILitePCConfig cfg;
        cfg.enable_all_checks();
	cfg.check_axi_handshakes(true, 1000);
        return cfg;
}

SC_MODULE(Top)
{
	tlm_utils::simple_target_socket<Top> target_socket;
	sc_signal<bool> rst;
	sc_signal<bool> rst_n;
	sc_clock clk;

	Vrvee_fetch_tb tb;

	AXILiteSignals<AWIDTH, DWIDTH> axi_signals;
	axilite2tlm_bridge<AWIDTH, DWIDTH> tlm_bridge;
	AXILiteProtocolChecker<AWIDTH, DWIDTH > checker;

	sc_signal<bool> p_ready;
	sc_signal<bool> p_jmp;
	sc_signal<bool> p_jmp_ff;
	sc_signal<sc_bv<XLEN> > p_jmp_base;
	sc_signal<sc_bv<XLEN> > p_jmp_offset;

	sc_signal<bool> f_valid;
	sc_signal<bool> f_ready;
	sc_signal<sc_bv<32> > f_iw;
	sc_signal<sc_bv<XLEN> > f_pc;
	sc_signal<bool> f_flush;

	class payload {
	public:
		xlen_t pc;
		uint32_t iw;
	};

	sc_fifo<payload *> queued_insns;

	unsigned int rand_seed;

	SC_HAS_PROCESS(Top);

	void wait_cycles(unsigned int n) {
		while (n--) {
			wait(clk.posedge_event());
		}
	}

	void wait_rand_cycles(void) {
		unsigned int rand_delay = (rand_r(&rand_seed) & 0xf) + 1;
		printf("%s: delay=%d\n", __func__, rand_delay);
		wait_cycles(rand_delay);
	}

	void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
		unsigned char *data = trans.get_data_ptr();
		uint64_t addr = trans.get_address();
		payload *p = new payload();
		bool flush = f_flush.read();
		uint32_t iw = rand_r(&rand_seed);

		sc_assert(trans.is_read());

		wait_rand_cycles();

		p->pc = addr;
		p->iw = iw;
		printf("AXI: pc=%lx iw=%x jmp_delay=%d jmp_dest=%x flush=%d\n",
			(uint64_t) p->pc, p->iw, jmp_delay, jmp_dest, flush);

		queued_insns.write(p);

		memcpy(data, &iw, trans.get_data_length());
		trans.set_response_status(tlm::TLM_OK_RESPONSE);
	}

	xlen_t jmp_dest;
	int jmp_delay;
	void decoder(void) {
		xlen_t pc;
		uint32_t iw;
		payload *p;
		bool jmp;
		xlen_t jmp_base = 0;
		xlen_t jmp_offset = 0;
		xlen_t prev_pc = -4; 

		jmp_dest = 0;
		jmp_delay = 0;
		wait(rst.negedge_event());
		f_ready.write(1);
		while (true) {
			wait(clk.posedge_event());
			while (f_valid.read() == 0) {
				wait(clk.posedge_event());
			}

			pc = f_pc.read().to_uint();
			iw = f_iw.read().to_uint();

			p = queued_insns.read();
			if (jmp_delay) {
				int depth = 5;

				while (p->pc != jmp_dest && depth > 0) {
					delete p;
					p = queued_insns.read();
					depth--;
				}
				sc_assert(p->pc == jmp_dest);
			}

			printf("DECODER: pc=%lx.%lx prev_pc=%lx iw=%x.%x jmp_delay=%d\n",
				(uint64_t) pc, (uint64_t) p->pc, (uint64_t) prev_pc, iw, p->iw,
				jmp_delay);

			if (jmp_delay) {
				jmp_delay -= 1;
				if (jmp_delay == 0) {
					sc_assert(pc == jmp_dest);
					sc_assert(p->pc == pc);
					sc_assert(p->iw == iw);
				}
			} else {
				sc_assert(p->pc == pc);
				sc_assert(p->iw == iw);

				if (pc != prev_pc + 4) {
					printf("BAD PC\n");
					sc_stop();
				}
			}
			delete p;
			p = NULL;

			/* Update PC, with randomized jumps.  */
			jmp = 0;
			if (!jmp_delay && 1) {
				jmp = (rand_r(&rand_seed) & 0x1f) == 0;
			}

			if (jmp) {
				jmp_delay = 1;
				jmp_base = rand_r(&rand_seed) & ~3;
				jmp_offset = 0;
				jmp_dest = jmp_base + jmp_offset;

				printf("JMP to %lx (%lx + %lx) p-r%d\n",
					(uint64_t) (jmp_base + jmp_offset),
					(uint64_t) jmp_base, (uint64_t) jmp_offset,
					p_ready.read());
			}

			p_jmp.write(jmp);
			p_jmp_base.write(jmp_base);
			p_jmp_offset.write(jmp_offset);

			prev_pc = pc;

			/* Apply randomized delay.  */
			f_ready.write(0);

			// Need to end the jmp.
			if (jmp && 1) {
				f_ready.write(1);
				wait(clk.posedge_event());
				f_ready.write(0);
				p_jmp.write(0);
				printf("END JMP f_valid=%d jmp_ff=%d jmp=%d\n",
					f_valid.read(), p_jmp_ff.read(), p_jmp.read());
				// dec stage is responsible for droping active insn when seeing
				// a jmp.
				if (f_valid.read()) {
					p = queued_insns.read();
					pc = f_pc.read().to_uint();

					printf("GOT an insn while jumping %x.%x flush=%d\n",
						pc, p->pc, f_flush.read());
					sc_assert(p->pc == pc); 
					printf("Dropped pc %x\n", p->pc);
					delete p;
					f_ready.write(1);
					wait(clk.posedge_event());
					f_ready.write(0);
				} else {
					f_ready.write(1);
					wait(clk.posedge_event());
					f_ready.write(0);
				}
				printf("END2 JMP f_valid=%d jmp_ff=%d jmp=%d\n",
					f_valid.read(), p_jmp_ff.read(), p_jmp.read());
				// dec stage is responsible for droping active insn when seeing
				// a jmp_ff.
				if (f_valid.read() && p_jmp_ff.read()) {
					p = queued_insns.read();
					pc = f_pc.read().to_uint();

					printf("GOT an insn while jumping %x.%x flush=%d\n",
						pc, p->pc, f_flush.read());
					sc_assert(p->pc == pc); 
					printf("Dropped pc %x\n", p->pc);
					delete p;
					f_ready.write(0);
				}
			}

			wait_rand_cycles();
			f_ready.write(1);
		}
	}

	void pull_reset(void) {
		/* Pull the reset signal.  */
		rst.write(true);
		wait(clk.negedge_event());
		wait(clk.posedge_event());
		rst.write(false);
	}

	void gen_rst_n(void) {
		rst_n.write(!rst.read());
	}

	Top(sc_module_name name, sc_time quantum, unsigned int rand_seed) :
		target_socket("target-socket"),
		rst("rst"),
		rst_n("rst_n"),
		clk("clk", sc_time(10, SC_NS)),
		tb("tb"),
		axi_signals("axi-signals"),
		tlm_bridge("tlm-bridge"),
		checker("checker", checker_config()),
		p_ready("p_ready"),
		p_jmp("p_jmp"),
		p_jmp_ff("p_jmp_ff"),
		p_jmp_base("p_jmp_base"),
		p_jmp_offset("p_jmp_offset"),
		f_valid("f_valid"),
		f_ready("f_ready"),
		f_iw("f_iw"),
		f_pc("f_pc"),
		f_flush("f_flush"),
		rand_seed(rand_seed)
	{
		m_qk.set_global_quantum(quantum);

		SC_THREAD(pull_reset);
		SC_THREAD(decoder);
		SC_METHOD(gen_rst_n);
		sensitive << rst;

	        target_socket.register_b_transport(this, &Top::b_transport);

		checker.clk(clk);
		checker.resetn(rst_n);
		tlm_bridge.clk(clk);
		tlm_bridge.resetn(rst_n);
		tlm_bridge.socket(target_socket);

		axi_signals.connect(tlm_bridge);
		axi_signals.connect(checker);
		axi_signals.connect(tb);

		tb.rst(rst);
		tb.clk(clk);

		tb.p_ready(p_ready);
		tb.p_jmp(p_jmp);
		tb.p_jmp_ff(p_jmp_ff);
		tb.p_jmp_base(p_jmp_base);
		tb.p_jmp_offset(p_jmp_offset);

		tb.f_valid(f_valid);
		tb.f_ready(f_ready);
		tb.f_iw(f_iw);
		tb.f_pc(f_pc);
		tb.f_flush(f_flush);
	}

private:
	tlm_utils::tlm_quantumkeeper m_qk;
};

#include "sc_main.h"
