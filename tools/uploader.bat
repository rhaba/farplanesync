@echo off
title farplanesync uploader
rem Sends farplanesync's character files to farplane.org (outside the game). Close this window to stop.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uploader.ps1"
pause
