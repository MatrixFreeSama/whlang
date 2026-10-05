#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

typedef struct { double dtemp, sxx0, local; } Local;

static inline Local local_state(uint64_t i, uint64_t n) {
    const double x = ((double)i - 0.5*(double)n) * 1.0e-6;
    const double heat_over = 900.0 - 100000000.0*x*x;
    const double dtemp = heat_over > 0.0 ? heat_over : 0.0;
    const double eth = 0.000012*dtemp;
    const double strain_over = 0.018 - 4500.0*x*x;
    const double exx = strain_over > 0.0 ? strain_over : 0.0;
    const double eyy = -0.25*exx;
    const double ezz = -0.20*exx;
    const double gxy = 0.15*exx;
    const double gyz = 0.05*exx;
    const double gzx = -0.08*exx;
    const double emxx = exx - eth;
    const double emyy = eyy - eth;
    const double emzz = ezz - eth;
    const double tr = emxx + emyy + emzz;
    const double sxx0 = 121153846153.84615*tr + 161538461538.46155*emxx;
    const double syy0 = 121153846153.84615*tr + 161538461538.46155*emyy;
    const double szz0 = 121153846153.84615*tr + 161538461538.46155*emzz;
    const double sxy0 = 80769230769.23077*gxy;
    const double syz0 = 80769230769.23077*gyz;
    const double szx0 = 80769230769.23077*gzx;
    const double meanp = (sxx0 + syy0 + szz0)/3.0;
    const double dxx = sxx0 - meanp;
    const double dyy = syy0 - meanp;
    const double dzz = szz0 - meanp;
    const double j2q = 1.5*(dxx*dxx + dyy*dyy + dzz*dzz + 2.0*(sxy0*sxy0 + syz0*syz0 + szx0*szx0));
    const double seq = sqrt(j2q);
    const double yield_over = seq - 350000000.0;
    const double dlambda = yield_over > 0.0 ? yield_over/243307692307.69232 : 0.0;
    const double epxx = 1.5*dlambda*dxx/(seq + 1.0);
    const double plastic_work = seq*dlambda;
    const double plastic_heat = 0.9*plastic_work/3744000.0;
    const double energy = 0.5*(sxx0*emxx + syy0*emyy + szz0*emzz + sxy0*gxy + syz0*gyz + szx0*gzx);
    const double damage_over = energy - 5000000.0;
    const double damage_raw = damage_over > 0.0 ? damage_over*0.00000002 : 0.0;
    const double damage = damage_raw > 0.95 ? 0.95 : damage_raw;
    const double local = plastic_work + damage*energy + 100000000000.0*epxx*epxx + plastic_heat*plastic_heat + dtemp*dtemp;
    Local r = {dtemp, sxx0, local};
    return r;
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    const uint64_t n = strtoull(argv[1], 0, 10);
    if (n < 16384) return 3;
    double *dtemp = 0, *sxx0 = 0, *local = 0;
    if (posix_memalign((void**)&dtemp, 64, n*sizeof(double)) ||
        posix_memalign((void**)&sxx0, 64, n*sizeof(double)) ||
        posix_memalign((void**)&local, 64, n*sizeof(double))) return 4;
    for (uint64_t i=0;i<n;i++) {
        Local r = local_state(i,n);
        dtemp[i]=r.dtemp; sxx0[i]=r.sxx0; local[i]=r.local;
    }
    double sum = 0.0;
    for (uint64_t i=0;i<n;i++) {
        const uint64_t im = i ? i-1 : n-1;
        const uint64_t ip = i+1 == n ? 0 : i+1;
        const double divsig = (sxx0[ip]-sxx0[im])*500000.0;
        const double accel = divsig/7800.0;
        const double dv = 1.0e-9*accel;
        const double laptemp = (dtemp[ip]-2.0*dtemp[i]+dtemp[im])*1.0e12;
        sum += local[i] + 3900.0*dv*dv + laptemp*laptemp*1.0e-18;
    }
    uint64_t bits; memcpy(&bits,&sum,8);
    printf("checksum=%.17g\nchecksum_bits=0x%016llx\n",sum,(unsigned long long)bits);
    free(dtemp); free(sxx0); free(local);
    return 0;
}
