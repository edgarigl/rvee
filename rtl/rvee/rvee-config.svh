// Various configuration options for the RVee core.
`ifndef RVEE_CONFIG_SVH_
`define RVEE_CONFIG_SVH

// 64 or 32-bit core.
// At the moment, only 32-bit cores are supported.
`define XLEN 32

// Enable CSR access
`define RVEE_ZICSR

// MEM_REGFW
//
// If defined, it enables register forwarding between the
// flopped input of the MEM stage back into the
// DECODE stage's register reads.
//
// If not defined, the decoder will automatically inject
// bubbles into the pipeline when a hazard is detected.
//
// This option should be set to 1 or 0.
// 
`define RVEE_CONFIG_MEM_REGFW 1

//`define RVEE_CONFIG_MEM_BPU

// DEBUG enables
//`define DEBUG_FETCH
//`define DEBUG_FETCH_JMP
//`define DEBUG_DECODE
//`define DEBUG_CSR
//`define DEBUG_EXEC
//`define DEBUG_MEM
//`define DEBUG_MEM_LD
//`define DEBUG_MEM_ST
//`define DEBUG_RF
`endif
