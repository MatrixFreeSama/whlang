program rigid7
  use iso_fortran_env, only: int64, real64
  implicit none
  integer :: argc
  character(len=64) :: arg
  integer(int64) :: steps,i,bits
  real(real64) :: q0,q1,q2,q3,wx,wy,wz,norm2,corr,nq0,nq1,nq2,nq3,nwx,nwy,nwz
  steps=0_int64
  argc=command_argument_count(); if(argc>=1) then; call get_command_argument(1,arg); read(arg,*) steps; end if
  q0=1.0_real64; q1=0.01_real64; q2=-0.02_real64; q3=0.03_real64
  wx=1.2_real64; wy=-0.7_real64; wz=0.9_real64
  do i=0_int64,steps-1_int64
    norm2=(((q0*q0)+(q1*q1))+(q2*q2))+(q3*q3)
    corr=0.15_real64*(1.0_real64-norm2)
    nq0=q0+(((-0.5_real64*(((q1*wx)+(q2*wy))+(q3*wz)))+(corr*q0))*0.00001_real64)
    nq1=q1+(((0.5_real64*(((q0*wx)+(q2*wz))-(q3*wy)))+(corr*q1))*0.00001_real64)
    nq2=q2+(((0.5_real64*(((q0*wy)+(q3*wx))-(q1*wz)))+(corr*q2))*0.00001_real64)
    nq3=q3+(((0.5_real64*(((q0*wz)+(q1*wy))-(q2*wx)))+(corr*q3))*0.00001_real64)
    nwx=wx+((((0.6_real64*wy)*wz)-(0.02_real64*wx))*0.00001_real64)
    nwy=wy+((((-0.4_real64*wz)*wx)-(0.025_real64*wy))*0.00001_real64)
    nwz=wz+((((0.2_real64*wx)*wy)-(0.03_real64*wz))*0.00001_real64)
    q0=nq0; q1=nq1; q2=nq2; q3=nq3; wx=nwx; wy=nwy; wz=nwz
  end do
  bits=transfer(q3,bits)
  write(*,'("out00_bits=0x",Z16.16)') bits
end program
