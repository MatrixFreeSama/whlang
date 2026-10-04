#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char**argv){
 uint64_t steps=argc>1?strtoull(argv[1],0,10):0;
 double x1=.10,v1=0.0,x2=-.05,v2=.02,x3=.08,v3=-.01;
 for(uint64_t i=0;i<steps;i++){
  double nx1=x1+(v1*0.0001);
  double nv1=v1+(((((-0.8*x1)+(0.3*(x2-x1)))-(0.05*v1))+(0.02*(v2-v1)))*0.0001);
  double nx2=x2+(v2*0.0001);
  double nv2=v2+(((((0.25*(x1-x2))+(0.35*(x3-x2)))+(0.018*(v1-v2)))+(0.022*(v3-v2)))*0.0001);
  double nx3=x3+(v3*0.0001);
  double nv3=v3+(((((0.4*(x2-x3))-(0.7*x3))+(0.025*(v2-v3)))-(0.06*v3))*0.0001);
  x1=nx1;v1=nv1;x2=nx2;v2=nv2;x3=nx3;v3=nv3;
 }
 uint64_t u; memcpy(&u,&x3,8); printf("out00_bits=0x%016llx\n",(unsigned long long)u); return 0;
}
