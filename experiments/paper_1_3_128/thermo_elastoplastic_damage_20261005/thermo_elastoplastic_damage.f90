program thermo_damage
  use iso_fortran_env, only: int64, real64
  use iso_c_binding, only: c_int64_t
  implicit none
  integer(int64) :: n, i, im, ip, bits
  character(len=64) :: arg
  real(real64), allocatable :: dtemp(:), sxx0(:), localv(:)
  real(real64) :: x, heat_over, eth, strain_over, exx, eyy, ezz, gxy, gyz, gzx
  real(real64) :: emxx, emyy, emzz, tr, syy0, szz0, sxy0, syz0, szx0, meanp
  real(real64) :: dxx, dyy, dzz, j2q, seq, yield_over, dlambda, epxx
  real(real64) :: plastic_work, plastic_heat, energy, damage_over, damage_raw, damage
  real(real64) :: divsig, accel, dv, laptemp, sumv
  call get_command_argument(1,arg); read(arg,*) n
  allocate(dtemp(0:n-1),sxx0(0:n-1),localv(0:n-1))
  do i=0,n-1
    x=(real(i,real64)-0.5_real64*real(n,real64))*1.0e-6_real64
    heat_over=900.0_real64-100000000.0_real64*x*x
    if (heat_over > 0.0_real64) then; dtemp(i)=heat_over; else; dtemp(i)=0.0_real64; end if
    eth=0.000012_real64*dtemp(i)
    strain_over=0.018_real64-4500.0_real64*x*x
    if (strain_over > 0.0_real64) then; exx=strain_over; else; exx=0.0_real64; end if
    eyy=-0.25_real64*exx; ezz=-0.20_real64*exx
    gxy=0.15_real64*exx; gyz=0.05_real64*exx; gzx=-0.08_real64*exx
    emxx=exx-eth; emyy=eyy-eth; emzz=ezz-eth; tr=emxx+emyy+emzz
    sxx0(i)=121153846153.84615_real64*tr+161538461538.46155_real64*emxx
    syy0=121153846153.84615_real64*tr+161538461538.46155_real64*emyy
    szz0=121153846153.84615_real64*tr+161538461538.46155_real64*emzz
    sxy0=80769230769.23077_real64*gxy; syz0=80769230769.23077_real64*gyz; szx0=80769230769.23077_real64*gzx
    meanp=(sxx0(i)+syy0+szz0)/3.0_real64
    dxx=sxx0(i)-meanp; dyy=syy0-meanp; dzz=szz0-meanp
    j2q=1.5_real64*(dxx*dxx+dyy*dyy+dzz*dzz+2.0_real64*(sxy0*sxy0+syz0*syz0+szx0*szx0))
    seq=sqrt(j2q); yield_over=seq-350000000.0_real64
    if (yield_over > 0.0_real64) then; dlambda=yield_over/243307692307.69232_real64; else; dlambda=0.0_real64; end if
    epxx=1.5_real64*dlambda*dxx/(seq+1.0_real64)
    plastic_work=seq*dlambda; plastic_heat=0.9_real64*plastic_work/3744000.0_real64
    energy=0.5_real64*(sxx0(i)*emxx+syy0*emyy+szz0*emzz+sxy0*gxy+syz0*gyz+szx0*gzx)
    damage_over=energy-5000000.0_real64
    if (damage_over > 0.0_real64) then; damage_raw=damage_over*0.00000002_real64; else; damage_raw=0.0_real64; end if
    if (damage_raw > 0.95_real64) then; damage=0.95_real64; else; damage=damage_raw; end if
    localv(i)=plastic_work+damage*energy+100000000000.0_real64*epxx*epxx+plastic_heat*plastic_heat+dtemp(i)*dtemp(i)
  end do
  sumv=0.0_real64
  do i=0,n-1
    im=i-1; if (im < 0) im=n-1
    ip=i+1; if (ip >= n) ip=0
    divsig=(sxx0(ip)-sxx0(im))*500000.0_real64
    accel=divsig/7800.0_real64; dv=1.0e-9_real64*accel
    laptemp=(dtemp(ip)-2.0_real64*dtemp(i)+dtemp(im))*1.0e12_real64
    sumv=sumv+localv(i)+3900.0_real64*dv*dv+laptemp*laptemp*1.0e-18_real64
  end do
  bits=transfer(sumv,bits)
  write(*,'(A,ES25.17E3)') 'checksum=',sumv
  write(*,'(A,Z16.16)') 'checksum_bits=0x',bits
end program
