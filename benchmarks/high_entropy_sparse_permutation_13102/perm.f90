program p
  use iso_fortran_env, only: int64, real64
  implicit none
  integer(int64) :: n,i,bits
  real(real64) :: s
  character(len=64) :: arg
  if(command_argument_count()/=1) stop 2
  call get_command_argument(1,arg); read(arg,*) n
  s=0.0_real64
!$omp parallel do default(none) shared(n) private(i) reduction(+:s) schedule(static)
  do i=0_int64,n-1_int64
    s = s + xv(modulo(i*97_int64+17_int64,n)) &
          - 0.5_real64*xv(modulo(i*193_int64+31_int64,n)) &
          + 0.25_real64*xv(modulo(i*389_int64+47_int64,n)) &
          - 0.125_real64*xv(modulo(i*769_int64+71_int64,n)) &
          + 0.0625_real64*xv(modulo(i*1543_int64+101_int64,n)) &
          - 0.03125_real64*xv(modulo(i*3079_int64+131_int64,n))
  end do
!$omp end parallel do
  bits=transfer(s,bits)
  write(*,'(A,Z16.16)') 'checksum_bits=0x',bits
contains
  pure real(real64) function xv(j)
    integer(int64), intent(in) :: j
    integer(int64) :: q
    q=modulo(j*2654435761_int64+2246822519_int64,8192_int64)
    xv=-0.5_real64+real(q,real64)/4096.0_real64
  end function
end program
