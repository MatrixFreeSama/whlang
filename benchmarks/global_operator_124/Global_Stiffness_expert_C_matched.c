#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHUNK 65536ULL
static uint64_t N;
static int E;
static double *partials;
typedef struct { int e; } Arg;

static inline double xval(uint64_t i){
    return -0.5 + (double)((i*29ULL + 7ULL) & 1023ULL) * (1.0/1024.0);
}
static inline double kval(uint64_t i){
    return 1.0 + (double)((i*17ULL + 3ULL) & 255ULL) * (1.0/1024.0);
}
static inline double slot(uint64_t i){
    uint64_t im1 = i ? i-1 : N-1;
    uint64_t ip1 = i+1==N ? 0 : i+1;
    double ki = kval(i), kip = kval(ip1);
    double yi = (ki + kip)*xval(i) - ki*xval(im1) - kip*xval(ip1);
    return yi*yi;
}
static inline double chunk_sum(uint64_t k){
    uint64_t s=k*CHUNK, end=s+CHUNK; if(end>N) end=N;
    double a0=0.0,a1=0.0,a2=0.0,a3=0.0;
    uint64_t i=s;
    for(; i+4<=end; i+=4){
        a0+=slot(i); a1+=slot(i+1); a2+=slot(i+2); a3+=slot(i+3);
    }
    if(i<end) a0+=slot(i++);
    if(i<end) a1+=slot(i++);
    if(i<end) a2+=slot(i++);
    return (a0+a1)+(a2+a3);
}
static void *worker(void *p){
    int e=((Arg*)p)->e;
    uint64_t chunks=(N+CHUNK-1)/CHUNK;
    for(uint64_t k=(uint64_t)e;k<chunks;k+=(uint64_t)E) partials[k]=chunk_sum(k);
    return 0;
}
static double tree_reduce(uint64_t m){
    while(m>1){
        uint64_t w=0;
        for(uint64_t i=0;i+1<m;i+=2) partials[w++]=partials[i]+partials[i+1];
        if(m&1) partials[w++]=partials[m-1];
        m=w;
    }
    return partials[0];
}
int main(int argc,char**argv){
    if(argc!=3) return 2;
    N=strtoull(argv[1],0,10); E=atoi(argv[2]);
    if(N<4 || N>100000000 || (E!=1 && E!=2 && E!=4)) return 2;
    uint64_t chunks=(N+CHUNK-1)/CHUNK;
    if(posix_memalign((void**)&partials,64,chunks*sizeof(double))) return 3;
    pthread_t th[4]; Arg a[4];
    if(E==1){ a[0].e=0; worker(&a[0]); }
    else {
        for(int e=0;e<E;e++){ a[e].e=e; if(pthread_create(&th[e],0,worker,&a[e])) return 4; }
        for(int e=0;e<E;e++) pthread_join(th[e],0);
    }
    double out=tree_reduce(chunks); uint64_t bits; memcpy(&bits,&out,8);
    printf("checksum_bits=0x%016llx\n",(unsigned long long)bits);
    free(partials); return 0;
}
