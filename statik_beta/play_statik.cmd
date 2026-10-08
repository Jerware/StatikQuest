@echo off
setlocal
cd /d "%~dp0"
set "ps=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "ps=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%ps%" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0launcher.ps1"
if errorlevel 1 pause
