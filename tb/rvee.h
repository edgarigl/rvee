#define AWIDTH 32
#define DWIDTH 32

#ifndef XLEN
#define XLEN 32
#endif

#if XLEN == 32
#define XLEN_MAX UINT32_MAX
#define XLEN_CLOG2 5
typedef uint32_t xlen_t;
typedef int32_t sxlen_t;
#else
#define XLEN_MAX UINT64_MAX
#define XLEN_CLOG2 6
typedef uint64_t xlen_t;
typedef int64_t sxlen_t;
#endif

#define XLEN_CLOG2_MASK (XLEN - 1)

typedef enum {
	LUI_TYPE = 0x37,
	AUIPC_TYPE = 0x17,
	JAL_TYPE = 0x6f,
	BCC_TYPE = 0x63,
	S_TYPE = 0x23,
	I_JALR_TYPE = 0x67,
	I_LD_TYPE = 0x3,
	I_ALU_TYPE = 0x13,
	R_ALU_TYPE = 0x33,
} rv_opcode_t;

typedef enum {
	ALU_ADD  = 0,
	ALU_SLL  = 1,
	ALU_SLT  = 2,
	ALU_SLTU = 3,
	ALU_XOR  = 4,
	ALU_SRL  = 5,
	ALU_OR   = 6,
	ALU_AND  = 7
} rv_alu_op_t;

typedef enum {
	CC_EQ  = 0,
	CC_NE  = 1,
	CC_LT  = 4,
	CC_GE  = 5,
	CC_LTU = 6,
	CC_GEU = 7,
} rv_cc_t;

xlen_t rv_sext(unsigned int w, uint32_t v)
{
	xlen_t r = v;

	if (r & (1ULL << (w - 1))) {
		r |= ~((1ULL << w) - 1);
	}
	return r;
}

static inline uint32_t gen_jal_imm(uint32_t v) {
	uint32_t imm;

	imm = (v >> 12) & 0xff;
	imm |= ((v >> 11) & 1) << 8;
	imm |= ((v >> 1) & 0x3ff) << 9;
	imm |= ((v >> 20) & 1) << 19;
	return imm;
}

static inline uint32_t gen_bcc_imm(uint32_t v) {
	uint32_t imm;

	imm = ((v >> 11) & 1) << 7;
	imm |= ((v >> 1) & 0xf) << 8;
	imm |= ((v >> 5) & 0x3f) << 25;
	imm |= ((v >> 12) & 1) << 31;
	return imm;
}

static inline uint32_t rvee_encode_s(
				unsigned int rs1,
				unsigned int rs2,
				unsigned int size,
				uint32_t imm) {
	uint32_t iw;

	assert((imm & ~0xfff) == 0);
	assert(size <= 2);
	iw = S_TYPE |
		(imm & 0x1f) << 7 |
		size << 12 |
		rs1 << 15 |
		rs2 << 20 |
		(imm >> 5) << 25;
	return iw;
}

static inline uint32_t rvee_encode_bcc(unsigned int rs1,
				unsigned int rs2,
				rv_cc_t cc,
				uint32_t imm) {
	uint32_t iw;

	assert((imm & 1) == 0);
	assert((imm & ~0x1fff) == 0);
	assert((cc & ~7) == 0);
	assert(cc != 2 && cc != 3);
	imm = gen_bcc_imm(imm);
	iw = BCC_TYPE |
		cc << 12 |
		rs1 << 15 |
		rs2 << 20 |
		imm;
	return iw;
}

static inline uint32_t rvee_encode_jal(unsigned int rd,
				       uint32_t imm) {
	uint32_t iw;

	assert((imm & 1) == 0);
	assert((imm & ~0x1fffff) == 0);
	imm = gen_jal_imm(imm);
	iw = JAL_TYPE | rd << 7 | imm << 12;
	return iw;
}

static inline uint32_t rvee_encode_u(rv_opcode_t opcode,
				unsigned int rd,
				uint32_t imm) {
	uint32_t iw;

	// We expect imm to already be shifted up (since it's upper).
	assert((imm & ((1U << 12) - 1)) == 0);
	iw = opcode | rd << 7 | imm;
	return iw;
}

static inline uint32_t rvee_encode_r(rv_alu_op_t op,
				unsigned int rd,
				unsigned int rs1,
				unsigned int rs2,
				bool c) {
	uint32_t iw;

	assert(!c || (op == ALU_ADD || op == ALU_SRL));

	iw = R_ALU_TYPE |
		rd << 7 |
		(unsigned int)op << 12 |
		rs1 << 15 |
		rs2 << 20 |
		(unsigned int)c << 30;
	return iw;
}

static inline uint32_t rvee_encode_i(rv_opcode_t opcode,
				rv_alu_op_t op,
				unsigned int rd,
				unsigned int rs1,
				uint32_t imm) {
	uint32_t iw;

	assert((imm & (~((1U << 12) - 1))) == 0);
	iw = opcode |
		rd << 7 |
		op << 12 |
		imm << 20;
	return iw;
}
