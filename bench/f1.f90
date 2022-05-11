! -Ofast -march=native -ffast-math

program f1

integer, parameter :: N = 1000, T = 10000

integer x, y, q

real(8), dimension(N,N) :: f, f_

do y=1,N
  f(1,y) = 1
  f_(1,y) = 1
end do

do q=1,T
  do x=2,N-1
    do y=2,N-1
      f_(x,y) = ( (f(x+1,y) + f(x-1,y) + f(x,y+1) + f(x,y-1) - 4*f(x,y)) + f(x,y) )*0.1
    end do
  end do
  f = f_
end do

print *, f_(2,2)

end program