program fluid_solid_expert_fortran_matched
  use iso_fortran_env, only: int64, real64
  use omp_lib
  implicit none

  integer(int64), parameter :: CHUNK = 65536_int64
  integer(int64) :: N, chunks, k, m, w, i
  integer :: E, argc, tid, ios, eidx
  real(real64), allocatable :: partials(:)
  real(real64) :: out
  integer(int64) :: bits
  character(len=64) :: arg

  argc = command_argument_count()
  if (argc /= 2) stop 2
  call get_command_argument(1,arg); read(arg,*,iostat=ios) N
  if (ios /= 0) stop 2
  call get_command_argument(2,arg); read(arg,*,iostat=ios) E
  if (ios /= 0) stop 2
  if (N < 4_int64 .or. N > 100000000_int64) stop 2
  if (E /= 1 .and. E /= 2 .and. E /= 4) stop 2

  chunks = (N + CHUNK - 1_int64) / CHUNK
  allocate(partials(chunks), stat=ios)
  if (ios /= 0) stop 3
  partials = 0.0_real64

  call omp_set_dynamic(.false.)
  if (E == 1) then
    do k = 0_int64, chunks-1_int64
      partials(k+1_int64) = chunk_sum(k, N)
    end do
  else
!$omp parallel num_threads(E) default(none) shared(partials,N,chunks,E) private(tid,k)
    tid = omp_get_thread_num()
    k = int(tid,int64)
    do while (k < chunks)
      partials(k+1_int64) = chunk_sum(k, N)
      k = k + int(E,int64)
    end do
!$omp end parallel
  end if

  m = chunks
  do while (m > 1_int64)
    w = 0_int64
    i = 1_int64
    do while (i + 1_int64 <= m)
      w = w + 1_int64
      partials(w) = partials(i) + partials(i+1_int64)
      i = i + 2_int64
    end do
    if (i <= m) then
      w = w + 1_int64
      partials(w) = partials(m)
    end if
    m = w
  end do

  out = partials(1)
  bits = transfer(out,bits)
  write(*,'(A,Z16.16)') 'checksum_bits=0x', bits
  deallocate(partials)

contains
  pure function fluid(i) result(v)
    integer(int64), intent(in) :: i
    real(real64) :: v
    v = -0.375_real64 + real(iand(i*31_int64 + 11_int64, 2047_int64),real64) * (1.0_real64/2048.0_real64)
  end function
  pure function solid(i) result(v)
    integer(int64), intent(in) :: i
    real(real64) :: v
    v = 0.25_real64 + real(iand(i*23_int64 + 5_int64, 1023_int64),real64) * (1.0_real64/1536.0_real64)
  end function
  pure function rho(i) result(v)
    integer(int64), intent(in) :: i
    real(real64) :: v
    v = 1.0_real64 + real(iand(i*13_int64 + 9_int64, 255_int64),real64) * (1.0_real64/2048.0_real64)
  end function
  pure function mu(i) result(v)
    integer(int64), intent(in) :: i
    real(real64) :: v
    v = 0.75_real64 + real(iand(i*7_int64 + 3_int64, 127_int64),real64) * (1.0_real64/1024.0_real64)
  end function
  pure function elastic(i) result(v)
    integer(int64), intent(in) :: i
    real(real64) :: v
    v = 1.25_real64 + real(iand(i*19_int64 + 1_int64, 255_int64),real64) * (1.0_real64/1024.0_real64)
  end function
  pure function gamma_c(i) result(v)
    integer(int64), intent(in) :: i
    real(real64) :: v
    v = 0.125_real64 + real(iand(i*5_int64 + 7_int64, 63_int64),real64) * (1.0_real64/4096.0_real64)
  end function
  pure function slot(i,nloc) result(v)
    integer(int64), intent(in) :: i,nloc
    integer(int64) :: im1, ip1
    real(real64) :: fi,fm,fp,ui,um,up,F,S,g,d,v
    if (i == 0_int64) then; im1=nloc-1_int64; else; im1=i-1_int64; end if
    if (i+1_int64 == nloc) then; ip1=0_int64; else; ip1=i+1_int64; end if
    fi=fluid(i); fm=fluid(im1); fp=fluid(ip1)
    ui=solid(i); um=solid(im1); up=solid(ip1)
    F = rho(i)*(2.0_real64*fi-fm-fp) + mu(i)*(fp-fm)
    S = elastic(i)*(2.0_real64*ui-um-up) + 0.0625_real64*(up-um)
    g=gamma_c(i); d=fi-ui
    F=F+g*d; S=S-g*d
    v=F*F+S*S
  end function
  pure function chunk_sum(k,nloc) result(s)
    integer(int64), intent(in) :: k,nloc
    integer(int64) :: st,en,j
    real(real64) :: s,a0,a1,a2,a3
    st=k*CHUNK; en=min(st+CHUNK,nloc)
    a0=0.0_real64; a1=0.0_real64; a2=0.0_real64; a3=0.0_real64
    j=st
    do while (j+4_int64 <= en)
      a0=a0+slot(j,nloc); a1=a1+slot(j+1_int64,nloc)
      a2=a2+slot(j+2_int64,nloc); a3=a3+slot(j+3_int64,nloc)
      j=j+4_int64
    end do
    if (j<en) then; a0=a0+slot(j,nloc); j=j+1_int64; end if
    if (j<en) then; a1=a1+slot(j,nloc); j=j+1_int64; end if
    if (j<en) then; a2=a2+slot(j,nloc); end if
    s=(a0+a1)+(a2+a3)
  end function
end program
