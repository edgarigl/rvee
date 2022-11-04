`ifndef __RVEE_CSR_REGS_VH__
`define __RVEE_CSR_REGS_VH__

// Since Yosys doesn't handle enums very well yet, we use defines.
// This contains a list of all CSRs that we in any way deal with.

// Machine TRAP Setup
`define CSR_MSTATUS				12'h300
`define CSR_MISA				12'h301
`define CSR_MEDELEG				12'h302
`define CSR_MIDELEG				12'h303
`define CSR_MIE					12'h304
`define CSR_MTVEC				12'h305
`define CSR_MCOUNTEREN				12'h306
`define CSR_MSTATUSH				12'h310

// Machine TRAP Handling
`define CSR_MSCRATCH				12'h340
`define CSR_MEPC				12'h341
`define CSR_MCAUSE				12'h342
`define   MCAUSE_INSN_MISALIGNED		31'd0
`define   MCAUSE_INSN_ACCESS_FAULT		31'd1
`define   MCAUSE_ILLEGAL_INSN			31'd2
`define   MCAUSE_BREAKPOINT			31'd3
`define   MCAUSE_LOAD_ADDRESS_MISALIGNED	31'd4
`define   MCAUSE_LOAD_ADDRESS_FAULT		31'd5
`define   MCAUSE_STORE_ADDRESS_MISALIGNED	31'd6
`define   MCAUSE_STORE_ADDRESS_FAULT		31'd7
`define   MCAUSE_ECALL_U			31'd8
`define   MCAUSE_ECALL_S			31'd9
/* Reserved 10.  */
`define   MCAUSE_ECALL_M			31'd11
`define   MCAUSE_INSN_PAGE_FAULT		31'd12
`define   MCAUSE_LOAD_PAGE_FAULT		31'd13
/* Reserved 14.  */
`define   MCAUSE_STORE_PAGE_FAULT		31'd15

`define CSR_MTVAL				12'h343
`define CSR_MIP					12'h344
`define CSR_MTINST				12'h34a
`define CSR_MTVAL2				12'h34b

// Machine Counters/Timers
`define CSR_MCYCLE				12'hb00
`define CSR_MINSTRET				12'hb02
`define CSR_MCYCLEH				12'hb80
`define CSR_MINSTRETH				12'hb82

// Machine Counter Setup
`define CSR_MCOUNTINHIBIT			12'h320
`endif
