#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
typedef struct { double dtemp, sxx0, local; } Local;
static inline Local local_state(uint64_t i, uint64_t n) {
    const double x=((double)i-0.5*(double)n)*1e-6;
    const double ho=900.0-100000000.0*x*x;
    const double dt=ho>0.0?ho:0.0;
    const double eth=0.000012*dt;
    const double so=0.018-4500.0*x*x;
    const double exx=so>0.0?so:0.0;
    const double eyy=-0.25*exx,ezz=-0.20*exx,gxy=0.15*exx,gyz=0.05*exx,gzx=-0.08*exx;
    const double emxx=exx-eth,emyy=eyy-eth,emzz=ezz-eth,tr=emxx+emyy+emzz;
    const double sx=121153846153.84615*tr+161538461538.46155*emxx;
    const double sy=121153846153.84615*tr+161538461538.46155*emyy;
    const double sz=121153846153.84615*tr+161538461538.46155*emzz;
    const double sxy=80769230769.23077*gxy,syz=80769230769.23077*gyz,szx=80769230769.23077*gzx;
    const double mp=(sx+sy+sz)/3.0;
    const double dxx=sx-mp,dyy=sy-mp,dzz=sz-mp;
    const double seq=sqrt(1.5*(dxx*dxx+dyy*dyy+dzz*dzz+2.0*(sxy*sxy+syz*syz+szx*szx)));
    const double yo=seq-350000000.0;
    const double dl=yo>0.0?yo/243307692307.69232:0.0;
    const double epxx=1.5*dl*dxx/(seq+1.0);
    const double pw=seq*dl,ph=0.9*pw/3744000.0;
    const double en=0.5*(sx*emxx+sy*emyy+sz*emzz+sxy*gxy+syz*gyz+szx*gzx);
    const double dro=en-5000000.0;
    const double dr=dro>0.0?dro*0.00000002:0.0;
    const double d=dr>0.95?0.95:dr;
    Local r={dt,sx,pw+d*en+100000000000.0*epxx*epxx+ph*ph+dt*dt}; return r;
}
int main(int argc,char**argv){
    if(argc!=2)return 2; const uint64_t n=strtoull(argv[1],0,10); if(n<16384)return 3;
    const uint64_t c=n/2, lo=c-3000, hi=c+3000;
    Local a=local_state(lo-1,n), b=local_state(lo,n), cc=local_state(lo+1,n);
    double sum=0.0;
    for(uint64_t i=lo;i<=hi;i++){
        const double divsig=(cc.sxx0-a.sxx0)*500000.0;
        const double dv=1e-9*(divsig/7800.0);
        const double lap=(cc.dtemp-2.0*b.dtemp+a.dtemp)*1e12;
        sum += b.local + 3900.0*dv*dv + lap*lap*1e-18;
        a=b; b=cc; if(i<hi) cc=local_state(i+2,n);
    }
    uint64_t bits;memcpy(&bits,&sum,8);printf("checksum=%.17g\nchecksum_bits=0x%016llx\n",sum,(unsigned long long)bits);return 0;
}
