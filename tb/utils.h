
static inline void rand_buf_r(unsigned int *seedp, void *buf, size_t n) {
	size_t i;
	int r;

	for (i = 0; i < n; i += sizeof r) {
		size_t space = n - i;

		r = rand_r(seedp);
		memcpy((char *)buf + i, &r, sizeof r <= space ? sizeof r : space);
	}
}
