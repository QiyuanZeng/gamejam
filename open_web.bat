@echo off
setlocal
set PORT=8060
set DIR=d:\zhanji\bao2\web

if not exist "%DIR%\index.html" (
	echo [ERR] no web build found at %DIR%
	echo       run export_web.bat first.
	pause
	exit /b 1
)

netstat -ano | findstr ":%PORT% " | findstr LISTENING >nul
if errorlevel 1 (
	echo starting local server on port %PORT% ...
	start "godot-web-server" /min cmd /c "cd /d %DIR% && python -m http.server %PORT%"
	ping -n 3 127.0.0.1 >nul
) else (
	echo server already listening on port %PORT%
)

echo opening http://localhost:%PORT%/index.html
start "" "http://localhost:%PORT%/index.html"
echo.
echo server runs in a minimized window titled "godot-web-server".
echo close that window to stop it.
endlocal
