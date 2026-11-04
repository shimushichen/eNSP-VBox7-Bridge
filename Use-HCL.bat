@echo off
rem Launch HCL in Oracle mode with the VBox72 gen_py shim, then restore MuMu.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','%~dp0scripts\Use-HCL.ps1'"
