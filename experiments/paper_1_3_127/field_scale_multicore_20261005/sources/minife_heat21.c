#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <omp.h>

static inline size_t idx3(size_t i,size_t j,size_t k,size_t ny,size_t nz){return (i*ny+j)*nz+k;}
int main(int argc,char**argv){
  if(argc!=3){fprintf(stderr,"usage: %s field.whfld n\n",argv[0]);return 2;}
  size_t n=strtoull(argv[2],0,10), ny=n, nz=n, N=n*n*n;
  size_t bytes=256+N*sizeof(float);
  int fd=open(argv[1],O_RDONLY); if(fd<0){perror("open");return 3;}
  void *map=mmap(NULL,bytes,PROT_READ,MAP_PRIVATE,fd,0); if(map==MAP_FAILED){perror("mmap");return 4;}
  const float *u=(const float*)((const unsigned char*)map+256);
  float sum=0.0f;
  const float c0=8.0f/3.0f, ce=-1.0f/6.0f, cc=-1.0f/12.0f;
  #pragma omp parallel for collapse(2) schedule(static) reduction(+:sum)
  for(size_t i=0;i<n;i++) for(size_t j=0;j<n;j++){
    size_t im=i?i-1:n-1, ip=(i+1==n)?0:i+1;
    size_t jm=j?j-1:n-1, jp=(j+1==n)?0:j+1;
    for(size_t k=0;k<n;k++){
      size_t km=k?k-1:n-1, kp=(k+1==n)?0:k+1;
      float edge =
        u[idx3(im,jm,k,ny,nz)] + u[idx3(im,jp,k,ny,nz)] +
        u[idx3(ip,jm,k,ny,nz)] + u[idx3(ip,jp,k,ny,nz)] +
        u[idx3(im,j,km,ny,nz)] + u[idx3(im,j,kp,ny,nz)] +
        u[idx3(ip,j,km,ny,nz)] + u[idx3(ip,j,kp,ny,nz)] +
        u[idx3(i,jm,km,ny,nz)] + u[idx3(i,jm,kp,ny,nz)] +
        u[idx3(i,jp,km,ny,nz)] + u[idx3(i,jp,kp,ny,nz)];
      float corner =
        u[idx3(im,jm,km,ny,nz)] + u[idx3(im,jm,kp,ny,nz)] +
        u[idx3(im,jp,km,ny,nz)] + u[idx3(im,jp,kp,ny,nz)] +
        u[idx3(ip,jm,km,ny,nz)] + u[idx3(ip,jm,kp,ny,nz)] +
        u[idx3(ip,jp,km,ny,nz)] + u[idx3(ip,jp,kp,ny,nz)];
      float s=c0*u[idx3(i,j,k,ny,nz)] + ce*edge + cc*corner;
      sum += s*s;
    }
  }
  uint32_t bits; memcpy(&bits,&sum,4);
  printf("checksum_f32_bits=0x%08x\n",bits);
  munmap(map,bytes); close(fd); return 0;
}
