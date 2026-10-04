program plasticity_ceiling
 use iso_fortran_env, only:int64,real64
 implicit none
 integer(int64)::n,i,bits,mid,lo,hi
 character(len=64)::arg
 real(real64)::x,over,dep,diss,sum
 call get_command_argument(1,arg);read(arg,*)n;sum=0.0_real64;mid=n/2;lo=max(0_int64,mid-2002_int64);hi=min(n,mid+2003_int64)
 do i=lo,hi-1_int64
   x=(real(i,real64)-0.5_real64*real(n,real64))*1.0e-6_real64
   over=50000000.0_real64-12500000000000.0_real64*x*x
   if(over>0.0_real64)then;dep=over/202000000000.0_real64;else;dep=0.0_real64;endif
   diss=250000000.0_real64*dep+1000000000.0_real64*dep*dep
   sum=sum+diss
 end do
 bits=transfer(sum,bits);write(*,'(A,ES24.17)')'checksum=',sum;write(*,'(A,Z16.16)')'checksum_bits=0x',bits
end program
