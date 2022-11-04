# Vivado Pain Points

## IP packaging

I tried using the IP Packager but it would not work with SystemVerilog
interfaces. It complains that the interfaces need to be named *master*
or *slave*. This happened despite using a plain Verilog wrapper, the
interfaces in question where internal.

I also tried using Yosys to convert RVee into plain verilog but couldn't
make progress.

## RTL as a module

Failed.

## Include-headers

It seems to be quite hard to get Vivado to consistently apply header-file
search paths. the Add files has one setting, simulation another and
synthesis yet another.
