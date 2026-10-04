#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _OPENMP
#include <omp.h>
#endif
int main(int argc,char**argv){
 if(argc!=2)return 2; uint64_t n=strtoull(argv[1],0,10);
 const double dx=1e-8,R=0.02,w2=4e-10,sigma=0.072; double sum=0.0;
 #ifdef _OPENMP
 #pragma omp parallel for schedule(static) reduction(+:sum)
 #endif
 for(uint64_t i=0;i<n;i++){
   double x=((double)i-0.5*(double)n)*dx;
   double dl=x+R, dr=x-R;
   double ql=dl*dl, qr=dr*dr;
   if(ql<w2) sum += sigma*(1.0-ql/w2);
   if(qr<w2) sum += sigma*(1.0-qr/w2);
 }
 uint64_t b;memcpy(&b,&sum,8);printf("checksum=%.17g\nchecksum_bits=0x%016llx\n",sum,(unsigned long long)b);return 0;
}
