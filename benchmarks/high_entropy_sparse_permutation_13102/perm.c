#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <omp.h>

static inline double xv(uint64_t i) {
    return -0.5 + (double)((i * UINT64_C(2654435761) + UINT64_C(2246822519)) % UINT64_C(8192)) / 4096.0;
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    uint64_t n = strtoull(argv[1], 0, 10);
    double sum = 0.0;

    #pragma omp parallel for reduction(+:sum) schedule(static)
    for (uint64_t i = 0; i < n; i++) {
        sum += xv((i * 97 + 17) % n)
             - 0.5 * xv((i * 193 + 31) % n)
             + 0.25 * xv((i * 389 + 47) % n)
             - 0.125 * xv((i * 769 + 71) % n)
             + 0.0625 * xv((i * 1543 + 101) % n)
             - 0.03125 * xv((i * 3079 + 131) % n);
    }

    uint64_t bits;
    memcpy(&bits, &sum, 8);
    printf("checksum_bits=0x%016llx\n", (unsigned long long)bits);
    return 0;
}
