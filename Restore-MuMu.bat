@echo off
rem Restore MuMu as the VirtualBox COM owner after an HCL session.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%~dp0scripts\Set-VBoxComMode.ps1','-Mode','MuMu'"
