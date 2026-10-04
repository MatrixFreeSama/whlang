#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _OPENMP
#include <omp.h>
#endif
int main(int argc,char**argv){
 if(argc!=2)return 2; uint64_t n=strtoull(argv[1],0,10); double sum=0.0;
 #ifdef _OPENMP
 #pragma omp parallel for schedule(static) reduction(+:sum)
 #endif
 for(uint64_t i=0;i<n;i++){
   double x=((double)i-0.5*(double)n)*1e-6;
   double over=50000000.0-12500000000000.0*x*x;
   double dep = over>0.0 ? over/202000000000.0 : 0.0;
   double diss=250000000.0*dep+1000000000.0*dep*dep;
   sum += diss;
 }
 uint64_t b;memcpy(&b,&sum,8);printf("checksum=%.17g\nchecksum_bits=0x%016llx\n",sum,(unsigned long long)b);return 0;
}
