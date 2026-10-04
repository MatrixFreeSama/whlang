#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
static inline size_t I(size_t i,size_t j,size_t k,size_t n){return(i*n+j)*n+k;}
int main(int ac,char**av){if(ac!=4)return 2;size_t n=strtoull(av[2],0,10),N=n*n*n;int shifted=atoi(av[3]);int fd=open(av[1],O_RDONLY);float*u=mmap(0,256+4*N,PROT_READ,MAP_PRIVATE,fd,0);u=(float*)((char*)u+256);float sum=0;for(size_t i=0;i<n;i++)for(size_t j=0;j<n;j++)for(size_t k=0;k<n;k++){float x=u[I(i,j,k,n)];if(shifted)x+=u[I(i,j,(k+1==n)?0:k+1,n)];sum+=x*x;}uint32_t b;memcpy(&b,&sum,4);printf("checksum_f32_bits=0x%08x\n",b);}
