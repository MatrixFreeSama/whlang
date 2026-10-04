program levelset
  use iso_fortran_env, only: int64, real64
  implicit none
  integer(int64) :: n,i,bits
  character(len=64)::arg
  real(real64),parameter :: dx=1.0e-8_real64,R=0.02_real64,w2=4.0e-10_real64,sigma=0.072_real64
  real(real64)::x,dl,dr,ql,qr,sum
  call get_command_argument(1,arg); read(arg,*) n; sum=0.0_real64
!$omp parallel do default(none) shared(n) private(i,x,dl,dr,ql,qr) reduction(+:sum) schedule(static)
  do i=0_int64,n-1_int64
    x=(real(i,real64)-0.5_real64*real(n,real64))*dx
    dl=x+R; dr=x-R; ql=dl*dl; qr=dr*dr
    if(ql<w2) sum=sum+sigma*(1.0_real64-ql/w2)
    if(qr<w2) sum=sum+sigma*(1.0_real64-qr/w2)
  end do
!$omp end parallel do
  bits=transfer(sum,bits); write(*,'(A,ES24.17)') 'checksum=',sum; write(*,'(A,Z16.16)') 'checksum_bits=0x',bits
end program
