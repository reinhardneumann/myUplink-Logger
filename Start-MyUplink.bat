@echo off
rem Startet das Menue des myUplink-Loggers per Doppelklick.
rem Optionale Parameter werden an das Menue weitergegeben, z. B. in der Eingabeaufforderung:
rem   Start-MyUplink.bat -Dezimaltrennzeichen ","
rem Erlaubt: Auto (Standard), "," und "." (Alias: -Dezimalkennzeichen).
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0MyUplink-Menue.ps1" %*
if errorlevel 1 (
  echo.
  echo Es ist ein Fehler aufgetreten.
  pause
)
