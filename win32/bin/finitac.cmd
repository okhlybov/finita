@echo off
for /f "tokens=*" %%R in ('dir /b "%~dp0..\lib\ruby*"') do (
	set ruby_home=%~dp0..\lib\%%R
	goto :run
)
:run
"%ruby_home%\bin\ruby.exe" "%ruby_home%\bin\finitac" %*