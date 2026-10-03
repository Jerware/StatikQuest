@echo off
rem ASTRO BOT Rescue Mission on this PC, shown in a headset connected through Virtual Desktop
rem (or any other OpenXR runtime). Settings: pc-vr\settings.txt
title Astro Bot VR
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pc-vr\launch.ps1" %*
