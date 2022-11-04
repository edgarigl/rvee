set_param general.maxThreads 16

read_xdc scripts/vivado/rvee-synth.xdc

read_verilog -sv rtl/rvee/rvee-pcgen.sv
read_verilog -sv rtl/rvee/rvee-fetch.sv
read_verilog -sv rtl/rvee/rvee-decode.sv
read_verilog -sv rtl/rvee/rvee-alu.sv
read_verilog -sv rtl/rvee/rvee-exec.sv
read_verilog -sv rtl/rvee/rvee-csr.sv
read_verilog -sv rtl/rvee/rvee-rf.sv
read_verilog -sv rtl/rvee/rvee-mem.sv
read_verilog -sv rtl/rvee/rvee.sv
read_verilog -sv rtl/plic/plic.sv
#synth_design -part xczu9eg-ffvb1156-2-e -top rvee_core -include_dirs rtl/
#synth_design -retiming -part xc7k70t-fbg676 -top rvee_core -include_dirs rtl/

synth_design -directive PerformanceOptimized -retiming -part xczu9eg-ffvb1156-2-e -top rvee_core -include_dirs rtl/
opt_design -aggressive_remap
place_design
phys_opt_design
route_design

#opt_design -sweep -propconst -resynth_seq_area
#opt_design -directive ExploreSequentialArea

report_utilization
report_timing
write_verilog -force scripts/vivado/out.v
