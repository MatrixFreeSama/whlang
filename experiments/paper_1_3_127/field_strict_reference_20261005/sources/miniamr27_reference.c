#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <omp.h>
static inline size_t I(size_t i,size_t j,size_t k,size_t n){return (i*n+j)*n+k;}
int main(int argc,char**argv){if(argc!=3)return 2;size_t n=strtoull(argv[2],0,10),N=n*n*n,bytes=256+4*N;int fd=open(argv[1],O_RDONLY);void*m=mmap(0,bytes,PROT_READ,MAP_PRIVATE,fd,0);if(m==MAP_FAILED)return 3;const float*u=(const float*)((char*)m+256);double sum=0.0;const float r=1.0f/27.0f;
#pragma omp parallel for collapse(2) schedule(static) reduction(+:sum)
for(size_t i=0;i<n;i++)for(size_t j=0;j<n;j++){size_t im=i?i-1:n-1,ip=(i+1==n)?0:i+1,jm=j?j-1:n-1,jp=(j+1==n)?0:j+1;for(size_t k=0;k<n;k++){size_t km=k?k-1:n-1,kp=(k+1==n)?0:k+1;float s=(
        u[I(im,jm,km,n)] +
        u[I(im,jm,k,n)] +
        u[I(im,jm,kp,n)] +
        u[I(im,j,km,n)] +
        u[I(im,j,k,n)] +
        u[I(im,j,kp,n)] +
        u[I(im,jp,km,n)] +
        u[I(im,jp,k,n)] +
        u[I(im,jp,kp,n)] +
        u[I(i,jm,km,n)] +
        u[I(i,jm,k,n)] +
        u[I(i,jm,kp,n)] +
        u[I(i,j,km,n)] +
        u[I(i,j,k,n)] +
        u[I(i,j,kp,n)] +
        u[I(i,jp,km,n)] +
        u[I(i,jp,k,n)] +
        u[I(i,jp,kp,n)] +
        u[I(ip,jm,km,n)] +
        u[I(ip,jm,k,n)] +
        u[I(ip,jm,kp,n)] +
        u[I(ip,j,km,n)] +
        u[I(ip,j,k,n)] +
        u[I(ip,j,kp,n)] +
        u[I(ip,jp,km,n)] +
        u[I(ip,jp,k,n)] +
        u[I(ip,jp,kp,n)])*r;sum+=(double)s*(double)s;}}
printf("reference_f64=%.17g\n",sum);munmap(m,bytes);close(fd);}
