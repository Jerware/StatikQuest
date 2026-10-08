@echo off
rem Statik on this PC, shown in a headset through Virtual Desktop, SteamVR or another OpenXR runtime.
rem Settings: pc-vr\settings.txt
title Statik VR
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pc-vr\launch.ps1" %*
