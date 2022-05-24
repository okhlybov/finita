! -Ofast -march=native -ffast-math

program f1

  integer, parameter :: N = 1024

  call runme(N)

end program

subroutine runme(N)

  integer, parameter :: N1 = 1024
  integer, parameter :: T = 10000

  real(8), allocatable, dimension(:,:) :: f, f_

  integer x, y, q
    
  allocate(f(N,N))
  allocate(f_(N,N))
  
  do y=1,N
    f(1,y) = 1
    f_(1,y) = 1
  end do
  
  do q=1,T
      do y=2,N-1
        do x=2,N-1
          f_(x,y) = ( (f(x+1,y) + f(x-1,y) + f(x,y+1) + f(x,y-1) - 4*f(x,y)) + f(x,y) )*0.1
      end do
    end do
    f = f_
  end do

  print *, f_(2,2)

end subroutine