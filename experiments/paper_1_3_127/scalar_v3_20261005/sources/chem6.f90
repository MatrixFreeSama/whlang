program chem6
  use iso_fortran_env, only: int64, real64
  implicit none
  integer(int64) :: steps, i, bits
  real(real64) :: a,b,c,d,e,f,r1f,r1r,r2f,r2r,r3,r4,na,nb,nc,nd,ne,nf
  character(len=64) :: arg
  steps=0_int64
  if (command_argument_count() >= 1) then
    call get_command_argument(1,arg); read(arg,*) steps
  end if
  a=1.0_real64; b=0.5_real64; c=0.1_real64; d=0.7_real64; e=0.2_real64; f=0.05_real64
  do i=1_int64,steps
    r1f=(0.1_real64*a)*b
    r1r=0.03_real64*c
    r2f=(0.07_real64*c)*d
    r2r=0.02_real64*e
    r3=(0.04_real64*e)*a
    r4=0.01_real64*f
    na=a+((r1r-r1f)-r3)*0.00001_real64
    nb=b+((r1r-r1f)+r4)*0.00001_real64
    nc=c+(((r1f-r1r)-r2f)+r2r)*0.00001_real64
    nd=d+((r2r-r2f)+r4)*0.00001_real64
    ne=e+((r2f-r2r)-r3)*0.00001_real64
    nf=f+(r3-r4)*0.00001_real64
    a=na; b=nb; c=nc; d=nd; e=ne; f=nf
  end do
  bits=transfer(f,bits)
  write(*,'(A,Z16.16)') 'out00_bits=0x',bits
end program
