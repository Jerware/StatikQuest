@echo off
setlocal
if not exist "%~dp0build\statik_local\play_statik.cmd" (
    echo The local Statik build has not been staged.
    echo See README-STATIK.md for build and staging instructions.
    pause
    exit /b 1
)
call "%~dp0build\statik_local\play_statik.cmd"
