@echo off

REM The name portion of the top source file and all generated files
set SOURCE=spaceship

REM The location of 64TASS
set TASSHOME=d:\64tass

REM 0 = No tracing information, 1 = Include subroutine names, 2 = Generate trace messages
set TRACE_LEVEL=0

set OPTS=-D UNITTEST=%UNITTEST% -D TRACE_LEVEL=%TRACE_LEVEL% --long-address --flat -b
set DEST=--m65816 --intel-hex -o %SOURCE%.hex
set AUXFILES=--list=%SOURCE%.lst --labels=%SOURCE%.lbl

%TASSHOME%\64tass %OPTS% %DEST% %AUXFILES% src\%SOURCE%.s
