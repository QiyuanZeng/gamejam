@echo off
chcp 65001 > nul
:: DreamMaker Token 更新工具
:: 双击此文件即可更新保存的 x-access-token

set SCRIPT_DIR=%~dp0
set UPDATE_SCRIPT=%SCRIPT_DIR%update-token.js

for /f "tokens=*" %%i in ('where node 2^>nul') do set NODE_PATH=%%i

if "%NODE_PATH%"=="" (
    echo ❌ 未找到 Node.js，请先安装 Node.js
    echo    下载地址: https://nodejs.org
    pause
    exit /b 1
)

"%NODE_PATH%" "%UPDATE_SCRIPT%"
