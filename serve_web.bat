@echo off
cd /d d:\zhanji\bao2\web || exit /b 1
echo serving http://localhost:8060/index.html   (Ctrl+C to stop)
python -m http.server 8060
