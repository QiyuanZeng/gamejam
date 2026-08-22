@echo off
:: DreamMaker 代理开机自启配置脚本
:: 运行后，proxy.js 将在 Windows 登录时自动在后台启动
:: 使用方式：双击运行（需要管理员权限，或直接在当前用户目录写注册表）

set SCRIPT_DIR=%~dp0
set PROXY_PATH=%SCRIPT_DIR%proxy.js

:: 查找 node.exe 路径
for /f "tokens=*" %%i in ('where node') do set NODE_PATH=%%i

echo ================================================
echo  DreamMaker 代理自启配置
echo ================================================
echo  Node.js 路径: %NODE_PATH%
echo  代理脚本路径: %PROXY_PATH%
echo.

:: 写入注册表（当前用户，无需管理员权限）
set REG_KEY=HKCU\Software\Microsoft\Windows\CurrentVersion\Run
set REG_NAME=DreamMakerProxy
set REG_VALUE="%NODE_PATH%" "%PROXY_PATH%"

reg add "%REG_KEY%" /v "%REG_NAME%" /t REG_SZ /d %REG_VALUE% /f

if %errorlevel% == 0 (
    echo ✅ 已添加到开机自启！
    echo    每次 Windows 登录后将自动在后台运行代理
    echo.
    echo 如需取消自启，运行:
    echo    reg delete "%REG_KEY%" /v "%REG_NAME%" /f
) else (
    echo ❌ 写入注册表失败，请尝试以管理员身份运行此脚本
)

echo.
echo 立即启动代理？按任意键继续，关闭窗口跳过...
pause > nul
start "DreamMaker Proxy" /min "%NODE_PATH%" "%PROXY_PATH%"
echo ✅ 代理已在后台启动（http://127.0.0.1:7788）
