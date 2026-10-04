program p
use iso_c_binding;use omp_lib;implicit none
interface
 function c_open(path,flags) bind(C,name='open') result(fd);import c_char,c_int;character(c_char),dimension(*)::path;integer(c_int),value::flags;integer(c_int)::fd;end function
 function c_mmap(addr,len,prot,flags,fd,off) bind(C,name='mmap') result(q);import c_ptr,c_size_t,c_int,c_long;type(c_ptr),value::addr;integer(c_size_t),value::len;integer(c_int),value::prot,flags,fd;integer(c_long),value::off;type(c_ptr)::q;end function
 function c_munmap(addr,len) bind(C,name='munmap') result(rc);import c_ptr,c_size_t,c_int;type(c_ptr),value::addr;integer(c_size_t),value::len;integer(c_int)::rc;end function
 function c_close(fd) bind(C,name='close') result(rc);import c_int;integer(c_int),value::fd;integer(c_int)::rc;end function
end interface
integer(c_size_t)::n,ntot,bytes,i,j,k,im,ip,jm,jp,km,kp;integer(c_int)::fd,rc;type(c_ptr)::base,data;integer(c_intptr_t)::bi;real(c_float),pointer::u(:);real(c_float)::sum,s;real(c_float),parameter::r=1.0_c_float/27.0_c_float;character(4096)::path,arg;character(c_char),allocatable::cp(:);integer::L,q;integer(c_int32_t)::bits
if(command_argument_count()/=2)stop 2;call get_command_argument(1,path);call get_command_argument(2,arg);read(arg,*)n;ntot=n*n*n;bytes=256+4*ntot;L=len_trim(path);allocate(cp(0:L));do q=1,L;cp(q-1)=path(q:q);enddo;cp(L)=c_null_char;fd=c_open(cp,0);base=c_mmap(c_null_ptr,bytes,1,2,fd,0_c_long);bi=transfer(base,bi)+256;data=transfer(bi,data);call c_f_pointer(data,u,[int(ntot)]);sum=0.0
!$omp parallel do collapse(2) schedule(static) reduction(+:sum) private(i,j,k,im,ip,jm,jp,km,kp,s)
do i=0,n-1;do j=0,n-1;if(i==0)then;im=n-1;else;im=i-1;endif;if(i+1==n)then;ip=0;else;ip=i+1;endif;if(j==0)then;jm=n-1;else;jm=j-1;endif;if(j+1==n)then;jp=0;else;jp=j+1;endif;do k=0,n-1;if(k==0)then;km=n-1;else;km=k-1;endif;if(k+1==n)then;kp=0;else;kp=k+1;endif;s=( &
       u(1+(im*n+jm)*n+km) + &
       u(1+(im*n+jm)*n+k) + &
       u(1+(im*n+jm)*n+kp) + &
       u(1+(im*n+j)*n+km) + &
       u(1+(im*n+j)*n+k) + &
       u(1+(im*n+j)*n+kp) + &
       u(1+(im*n+jp)*n+km) + &
       u(1+(im*n+jp)*n+k) + &
       u(1+(im*n+jp)*n+kp) + &
       u(1+(i*n+jm)*n+km) + &
       u(1+(i*n+jm)*n+k) + &
       u(1+(i*n+jm)*n+kp) + &
       u(1+(i*n+j)*n+km) + &
       u(1+(i*n+j)*n+k) + &
       u(1+(i*n+j)*n+kp) + &
       u(1+(i*n+jp)*n+km) + &
       u(1+(i*n+jp)*n+k) + &
       u(1+(i*n+jp)*n+kp) + &
       u(1+(ip*n+jm)*n+km) + &
       u(1+(ip*n+jm)*n+k) + &
       u(1+(ip*n+jm)*n+kp) + &
       u(1+(ip*n+j)*n+km) + &
       u(1+(ip*n+j)*n+k) + &
       u(1+(ip*n+j)*n+kp) + &
       u(1+(ip*n+jp)*n+km) + &
       u(1+(ip*n+jp)*n+k) + &
       u(1+(ip*n+jp)*n+kp))*r;sum=sum+s*s;enddo;enddo;enddo
!$omp end parallel do
bits=transfer(sum,bits);write(*,'(A,Z8.8)')'checksum_f32_bits=0x',bits;rc=c_munmap(base,bytes);rc=c_close(fd)
end program
