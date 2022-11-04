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
#include "Vplic_tb.h"
#include "verilated_vcd_sc.h"

#include "test-modules/signals-axilite.h"
#include "tlm-bridges/tlm2axilite-bridge.h"
#include "checkers/pc-axilite.h"

#define D(x)

#define AWIDTH 32
#define DWIDTH 32
#define NUM_SOURCES 128
#define NUM_TARGETS 128
#define MAX_PRIO 3

#define PLIC_BASE_PENDING 0x1000
#define PLIC_BASE_ENABLE  0x2000
#define PLIC_BASE_CONTEXT 0x200000

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

	Vplic_tb tb;

	AXILiteSignals<AWIDTH, DWIDTH> axi_signals;
	tlm2axilite_bridge<AWIDTH, DWIDTH> tlm_bridge;
	AXILiteProtocolChecker<AWIDTH, DWIDTH > checker;

	sc_signal<sc_bv<NUM_SOURCES> > source;
#if NUM_TARGETS == 1
	sc_signal<bool > target;
#else
	sc_signal<sc_bv<NUM_TARGETS> > target;
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

	bool enable[NUM_TARGETS][NUM_SOURCES] = {0};
	bool claim[NUM_SOURCES] = {0};
	unsigned int claim_target[NUM_SOURCES] = {0};
	unsigned int prio[NUM_SOURCES] = {0};
	unsigned int target_prio[NUM_TARGETS] = {0};
	unsigned int irq_id[NUM_TARGETS];

	bool is_pending(unsigned int irq) {
		sc_bv<NUM_SOURCES> bv;
		bool v;

		bv = source.read();
		v = bv[irq] == '1';
		v &= !claim[irq];
		return v;
	}

	void update_targets(void) {
		unsigned int i, t;
		unsigned int irq_prio;

		for (t = 0; t < NUM_TARGETS; t++) {
			irq_id[t] = 0;
			irq_prio = target_prio[t];
			for (i = 0; i < NUM_SOURCES; i++) {
				if (is_pending(i) && enable[t][i] && prio[i] > irq_prio) {
					irq_id[t] = i;
					irq_prio = prio[i];
				}
			}
			D(printf("SC: irq_id[%d]=%d prio=%d\n",
				t, irq_id[t], target_prio[t]));
		}
	}

	void test(void) {
		unsigned int src = 0, src_flip = 0, src_complete = 0;
		unsigned int target_en = 0, target_claim = 0, target_complete = 0;
		unsigned int target_tp = 0;
		uint64_t addr = 0, addr_claim = 0, addr_complete = 0, addr_tp = 0;
		uint32_t wdata = 0;
		uint32_t rdata = 0;
		struct {
			bool do_prio;
			bool do_enable;
			bool do_source;
			bool do_target_prio;
			bool do_claim;
			bool do_complete;
		} setup;
		int i, t;
		sc_bv<NUM_SOURCES> bv;

		wait(rst.negedge_event());
		wait(clk.posedge_event());

		while (true) {
			setup.do_prio = rand_r(&rand_seed) & 1;
			setup.do_enable = rand_r(&rand_seed) & 1;
			setup.do_source = rand_r(&rand_seed) & 1;
			setup.do_target_prio = rand_r(&rand_seed) & 1;
			setup.do_claim = rand_r(&rand_seed) & 1;
			setup.do_complete = rand_r(&rand_seed) & 1;

			if (setup.do_prio) {
				src = rand_r(&rand_seed) % NUM_SOURCES;
				addr = src * 4;
				wdata = rand_r(&rand_seed);
				dev_write32(addr, wdata);
				prio[src] = wdata & MAX_PRIO;

				printf("do_prio: prio[%d]=%x addr=%lx wdata=%x\n",
					src, prio[src], addr, wdata);
			} else if (setup.do_enable) {
				target_en = rand_r(&rand_seed) % NUM_TARGETS;
				src = rand_r(&rand_seed) % NUM_SOURCES;
				src /= 32;
				addr = src * 4;
				addr |= target_en << 7;
				addr += PLIC_BASE_ENABLE;
				src *= 32;

				wdata = rand_r(&rand_seed);

				dev_write32(addr, wdata);
				for (i = 0; i < 32; i++) {
					if (src + i >= NUM_SOURCES)
						break;

					enable[target_en][src + i] = !!(wdata & (1ULL << i));
					printf("enable[%d] = %d\n",
						src + i, enable[target_en][src + i]);
				}

				printf("do_enable: src=%d target=%x addr=%lx wdata=%x\n",
					src, target_en, addr, wdata);
			}

			if (setup.do_source) {
				src_flip = rand_r(&rand_seed) % NUM_SOURCES;

				if (src_flip == 0) {
					// SRC zero is reserved.
					src_flip |= 1;
				}

				bv = source.read();
				bv[src_flip] ^= '1';

				printf("SRC: %d\n", src_flip);
				source.write(bv);
				wait(clk.posedge_event());
			}

			if (setup.do_target_prio) {
				uint32_t wdata_tp;

				target_tp = rand_r(&rand_seed) % NUM_TARGETS;
				addr_tp = PLIC_BASE_CONTEXT + target_tp * 0x1000 + 0;
				wdata_tp = rand_r(&rand_seed);
				dev_write32(addr_tp, wdata_tp);

				printf("target-prio[%d] = %x\n", target_tp, wdata_tp);
				target_prio[target_tp] = wdata_tp & MAX_PRIO;
			}

			if (setup.do_claim) {
				target_claim = rand_r(&rand_seed) % NUM_TARGETS;
				addr_claim = PLIC_BASE_CONTEXT + target_claim * 0x1000 + 4;

				update_targets();
				rdata = dev_read32(addr_claim);

				printf("claimed target[%d]=%d %d\n",
					target_claim, rdata, irq_id[target_claim]);
				sc_assert(irq_id[target_claim] == rdata);

				claim[rdata] = 1;
				claim_target[rdata] = target_claim;
			}

			if (setup.do_complete) {
				src_complete = rand_r(&rand_seed) % NUM_SOURCES;
				target_complete = rand_r(&rand_seed) % NUM_TARGETS;
				addr_complete = PLIC_BASE_CONTEXT + target_complete * 0x1000 + 4;
				dev_write32(addr_complete, src_complete);

				printf("completed %d\n", src_complete);
				if (claim_target[src_complete] == target_complete) {
					claim[src_complete] = 0;
				} else {
					printf("COMPLETE for non claimed source\n");
				}
			}

			if (setup.do_prio || setup.do_enable) {
				rdata = dev_read32(addr);
				printf("rdata=%x\n", rdata);

				if (setup.do_prio) {
					sc_assert(rdata == prio[src]);
				} else if (setup.do_enable) {
					for (i = 0; i < 32; i++) {
						if (src + i >= NUM_SOURCES)
							break;
						printf("enable[%d]=%d %d\n", src + i,
							enable[target_en][src + i], !!(rdata & (1ULL << i)));
						sc_assert(enable[target_en][src + i] == !!(rdata & (1ULL << i)));
					}
				}
			}
			if (setup.do_source) {
				bool v;

				rdata = dev_read32(PLIC_BASE_PENDING + (src_flip / 32) * 4);
				bv = source.read();
				v = bv[src_flip] == '1';
				v &= !claim[src_flip];
				i = src_flip % 32;

				printf("pending[%d]= %d src=%d claim=%d %d\n", src_flip,
					v, (bv[src_flip] == '1'), claim[src_flip],
					!!(rdata & (1ULL << i)));
				sc_assert(v == !!(rdata & (1ULL << i)));
			}

			// Need to do these checks after doing prio/enable updates.
			wait(clk.posedge_event());
			update_targets();

			for (t = 0; t < NUM_TARGETS; t++) {
				D(printf("irq_id[%d]=%d target=%d\n",
					t, irq_id[t], target.read()[t] == '1'));
				sc_assert(!!irq_id[t] == (target.read()[t] == '1'));
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
		source("source"),
		target("target"),
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

		tb.source(source);
		tb.target(target);
	}

private:
	tlm_utils::tlm_quantumkeeper m_qk;
};

#include "sc_main.h"
