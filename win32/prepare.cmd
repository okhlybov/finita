setlocal EnableExtensions
del /f /s /q .dist || goto :fail
md .dist\bin
md .dist\lib
copy bin\* .dist\bin || goto :fail
7za x .src\ruby-*.7z -o.dist\lib || goto :fail
set wd=%CD%
cd ..
for /f "tokens=*" %%R in ('dir /b "%wd%\.dist\lib\ruby*"') do (
	set ruby_home=%wd%\.dist\lib\%%R
	goto :run
)
:run
%ruby_home%\bin\gem install finita -N -l || goto :fail
goto :eof
:fail
exit /b %errorlevel%
:eof