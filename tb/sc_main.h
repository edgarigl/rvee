/*
 * Shared sc_main.
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

#include "verilated_vcd_sc.h"

int sc_main(int argc, char* argv[])
{
	sc_trace_file *trace_fp = NULL;
	unsigned int rand_seed = 0;

	Verilated::commandArgs(argc, argv);
	sc_set_time_resolution(1, SC_PS);

	if (argc > 1) {
		rand_seed = strtoull(argv[1], NULL, 0);
	}

	Top top("top", sc_time((double) 100, SC_NS), rand_seed);
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
