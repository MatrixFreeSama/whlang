#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void band(uint64_t n,int64_t center,double *sum){
 const double dx=1e-8,R=0.02,w2=4e-10,sigma=0.072;
 int64_t lo=center-2002,hi=center+2002;
 if(lo<0)lo=0; if(hi>(int64_t)n)hi=(int64_t)n;
 for(int64_t ii=lo;ii<hi;ii++){
   uint64_t i=(uint64_t)ii; double x=((double)i-0.5*(double)n)*dx;
   double d = center < (int64_t)(n/2) ? x+R : x-R;
   double q=d*d; if(q<w2)*sum += sigma*(1.0-q/w2);
 }
}
int main(int argc,char**argv){if(argc!=2)return 2;uint64_t n=strtoull(argv[1],0,10);double sum=0.0;int64_t mid=(int64_t)(n/2);band(n,mid-2000000,&sum);band(n,mid+2000000,&sum);uint64_t b;memcpy(&b,&sum,8);printf("checksum=%.17g\nchecksum_bits=0x%016llx\n",sum,(unsigned long long)b);return 0;}
