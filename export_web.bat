@echo off
setlocal

set GODOT=D:\godot\Godot_v4.7.1-stable_win64\Godot_v4.7.1-stable_win64.exe
set PROJ=d:\zhanji\moshi_demo
set OUTDIR=d:\zhanji\bao2\web
set OUT=%OUTDIR%\index.html
set LOG=d:\zhanji\moshi_demo\run_web.log
set TPL=%APPDATA%\Godot\export_templates\4.7.1.stable\web_nothreads_release.zip

if not exist "%GODOT%" (
	echo [ERR] standard Godot not found: %GODOT%
	echo       Web export requires the NON-mono editor.
	exit /b 1
)
if not exist "%TPL%" (
	echo [ERR] missing template: %TPL%
	exit /b 1
)
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

echo [1/2] exporting, log -^> %LOG%
"%GODOT%" --headless --path "%PROJ%" --export-release "Web" "%OUT%" > "%LOG%" 2>&1

echo [2/2] verifying
findstr /C:"ERROR" "%LOG%" >nul
if not errorlevel 1 (
	echo [FAIL] export reported ERROR, see %LOG%
	exit /b 1
)
if not exist "%OUT%" (
	echo [FAIL] index.html not generated, see %LOG%
	exit /b 1
)

echo [OK] exported to %OUTDIR%
dir /-c "%OUTDIR%"
echo.
echo local test: serve_web.bat  then open http://localhost:8060/index.html
endlocal
