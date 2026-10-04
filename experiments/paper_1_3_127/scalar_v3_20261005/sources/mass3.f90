program mass3
 use iso_fortran_env, only: int64,real64
 implicit none
 integer :: argc
 character(len=64)::arg
 integer(int64)::steps,i,bits
 real(real64)::x1,v1,x2,v2,x3,v3,nx1,nv1,nx2,nv2,nx3,nv3
 steps=0_int64; argc=command_argument_count(); if(argc>=1) then; call get_command_argument(1,arg); read(arg,*) steps; end if
 x1=.10_real64;v1=0.0_real64;x2=-.05_real64;v2=.02_real64;x3=.08_real64;v3=-.01_real64
 do i=0_int64,steps-1_int64
  nx1=x1+(v1*0.0001_real64)
  nv1=v1+(((((-0.8_real64*x1)+(0.3_real64*(x2-x1)))-(0.05_real64*v1))+(0.02_real64*(v2-v1)))*0.0001_real64)
  nx2=x2+(v2*0.0001_real64)
  nv2=v2+(((((0.25_real64*(x1-x2))+(0.35_real64*(x3-x2)))+(0.018_real64*(v1-v2)))+(0.022_real64*(v3-v2)))*0.0001_real64)
  nx3=x3+(v3*0.0001_real64)
  nv3=v3+(((((0.4_real64*(x2-x3))-(0.7_real64*x3))+(0.025_real64*(v2-v3)))-(0.06_real64*v3))*0.0001_real64)
  x1=nx1;v1=nv1;x2=nx2;v2=nv2;x3=nx3;v3=nv3
 end do
 bits=transfer(x3,bits); write(*,'("out00_bits=0x",Z16.16)') bits
end program
