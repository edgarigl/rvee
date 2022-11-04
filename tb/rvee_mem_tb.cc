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
#include "Vrvee_mem_tb.h"
#include "verilated_vcd_sc.h"

#include "test-modules/signals-axilite.h"
#include "tlm-bridges/axilite2tlm-bridge.h"
#include "checkers/pc-axilite.h"

#define RVEE_BPU 1
#define BPU_TAG_MASK (0xffUL << ((sizeof (xlen_t) - 1) * 8))


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

	Vrvee_mem_tb tb;

	AXILiteSignals<AWIDTH, DWIDTH> axi_signals;
	axilite2tlm_bridge<AWIDTH, DWIDTH> tlm_bridge;
	AXILiteProtocolChecker<AWIDTH, DWIDTH > checker;

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

	sc_signal<bool> m_rd_we;
	sc_signal<sc_bv<5> > m_rd;
	sc_signal<sc_bv<XLEN> > m_rd_data;

	class payload {
	public:
		xlen_t pc;
		bool rd_we;
		unsigned int rd;
		xlen_t result;
		xlen_t b;
		bool mem_load, mem_store;
		unsigned int mem_size;
		bool mem_sext;
		uint32_t iw;

		xlen_t rd_data;

		uint64_t mem_data;

		bool do_mem;
	};

	sc_fifo<payload *> queue_mem;
	sc_fifo<payload *> queue_wb;

	unsigned int rand_seed;

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

	void exec(void) {
		payload *p;

		wait(rst.negedge_event());
		wait(clk.posedge_event());
		while (true) {
			p = new payload();

			p->do_mem = (rand_r(&rand_seed) & 7) > 2;
			p->result = rand_r(&rand_seed);
			p->pc = rand_r(&rand_seed) & ~3;
			p->rd_we = rand_r(&rand_seed) & 1;
			p->rd = rand_r(&rand_seed) & 31;

			p->rd_data = p->result;

			p->mem_size = rand_r(&rand_seed) % 3;
			p->mem_size = 0;

			if (p->do_mem) {
				if (RVEE_BPU) {
					p->result &= ~BPU_TAG_MASK;
				}

				p->mem_data = rand_r(&rand_seed);
				p->mem_load = rand_r(&rand_seed) & 1;
				p->mem_store = !p->mem_load;
				p->mem_size = rand_r(&rand_seed) % 3;

				if (p->mem_size != 0) {
					p->result &= ~((1 << p->mem_size) - 1);
				}

				p->mem_sext = rand_r(&rand_seed) & 1 & p->mem_load;

				p->rd_we = 0;
				p->rd_data = p->mem_data;
			}

			printf("EX: pc %lx result=%lx rd_we=%d rd=%d b=%lx mem-data=%lx load=%d store=%d size=%d sext=%d\n",
				(uint64_t) p->pc, (uint64_t) p->result, p->rd_we, p->rd,
				(uint64_t) p->b, (uint64_t) p->mem_data,
				p->mem_load, p->mem_store, p->mem_size,
				p->mem_sext);

			e_result.write(p->result);
			e_rd.write(p->rd);
			e_mem_data.write(p->mem_data);
			e_mem_load.write(p->mem_load);
			e_mem_store.write(p->mem_store);
			e_mem_data.write(p->mem_data);
			e_mem_size.write(p->mem_size);
			e_mem_sext.write(p->mem_sext);

			e_rd_we.write(p->rd_we);
			e_valid.write(1);
			if (p->do_mem) {
				queue_mem.write(p);
			}
			if (p->rd_we || p->mem_load) {
				queue_wb.write(p);
			}

			wait(clk.posedge_event());
			while (e_ready.read() == 0) {
				wait(clk.posedge_event());
			}
			e_rd_we.write(0);
			e_valid.write(0);
			wait_rand_cycles();
		}
	}

	void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
		unsigned char *data = trans.get_data_ptr();
		uint64_t addr = trans.get_address();
		unsigned int size = trans.get_data_length();
		unsigned char *be = trans.get_byte_enable_ptr();
		unsigned int be_len = trans.get_byte_enable_length();
		uint64_t v = 0;
		payload *p;

		p = queue_mem.read();

		if (trans.is_read()) {
			uint64_t rdata = p->mem_data << ((p->result & 3) * 8);

			printf("MEM: rdata=%lx mem_data=%lx\n",
				rdata, p->mem_data);
			memcpy(data, &rdata, size);
		} else {
			if (be_len) {
				unsigned int pos;
				bool do_access;
				unsigned char *dest = (unsigned char *) &v;

				for (pos = 0; pos < size; pos++) {
					do_access = be[pos % be_len] == TLM_BYTE_ENABLED;
					if (do_access)
						dest[pos] = data[pos];
				}
			} else {
				memcpy(&v, data, size);
			}
			v >>= ((p->result & 3) * 8);
		}

		printf("MEM: addr=%lx.%lx rd_we=%d rd=%d v=%lx.%lx load=%d store=%d size=%d.%d sext=%d\n",
			addr, (uint64_t) p->result, p->rd_we, p->rd,
			v, (uint64_t) p->b,
			p->mem_load, p->mem_store, size, p->mem_size,
			p->mem_sext);

		fflush(NULL);
		sc_assert(addr == (p->result & ~3));
		sc_assert(trans.is_read() == p->mem_load);
		sc_assert(size == (1U << p->mem_size) || size == XLEN / 8);
		if (p->mem_store) {
			unsigned int size_bytes = 1 << p->mem_size;
			uint64_t size_mask = ((1ULL << (size_bytes * 8)) - 1);

			sc_assert(v == (p->mem_data & size_mask));
		}
		wait_rand_cycles();

		if (p->mem_store) {
			delete p;
		}
		trans.set_response_status(tlm::TLM_OK_RESPONSE);
	}

	void wb(void) {
		xlen_t rd_data;
		bool rd_we;
		unsigned int rd;
		payload *p;
		uint64_t masked_data;

		wait(rst.negedge_event());
		while (true) {
			printf("WAIT FOR rd_we\n");
			while (m_rd_we.read() == 0) {
				wait(clk.posedge_event());
			}

			rd_we = m_rd_we.read();
			rd = m_rd.read().to_uint();
			rd_data = m_rd_data.read().to_uint();

			p = queue_wb.read();

			masked_data = p->rd_data;

			if (p->mem_load) {
				unsigned int size_bytes = 1 << p->mem_size;
				uint64_t size_mask = ((1ULL << (size_bytes * 8)) - 1);

				masked_data = p->rd_data & size_mask;
				if (p->mem_sext) {
					masked_data = rv_sext(size_bytes * 8, masked_data);
				}
			}
			printf("WB: pc %lx rd_we=%d.%d rd=%d.%d rd_data=%lx.%lx.%lx sz%d md=%lx\n",
				(uint64_t) p->pc, rd_we, p->rd_we, rd, p->rd,
				(uint64_t) rd_data, (uint64_t) p->rd_data, masked_data,
				p->mem_size, p->mem_data);

			sc_assert(rd_we == (p->rd_we || p->mem_load));
			if (rd_we || p->mem_load) {
				sc_assert(rd == p->rd);
				sc_assert(rd_data == masked_data);
			}
			delete p;
			wait(clk.posedge_event());
		}
	}

	void pull_reset(void) {
		/* Pull the reset signal.  */
		rst.write(true);
		wait(40, SC_NS);
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
		m_rd_we("m_rd_we"),
		m_rd("m_rd"),
		m_rd_data("m_rd_data"),
		rand_seed(rand_seed)
	{
		m_qk.set_global_quantum(quantum);

		SC_THREAD(pull_reset);
		SC_THREAD(exec);
		SC_THREAD(wb);
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

		tb.m_rd_we(m_rd_we);
		tb.m_rd(m_rd);
		tb.m_rd_data(m_rd_data);
	}

private:
	tlm_utils::tlm_quantumkeeper m_qk;
};

#include "sc_main.h"
