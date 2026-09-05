#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static inline double uval(uint64_t i){ return 0.25 + (double)((17*i + 3) & 1023u) * 0x1p-10; }
static inline double pval(uint64_t i){ return -0.125 + (double)((29*i + 7) & 1023u) * 0x1p-10; }
static inline double xval(uint64_t i){ return -0.375 + (double)((31*i + 5) & 1023u) * 0x1p-10; }

static double heat(uint64_t n){
  double s=0.0;
  { double u=uval(0); s += u + 0.125*(uval(n-1)-2.0*u+uval(1)); }
  #pragma GCC ivdep
  for(uint64_t i=1;i<n-1;i++){ double u=uval(i); s += u + 0.125*(uval(i-1)-2.0*u+uval(i+1)); }
  { double u=uval(n-1); s += u + 0.125*(uval(n-2)-2.0*u+uval(0)); }
  return s;
}

static double wave(uint64_t n){
  double s=0.0;
  { double u=uval(0); s += 2.0*u-pval(0)+0.0625*(uval(n-1)-2.0*u+uval(1)); }
  #pragma GCC ivdep
  for(uint64_t i=1;i<n-1;i++){ double u=uval(i); s += 2.0*u-pval(i)+0.0625*(uval(i-1)-2.0*u+uval(i+1)); }
  { double u=uval(n-1); s += 2.0*u-pval(n-1)+0.0625*(uval(n-2)-2.0*u+uval(0)); }
  return s;
}

static double sparse(uint64_t n){
  double s=0.0;
  uint64_t j1=3%n,j2=7%n,j3=11%n;
  for(uint64_t i=0;i<n;i++){
    double x=xval(i);
    s += 1.75*x - 0.125*xval(j1) + 0.0625*xval(j2) - 0.03125*xval(j3) + 0.015625*x*x*x;
    j1 += 17; if(j1>=n) j1-=n;
    j2 += 29; if(j2>=n) j2-=n;
    j3 += 43; if(j3>=n) j3-=n;
  }
  return s;
}

int main(int argc,char **argv){
  if(argc!=3) return 2;
  uint64_t n=strtoull(argv[2],0,10);
  double s=!strcmp(argv[1],"heat")?heat(n):!strcmp(argv[1],"wave")?wave(n):sparse(n);
  union{double d;uint64_t u;}v={s};
  printf("checksum=%.17g checksum_bits=0x%016llx\n",s,(unsigned long long)v.u);
  return 0;
}
