#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char**argv){
  uint64_t steps = argc>1 ? strtoull(argv[1],0,10) : 0;
  double a=1.0,b=0.5,c=0.1,d=0.7,e=0.2,f=0.05;
  for(uint64_t i=0;i<steps;i++){
    double r1f=(0.1*a)*b;
    double r1r=0.03*c;
    double r2f=(0.07*c)*d;
    double r2r=0.02*e;
    double r3=(0.04*e)*a;
    double r4=0.01*f;
    double na=a+((r1r-r1f)-r3)*0.00001;
    double nb=b+((r1r-r1f)+r4)*0.00001;
    double nc=c+(((r1f-r1r)-r2f)+r2r)*0.00001;
    double nd=d+((r2r-r2f)+r4)*0.00001;
    double ne=e+((r2f-r2r)-r3)*0.00001;
    double nf=f+(r3-r4)*0.00001;
    a=na;b=nb;c=nc;d=nd;e=ne;f=nf;
  }
  uint64_t u; memcpy(&u,&f,8); printf("out00_bits=0x%016llx\n",(unsigned long long)u); return 0;
}
