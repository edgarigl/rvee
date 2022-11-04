/*
 * Top level of the PLIC TB.
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

#include "trace/trace.h"
#include "Vclint_tb.h"
#include "verilated_vcd_sc.h"

#include "test-modules/signals-axilite.h"
#include "tlm-bridges/tlm2axilite-bridge.h"
#include "checkers/pc-axilite.h"

#define D(x)

#define AWIDTH 32
#define DWIDTH 32
#define NUM_TARGETS 1024

#define CLINT_BASE_TIMECMP 0x4000
#define CLINT_MTIME 0xBFF8

AXILitePCConfig checker_config()
{
        AXILitePCConfig cfg;
        cfg.enable_all_checks();
	cfg.check_axi_handshakes(true, 1000);
        return cfg;
}

SC_MODULE(Top)
{
	tlm_utils::simple_initiator_socket<Top> socket;
	sc_signal<bool> rst;
	sc_signal<bool> rst_n;
	sc_clock clk;

	Vclint_tb tb;

	AXILiteSignals<AWIDTH, DWIDTH> axi_signals;
	tlm2axilite_bridge<AWIDTH, DWIDTH> tlm_bridge;
	AXILiteProtocolChecker<AWIDTH, DWIDTH > checker;

#if NUM_TARGETS == 1
	sc_signal<bool > target_sip;
	sc_signal<bool > target_tip;
#else
	sc_signal<sc_bv<NUM_TARGETS> > target_sip;
	sc_signal<sc_bv<NUM_TARGETS> > target_tip;
#endif

	unsigned int rand_seed;

	SC_HAS_PROCESS(Top);

	void dev_access(tlm::tlm_command cmd, uint64_t offset,
			void *buf, unsigned int len)
	{
		unsigned char *buf8 = (unsigned char *) buf;
		sc_time delay = SC_ZERO_TIME;
		tlm::tlm_generic_payload tr;

		tr.set_command(cmd);
		tr.set_address(offset);
		tr.set_data_ptr(buf8);
		tr.set_data_length(len);
		tr.set_streaming_width(len);
		tr.set_dmi_allowed(false);
		tr.set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);

		socket->b_transport(tr, delay);
		assert(tr.get_response_status() == tlm::TLM_OK_RESPONSE);
	}

	uint32_t dev_read32(uint64_t offset)
	{
		uint32_t r;
		assert((offset & 3) == 0);
		dev_access(tlm::TLM_READ_COMMAND, offset, &r, sizeof(r));
		return r;
	}

	void dev_write32(uint64_t offset, uint32_t v)
	{
		assert((offset & 3) == 0);
		dev_access(tlm::TLM_WRITE_COMMAND, offset, &v, sizeof(v));
	}

	void wait_cycles(unsigned int n) {
		while (n--) {
			wait(clk.posedge_event());
		}
	}

	void wait_rand_cycles(void) {
		unsigned int rand_delay = rand_r(&rand_seed) & 0xff;
		wait_cycles(rand_delay);
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

	uint32_t ipi[NUM_TARGETS] = {0};
	uint64_t timecmp[NUM_TARGETS];
	void test(void) {
		uint32_t target_ipi = 0;
		uint64_t addr_ipi = 0;
		uint32_t wdata_ipi = 0;
		uint32_t rdata_ipi = 0;
		uint32_t target_tc = 0;
		uint64_t addr_tc = 0;
		uint64_t wdata_tc = 0;
		uint64_t rdata_tc = 0;
		uint64_t mtime = 0;
		struct {
			bool do_ipi;
			bool do_timecmp;
			bool do_mtime;
		} setup;
		int t;

		wait(rst.negedge_event());
		wait(clk.posedge_event());

		for (t = 0; t < NUM_TARGETS; t++) {
			timecmp[t] = dev_read32(CLINT_BASE_TIMECMP + t * 8 + 4);
			timecmp[t] <<= 32;
			timecmp[t] |= dev_read32(CLINT_BASE_TIMECMP + t * 8);
		}

		while (true) {
			setup.do_ipi = rand_r(&rand_seed) & 1;
			setup.do_timecmp = rand_r(&rand_seed) & 1;
			setup.do_mtime = rand_r(&rand_seed) & 1;

			if (setup.do_ipi) {
				target_ipi = rand_r(&rand_seed) % NUM_TARGETS;
				addr_ipi = target_ipi * 4;
				wdata_ipi = rand_r(&rand_seed);
				ipi[target_ipi] &= ~1;
				ipi[target_ipi] |= wdata_ipi & 1;

				dev_write32(addr_ipi, wdata_ipi);
				printf("do ipi[%d]=%d\n", target_ipi, ipi[target_ipi]);
			}
			if (setup.do_timecmp) {
				target_tc = rand_r(&rand_seed) % NUM_TARGETS;
				addr_tc = CLINT_BASE_TIMECMP + target_ipi * 8;
				wdata_tc = rand_r(&rand_seed);
				wdata_tc <<= 32;
				wdata_tc |= rand_r(&rand_seed);

				timecmp[target_ipi] = wdata_tc;

				dev_write32(addr_tc, wdata_tc);
				dev_write32(addr_tc + 4, wdata_tc >> 32);
				printf("do timecmp[%d]=%lx\n", target_tc, timecmp[target_tc]);
			}

			if (setup.do_mtime) {
				uint64_t wdata;
				uint64_t rdata;

				wdata = rand_r(&rand_seed);
				wdata <<= 32;
				wdata |= rand_r(&rand_seed);

				dev_write32(CLINT_MTIME + 4, 0);
				dev_write32(CLINT_MTIME, 0);

				rdata = dev_read32(CLINT_MTIME + 4);
				rdata <<= 32;
				rdata |= dev_read32(CLINT_MTIME);
				sc_assert(rdata < 0x4);

				dev_write32(CLINT_MTIME + 4, wdata >> 32);
				dev_write32(CLINT_MTIME, wdata);

				printf("do-mtime = %lx rdata=%lx\n", wdata, rdata);
			}

			wait(clk.posedge_event());

			if (setup.do_ipi) {
				bool v;

				rdata_ipi = dev_read32(target_ipi * 4);
				v = target_sip.read()[target_ipi] == '1';
				sc_assert(rdata_ipi == ipi[target_ipi]);
				sc_assert(rdata_ipi == v);
			}
			if (setup.do_timecmp) {
				rdata_tc = dev_read32(CLINT_BASE_TIMECMP + target_tc * 8 + 4);
				rdata_tc <<= 32;
				rdata_tc |= dev_read32(CLINT_BASE_TIMECMP + target_tc * 8);

				sc_assert(rdata_tc == timecmp[target_tc]);
			}

			mtime = dev_read32(CLINT_MTIME + 4);
			mtime <<= 32;
			mtime |= dev_read32(CLINT_MTIME);

			for (t = 0; t < NUM_TARGETS; t++) {
				bool tip = target_tip.read()[t] == '1';

				D(printf("mtime=%lx timecmp[%d]=%lx tip=%d\n",
					mtime, t, timecmp[t], tip));
				sc_assert((mtime >= timecmp[t]) == tip);
			}
		}
	}

	Top(sc_module_name name, sc_time quantum, unsigned int rand_seed) :
		socket("socket"),
		rst("rst"),
		rst_n("rst_n"),
		clk("clk", sc_time(10, SC_NS)),
		tb("tb"),
		axi_signals("axi-signals"),
		tlm_bridge("tlm-bridge"),
		checker("checker", checker_config()),
		target_sip("target_sip"),
		target_tip("target_tip"),
		rand_seed(rand_seed)
	{
		m_qk.set_global_quantum(quantum);

		SC_THREAD(test);
		SC_THREAD(pull_reset);
		SC_METHOD(gen_rst_n);
		sensitive << rst;

		checker.clk(clk);
		checker.resetn(rst_n);
		tlm_bridge.clk(clk);
		tlm_bridge.resetn(rst_n);
		socket(tlm_bridge.tgt_socket);

		axi_signals.connect(tlm_bridge);
		axi_signals.connect(checker);
		axi_signals.connect(tb);

		tb.rst(rst);
		tb.clk(clk);

		tb.target_sip(target_sip);
		tb.target_tip(target_tip);
	}

private:
	tlm_utils::tlm_quantumkeeper m_qk;
};

#include "sc_main.h"
