program minife_heat21_fortran
  use iso_c_binding
  use omp_lib
  implicit none
  interface
    function c_open(path, flags) bind(C,name='open') result(fd)
      import :: c_char,c_int
      character(c_char), dimension(*) :: path
      integer(c_int), value :: flags
      integer(c_int) :: fd
    end function
    function c_mmap(addr,len,prot,flags,fd,off) bind(C,name='mmap') result(p)
      import :: c_ptr,c_size_t,c_int,c_long
      type(c_ptr), value :: addr
      integer(c_size_t), value :: len
      integer(c_int), value :: prot,flags,fd
      integer(c_long), value :: off
      type(c_ptr) :: p
    end function
    function c_munmap(addr,len) bind(C,name='munmap') result(rc)
      import :: c_ptr,c_size_t,c_int
      type(c_ptr), value :: addr
      integer(c_size_t), value :: len
      integer(c_int) :: rc
    end function
    function c_close(fd) bind(C,name='close') result(rc)
      import :: c_int
      integer(c_int), value :: fd
      integer(c_int) :: rc
    end function
  end interface
  integer(c_int), parameter :: O_RDONLY=0, PROT_READ=1, MAP_PRIVATE=2
  integer(c_int) :: fd,rc
  integer(c_size_t) :: n,Ntot,bytes
  integer(c_intptr_t) :: baseint
  type(c_ptr) :: base, datap
  real(c_float), pointer :: u(:)
  real(c_float) :: sum,s,edge,corner
  real(c_float), parameter :: c0=8.0_c_float/3.0_c_float, ce=-1.0_c_float/6.0_c_float, cc=-1.0_c_float/12.0_c_float
  integer(c_size_t) :: i,j,k,im,ip,jm,jp,km,kp
  character(len=4096) :: path,arg
  character(c_char), allocatable :: cpath(:)
  integer :: L,q
  integer(c_int32_t) :: bits
  if(command_argument_count()/=2) stop 2
  call get_command_argument(1,path); call get_command_argument(2,arg); read(arg,*) n
  Ntot=n*n*n; bytes=256_c_size_t+4_c_size_t*Ntot
  L=len_trim(path); allocate(cpath(0:L));
  do q=1,L; cpath(q-1)=path(q:q); end do; cpath(L)=c_null_char
  fd=c_open(cpath,O_RDONLY); if(fd<0) stop 3
  base=c_mmap(c_null_ptr,bytes,PROT_READ,MAP_PRIVATE,fd,0_c_long)
  if(.not.c_associated(base)) stop 4
  baseint=transfer(base,baseint); baseint=baseint+256_c_intptr_t; datap=transfer(baseint,datap)
  call c_f_pointer(datap,u,[int(Ntot)])
  sum=0.0_c_float
!$omp parallel do collapse(2) schedule(static) reduction(+:sum) private(i,j,k,im,ip,jm,jp,km,kp,edge,corner,s)
  do i=0_c_size_t,n-1_c_size_t
    do j=0_c_size_t,n-1_c_size_t
      if(i==0) then; im=n-1; else; im=i-1; end if
      if(i+1==n) then; ip=0; else; ip=i+1; end if
      if(j==0) then; jm=n-1; else; jm=j-1; end if
      if(j+1==n) then; jp=0; else; jp=j+1; end if
      do k=0_c_size_t,n-1_c_size_t
        if(k==0) then; km=n-1; else; km=k-1; end if
        if(k+1==n) then; kp=0; else; kp=k+1; end if
        edge = &
          u(1+(im*n+jm)*n+k)+u(1+(im*n+jp)*n+k)+u(1+(ip*n+jm)*n+k)+u(1+(ip*n+jp)*n+k)+ &
          u(1+(im*n+j)*n+km)+u(1+(im*n+j)*n+kp)+u(1+(ip*n+j)*n+km)+u(1+(ip*n+j)*n+kp)+ &
          u(1+(i*n+jm)*n+km)+u(1+(i*n+jm)*n+kp)+u(1+(i*n+jp)*n+km)+u(1+(i*n+jp)*n+kp)
        corner = &
          u(1+(im*n+jm)*n+km)+u(1+(im*n+jm)*n+kp)+u(1+(im*n+jp)*n+km)+u(1+(im*n+jp)*n+kp)+ &
          u(1+(ip*n+jm)*n+km)+u(1+(ip*n+jm)*n+kp)+u(1+(ip*n+jp)*n+km)+u(1+(ip*n+jp)*n+kp)
        s=c0*u(1+(i*n+j)*n+k)+ce*edge+cc*corner
        sum=sum+s*s
      end do
    end do
  end do
!$omp end parallel do
  bits=transfer(sum,bits)
  write(*,'(A,Z8.8)') 'checksum_f32_bits=0x', bits
  rc=c_munmap(base,bytes); rc=c_close(fd)
end program
