#define _GNU_SOURCE
#include <immintrin.h>
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef EXECUTORS
#define EXECUTORS 1
#endif
#define CHUNK 65536ULL
#define MAX_CHUNKS 1526
static uint64_t N;
static double partials[MAX_CHUNKS] __attribute__((aligned(64)));
typedef struct{int e;} Arg;
static inline double vf_scalar(uint64_t i){return -0.5+(double)((i*29ULL+7ULL)&1023ULL)*(1.0/1024.0);} 
static inline double slot_scalar(uint64_t i){double u=.25+(double)((i*17ULL+3ULL)&1023ULL)*(1.0/1024.0);double v=vf_scalar(i);uint64_t im1=i?i-1:N-1,ip1=i+1==N?0:i+1;return (2.0+.375*u*u)*v-vf_scalar(im1)-vf_scalar(ip1);} 
static inline void add_carrier(double a[4], uint64_t rel, double x){a[rel&3]+=x;}
static inline double chunk_sum(uint64_t k){
 uint64_t s=k*CHUNK,end=s+CHUNK;if(end>N)end=N; double a[4]={0,0,0,0}; uint64_t i=s;
 if(i==0 && i<end){add_carrier(a,i-s,slot_scalar(i));i++;}
 uint64_t interior_end=end; if(interior_end==N && interior_end>0) interior_end=N-1;
 const __m512i mask=_mm512_set1_epi64(1023), plus136=_mm512_set1_epi64(136), plus232=_mm512_set1_epi64(232), plus29=_mm512_set1_epi64(29), sub29=_mm512_set1_epi64(-29LL);
 const __m512d inv=_mm512_set1_pd(1.0/1024.0), qtr=_mm512_set1_pd(.25), neg_half=_mm512_set1_pd(-.5), two=_mm512_set1_pd(2.0), three8=_mm512_set1_pd(.375);
 if(i+8<=interior_end){
   __m512i idx=_mm512_set_epi64((long long)(i+7),(long long)(i+6),(long long)(i+5),(long long)(i+4),(long long)(i+3),(long long)(i+2),(long long)(i+1),(long long)i);
   __m512i ru=_mm512_and_si512(_mm512_add_epi64(_mm512_mullo_epi64(idx,_mm512_set1_epi64(17)),_mm512_set1_epi64(3)),mask);
   __m512i rv=_mm512_and_si512(_mm512_add_epi64(_mm512_mullo_epi64(idx,_mm512_set1_epi64(29)),_mm512_set1_epi64(7)),mask);
   for(;i+8<=interior_end;i+=8){
      __m512d u=_mm512_add_pd(qtr,_mm512_mul_pd(_mm512_cvtepi64_pd(ru),inv));
      __m512d v=_mm512_add_pd(neg_half,_mm512_mul_pd(_mm512_cvtepi64_pd(rv),inv));
      __m512i rvm=_mm512_and_si512(_mm512_add_epi64(rv,sub29),mask);
      __m512i rvp=_mm512_and_si512(_mm512_add_epi64(rv,plus29),mask);
      __m512d vm=_mm512_add_pd(neg_half,_mm512_mul_pd(_mm512_cvtepi64_pd(rvm),inv));
      __m512d vp=_mm512_add_pd(neg_half,_mm512_mul_pd(_mm512_cvtepi64_pd(rvp),inv));
      __m512d j=_mm512_sub_pd(_mm512_sub_pd(_mm512_mul_pd(_mm512_add_pd(two,_mm512_mul_pd(three8,_mm512_mul_pd(u,u))),v),vm),vp);
      double t[8] __attribute__((aligned(64))); _mm512_store_pd(t,j);
      uint64_t r=i-s;
      a[(r+0)&3]+=t[0]; a[(r+1)&3]+=t[1]; a[(r+2)&3]+=t[2]; a[(r+3)&3]+=t[3];
      a[(r+4)&3]+=t[4]; a[(r+5)&3]+=t[5]; a[(r+6)&3]+=t[6]; a[(r+7)&3]+=t[7];
      ru=_mm512_and_si512(_mm512_add_epi64(ru,plus136),mask); rv=_mm512_and_si512(_mm512_add_epi64(rv,plus232),mask);
   }
 }
 for(;i<interior_end;i++) add_carrier(a,i-s,slot_scalar(i));
 if(i<end) { add_carrier(a,i-s,slot_scalar(i)); i++; }
 return (a[0]+a[1])+(a[2]+a[3]);
}
static void *worker(void*p){int e=((Arg*)p)->e;cpu_set_t set;CPU_ZERO(&set);CPU_SET(e,&set);pthread_setaffinity_np(pthread_self(),sizeof(set),&set);uint64_t chunks=(N+CHUNK-1)/CHUNK;for(uint64_t k=e;k<chunks;k+=EXECUTORS)partials[k]=chunk_sum(k);return 0;}
static double tree_reduce(uint64_t m){while(m>1){uint64_t w=0;for(uint64_t i=0;i+1<m;i+=2)partials[w++]=partials[i]+partials[i+1];if(m&1)partials[w++]=partials[m-1];m=w;}return partials[0];}
int main(int argc,char**argv){if(argc!=2)return 2;N=strtoull(argv[1],0,10);if(N<4||N>100000000)return 2;uint64_t chunks=(N+CHUNK-1)/CHUNK;Arg a[EXECUTORS];pthread_t t[EXECUTORS];
#if EXECUTORS == 1
 a[0].e=0;worker(&a[0]);
#else
 for(int e=0;e<EXECUTORS;e++){a[e].e=e;if(pthread_create(&t[e],0,worker,&a[e]))return 3;}for(int e=0;e<EXECUTORS;e++)pthread_join(t[e],0);
#endif
 double x=tree_reduce(chunks);uint64_t bits;memcpy(&bits,&x,8);printf("checksum_bits=0x%016llx\n",(unsigned long long)bits);return 0;}
