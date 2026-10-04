program levelset_ceiling
  use iso_fortran_env, only: int64, real64
  implicit none
  integer(int64)::n,bits,mid
  character(len=64)::arg
  real(real64)::sum
  call get_command_argument(1,arg);read(arg,*)n;sum=0.0_real64;mid=n/2_int64
  call band(n,mid-2000000_int64,.true.,sum)
  call band(n,mid+2000000_int64,.false.,sum)
  bits=transfer(sum,bits);write(*,'(A,ES24.17)')'checksum=',sum;write(*,'(A,Z16.16)')'checksum_bits=0x',bits
contains
  subroutine band(n,center,left,sum)
    integer(int64),intent(in)::n,center
    logical,intent(in)::left
    real(real64),intent(inout)::sum
    integer(int64)::i,lo,hi
    real(real64),parameter::dx=1.0e-8_real64,R=0.02_real64,w2=4.0e-10_real64,sigma=0.072_real64
    real(real64)::x,d,q
    lo=max(0_int64,center-2002_int64);hi=min(n,center+2002_int64)
    do i=lo,hi-1_int64
      x=(real(i,real64)-0.5_real64*real(n,real64))*dx
      if(left)then; d=x+R; else; d=x-R; end if
      q=d*d;if(q<w2)sum=sum+sigma*(1.0_real64-q/w2)
    end do
  end subroutine
end program
