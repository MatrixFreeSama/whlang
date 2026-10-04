#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char**argv){
  uint64_t steps=argc>1?strtoull(argv[1],0,10):0;
  double q0=1.0,q1=0.01,q2=-0.02,q3=0.03,wx=1.2,wy=-0.7,wz=0.9;
  for(uint64_t i=0;i<steps;i++){
    double norm2=(((q0*q0)+(q1*q1))+(q2*q2))+(q3*q3);
    double corr=0.15*(1.0-norm2);
    double nq0=q0+(((-0.5*(((q1*wx)+(q2*wy))+(q3*wz)))+(corr*q0))*0.00001);
    double nq1=q1+(((0.5*(((q0*wx)+(q2*wz))-(q3*wy)))+(corr*q1))*0.00001);
    double nq2=q2+(((0.5*(((q0*wy)+(q3*wx))-(q1*wz)))+(corr*q2))*0.00001);
    double nq3=q3+(((0.5*(((q0*wz)+(q1*wy))-(q2*wx)))+(corr*q3))*0.00001);
    double nwx=wx+((((0.6*wy)*wz)-(0.02*wx))*0.00001);
    double nwy=wy+((((-0.4*wz)*wx)-(0.025*wy))*0.00001);
    double nwz=wz+((((0.2*wx)*wy)-(0.03*wz))*0.00001);
    q0=nq0;q1=nq1;q2=nq2;q3=nq3;wx=nwx;wy=nwy;wz=nwz;
  }
  uint64_t u; memcpy(&u,&q3,8); printf("out00_bits=0x%016llx\n",(unsigned long long)u); return 0;
}
