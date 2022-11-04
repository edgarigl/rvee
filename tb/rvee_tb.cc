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
#include "Vrvee_tb.h"
#include "verilated_vcd_sc.h"

#include "test-modules/signals-axilite.h"
#include "tlm-bridges/axilite2tlm-bridge.h"
#include "tlm-bridges/tlm2axilite-bridge.h"
#include "checkers/pc-axilite.h"

#include "soc/interconnect/iconnect.h"
#include "tests/test-modules/memory.h"

#define RAM_SIZE (1 * 1024 * 1024)

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

	sc_signal<sc_bv<32> > resetv;
	Vrvee_tb tb;

	iconnect<2, 3> ic;

	AXILiteSignals<AWIDTH, DWIDTH> fetch_signals;
	axilite2tlm_bridge<AWIDTH, DWIDTH> fetch_bridge;
	AXILiteProtocolChecker<AWIDTH, DWIDTH > fetch_checker;

	AXILiteSignals<AWIDTH, DWIDTH> mem_signals;
	axilite2tlm_bridge<AWIDTH, DWIDTH> mem_bridge;
	AXILiteProtocolChecker<AWIDTH, DWIDTH > mem_checker;

	AXILiteSignals<AWIDTH, DWIDTH> clint_signals;
	tlm2axilite_bridge<AWIDTH, DWIDTH> clint_bridge;
	AXILiteProtocolChecker<AWIDTH, DWIDTH > clint_checker;

	uint8_t *rambuf;
	memory ram;

	SC_HAS_PROCESS(Top);

	void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
		unsigned int len = trans.get_data_length();
		uint64_t addr = trans.get_address();
		uint8_t *ptr = trans.get_data_ptr();

		if (len > 8) {
			trans.set_response_status(tlm::TLM_GENERIC_ERROR_RESPONSE);
		}

		if (trans.is_read()) {
			uint32_t v = 0;

			switch (addr) {
			case 0x2c:
				v |= 8;	// Tempty
				break;
			default:
				break;
			}
			memset(ptr, 0, len);
			memcpy(ptr, &v, len > sizeof v ? sizeof v : len);
		} else {
			uint64_t c = 0;

			memcpy(&c, ptr, len);

			switch (addr) {
			case 0x30:
				printf("%c", (unsigned char) c & 0xff);
				break;
			case 0x104:
				printf("HEX: 0x%8.8lx\n", c);
				break;
			case 0x108:
				printf("EXIT %ld\n", c);
				exit(c);
				break;
			}
		}
	}

	void pull_reset(void) {
		/* Pull the reset signal.  */

		resetv.write(0x0);
		rst.write(true);
		wait(clk.negedge_event());
		wait(clk.posedge_event());
		rst.write(false);
	}

	void gen_rst_n(void) {
		rst_n.write(!rst.read());
	}

	Top(sc_module_name name, sc_time quantum, const char *ramfile) :
		target_socket("mock-uart-socket"),
		rst("rst"),
		rst_n("rst_n"),
		clk("clk", sc_time(10, SC_NS)),
		resetv("resetv"),
		tb("tb"),
		ic("ic"),
		fetch_signals("fetch-signals"),
		fetch_bridge("fetch-bridge"),
		fetch_checker("fetch-checker", checker_config()),
		mem_signals("mem-signals"),
		mem_bridge("mem-bridge"),
		mem_checker("mem-checker", checker_config()),
		clint_signals("clint-signals"),
		clint_bridge("clint-bridge"),
		clint_checker("clint-checker", checker_config()),
		rambuf(new uint8_t [RAM_SIZE]),
		ram("ram", sc_time(1, SC_NS), RAM_SIZE, rambuf)
	{
		m_qk.set_global_quantum(quantum);

		SC_THREAD(pull_reset);
		SC_METHOD(gen_rst_n);
		sensitive << rst;

		target_socket.register_b_transport(this, &Top::b_transport);

		tb.aresetn(rst_n);
		tb.aclk(clk);
		tb.resetv(resetv);

		fetch_checker.clk(clk);
		fetch_checker.resetn(rst_n);

		fetch_bridge.clk(clk);
		fetch_bridge.resetn(rst_n);
		fetch_bridge.socket(*(ic.t_sk[0]));

		fetch_signals.connect(fetch_bridge);
		fetch_signals.connect(fetch_checker);
		fetch_signals.connect(tb, "m00_");

		mem_checker.clk(clk);
		mem_checker.resetn(rst_n);

		mem_bridge.clk(clk);
		mem_bridge.resetn(rst_n);
		mem_bridge.socket(*(ic.t_sk[1]));

		mem_signals.connect(mem_bridge);
		mem_signals.connect(mem_checker);
		mem_signals.connect(tb, "m01_");

		clint_checker.clk(clk);
		clint_checker.resetn(rst_n);

		clint_bridge.clk(clk);
		clint_bridge.resetn(rst_n);

		clint_signals.connect(clint_bridge);
		clint_signals.connect(clint_checker);
		clint_signals.connect(tb, "s00_");

		ic.memmap(0xff000000ULL, 0x200 - 1, ADDRMODE_RELATIVE, -1, target_socket);
		ic.memmap(0xa0000000ULL, 0x10000 - 1, ADDRMODE_RELATIVE, -1,
			  clint_bridge.tgt_socket);
		ic.memmap(0x00000000ULL, RAM_SIZE - 1, ADDRMODE_RELATIVE, -1, ram.socket);

		memset(rambuf, 0xff, RAM_SIZE);
		if (ramfile) {
			FILE *fp = fopen(ramfile, "rb");
			size_t l = 0;

			if (fp)
				l = fread(rambuf, 1, RAM_SIZE, fp);
			if (!fp || ferror(fp)) {
				perror(ramfile);
				exit(EXIT_FAILURE);
			}
			fclose(fp);

			printf("Loaded %s %zu bytes to RAM\n", ramfile, l);
		}
	}

private:
	tlm_utils::tlm_quantumkeeper m_qk;
};

#include "verilated_vcd_sc.h"

int sc_main(int argc, char* argv[])
{
	sc_trace_file *trace_fp = NULL;
	const char *ramfile = NULL;

	Verilated::commandArgs(argc, argv);
	sc_set_time_resolution(1, SC_PS);

	if (argc >= 2) {
		ramfile = argv[1];
	}

	Top top("top", sc_time((double) 100, SC_NS), ramfile);
#if VM_TRACE
	Verilated::traceEverOn(true);
	// If verilator was invoked with --trace argument,
	// and if at run time passed the +trace argument, turn on tracing
	VerilatedVcdSc *tfp = NULL;
	const char* flag = Verilated::commandArgsPlusMatch("trace");
	if (flag && !strcmp(flag, "+trace")) {
		char fname[256];
		tfp = new VerilatedVcdSc;
		top.tb.trace(tfp, 100);

		snprintf(fname, sizeof fname, "%s-verilator.vcd", argv[0]);
		tfp->open(fname);

		trace_fp = sc_create_vcd_trace_file(argv[0]);
		trace(trace_fp, top, top.name());
	}
#endif
	sc_start();
	if (trace_fp) {
		sc_close_vcd_trace_file(trace_fp);
	}

#if VM_TRACE
	delete tfp;
#endif
	return 0;
}
