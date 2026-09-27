#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define MAX_NODES 64
#define MAX_EDGES 256

static uint32_t parse_u32(const char *s) {
    char *e = NULL; unsigned long v = strtoul(s, &e, 10);
    if (!s[0] || !e || *e || v > 0xffffffffUL) { fprintf(stderr,"parse error\n"); exit(65); }
    return (uint32_t)v;
}
static uint64_t work_one(uint32_t node, uint32_t iters) {
    uint64_t x=(uint64_t)node+1, k=UINT64_C(0x9e3779b97f4a7c15);
    while(iters--) { x*=k; x=(x>>17)|(x<<(64-17)); x+=UINT64_C(0x27d4eb2d); }
    return x;
}
int main(int argc,char **argv){
    if(argc<4) return 64;
    uint32_t n=parse_u32(argv[1]), e=parse_u32(argv[2]), slots=parse_u32(argv[3]);
    if(!n||n>MAX_NODES||e>MAX_EDGES||slots!=1) return 65;
    if(argc != (int)(4+2*n+2*e)) return 64;
    uint32_t home[MAX_NODES], work[MAX_NODES], indeg[MAX_NODES]={0}, first[MAX_NODES], next[MAX_EDGES], vtx[MAX_EDGES];
    uint64_t result[MAX_NODES];
    for(uint32_t i=0;i<n;i++) first[i]=UINT32_MAX;
    int a=4;
    for(uint32_t i=0;i<n;i++){ home[i]=parse_u32(argv[a++]); if(home[i]) return 65; }
    for(uint32_t i=0;i<n;i++) work[i]=parse_u32(argv[a++]);
    for(uint32_t j=0;j<e;j++){
        uint32_t u=parse_u32(argv[a++]),v=parse_u32(argv[a++]); if(u>=n||v>=n) return 65;
        vtx[j]=v; next[j]=first[u]; first[u]=j; indeg[v]++;
    }
    uint32_t q[MAX_NODES],qh=0,qt=0;
    for(uint32_t i=0;i<n;i++) if(indeg[i]==0) q[qt++]=i;
    uint32_t completed=0, messages=0;
    while(qh<qt){
        uint32_t u=q[qh++]; result[u]=work_one(u,work[u]); completed++;
        for(uint32_t j=first[u];j!=UINT32_MAX;j=next[j]){ uint32_t v=vtx[j]; messages++; if(--indeg[v]==0) q[qt++]=v; }
    }
    if(completed!=n||messages!=e) return 66;
    uint64_t checksum=0; for(uint32_t i=0;i<n;i++) checksum^=result[i]+UINT64_C(0x9e3779b97f4a7c15)*(i+1);
    printf("{\"mode\":\"expert_c_causal_q1\",\"completed\":%u,\"dependency_messages\":%u,\"checksum\":\"%016llx\"}\n",completed,messages,(unsigned long long)checksum);
    return 0;
}
