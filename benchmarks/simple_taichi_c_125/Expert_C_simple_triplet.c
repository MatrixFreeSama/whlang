#define _GNU_SOURCE
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum bench_mode { HEAT=0, WAVE=1, SPARSE=2 };
typedef struct { uint64_t n, lo, hi; int mode; double sum; } job_t;

static inline double uval(uint64_t i){ return 0.25 + (double)((17*i + 3) & 1023u) * 0x1p-10; }
static inline double pval(uint64_t i){ return -0.125 + (double)((29*i + 7) & 1023u) * 0x1p-10; }
static inline double xval(uint64_t i){ return -0.375 + (double)((31*i + 5) & 1023u) * 0x1p-10; }

static double heat_range(uint64_t lo,uint64_t hi,uint64_t n){
  double s=0.0;
  if(lo==0 && hi){ double u=uval(0); s += u + 0.125*(uval(n-1)-2.0*u+uval(1)); lo=1; }
  uint64_t e=hi < n-1 ? hi : n-1;
  #pragma GCC ivdep
  for(uint64_t i=lo;i<e;i++){ double u=uval(i); s += u + 0.125*(uval(i-1)-2.0*u+uval(i+1)); }
  if(hi==n && lo<=n-1){ double u=uval(n-1); s += u + 0.125*(uval(n-2)-2.0*u+uval(0)); }
  return s;
}

static double wave_range(uint64_t lo,uint64_t hi,uint64_t n){
  double s=0.0;
  if(lo==0 && hi){ double u=uval(0); s += 2.0*u-pval(0)+0.0625*(uval(n-1)-2.0*u+uval(1)); lo=1; }
  uint64_t e=hi < n-1 ? hi : n-1;
  #pragma GCC ivdep
  for(uint64_t i=lo;i<e;i++){ double u=uval(i); s += 2.0*u-pval(i)+0.0625*(uval(i-1)-2.0*u+uval(i+1)); }
  if(hi==n && lo<=n-1){ double u=uval(n-1); s += 2.0*u-pval(n-1)+0.0625*(uval(n-2)-2.0*u+uval(0)); }
  return s;
}

static double sparse_range(uint64_t lo,uint64_t hi,uint64_t n){
  double s=0.0;
  if(n<=43){
    for(uint64_t i=lo;i<hi;i++){
      double x=xval(i);
      s += 1.75*x - 0.125*xval((17*i+3)%n) + 0.0625*xval((29*i+7)%n) - 0.03125*xval((43*i+11)%n) + 0.015625*x*x*x;
    }
    return s;
  }
  uint64_t j1=(17*lo+3)%n, j2=(29*lo+7)%n, j3=(43*lo+11)%n;
  for(uint64_t i=lo;i<hi;i++){
    double x=xval(i);
    s += 1.75*x - 0.125*xval(j1) + 0.0625*xval(j2) - 0.03125*xval(j3) + 0.015625*x*x*x;
    j1 += 17; if(j1>=n) j1-=n;
    j2 += 29; if(j2>=n) j2-=n;
    j3 += 43; if(j3>=n) j3-=n;
  }
  return s;
}

static void *worker(void *vp){
  job_t *j=(job_t*)vp;
  j->sum = j->mode==HEAT ? heat_range(j->lo,j->hi,j->n) : j->mode==WAVE ? wave_range(j->lo,j->hi,j->n) : sparse_range(j->lo,j->hi,j->n);
  return NULL;
}

int main(int argc,char**argv){
  if(argc!=4){fprintf(stderr,"usage: %s heat|wave|sparse N Q\n",argv[0]); return 2;}
  int mode=!strcmp(argv[1],"heat")?HEAT:!strcmp(argv[1],"wave")?WAVE:!strcmp(argv[1],"sparse")?SPARSE:-1;
  uint64_t n=strtoull(argv[2],0,10); int q=atoi(argv[3]);
  if(mode<0||q<1||q>64||n<4) return 2;
  job_t *jobs=calloc((size_t)q,sizeof(*jobs)); pthread_t *th=calloc((size_t)q,sizeof(*th));
  for(int t=0;t<q;t++){
    uint64_t lo=(n*(uint64_t)t)/(uint64_t)q, hi=(n*(uint64_t)(t+1))/(uint64_t)q;
    jobs[t]=(job_t){n,lo,hi,mode,0};
    if(q>1 && pthread_create(&th[t],0,worker,&jobs[t])) return 3;
  }
  if(q==1) worker(&jobs[0]); else for(int t=0;t<q;t++) pthread_join(th[t],0);
  double sum=0.0; for(int t=0;t<q;t++) sum += jobs[t].sum;
  union{double d;uint64_t u;}v={sum};
  printf("checksum=%.17g checksum_bits=0x%016llx\n",sum,(unsigned long long)v.u);
  free(jobs); free(th); return 0;
}
