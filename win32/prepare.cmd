setlocal EnableExtensions
rd /s /q .dist
md .dist\bin
md .dist\lib
copy bin\* .dist\bin || goto :fail
7za x .src\ruby-*.7z -o.dist\lib || goto :fail
set wd=%CD%
cd .dist\lib
for /f %%R in ('dir /b ruby*') do (rename %%R ruby)
set ruby_home=%wd%\.dist\lib\ruby
:run
cd %wd%\..
cmd /c %ruby_home%\bin\gem build finita.gemspec  || goto :fail
cmd /c %ruby_home%\bin\gem install finita -N -l || goto :fail
cd %wd%
%ruby_home%\bin\ruby -rfinita -e "puts Finita::Version" > .version || goto :fail
goto :eof
:fail
exit /b %errorlevel%
:eof