@echo off
title Equicord Plugin Injector - Cleanup
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleanup.ps1" %*
