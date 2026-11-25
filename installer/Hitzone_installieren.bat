@echo off
rem Hitzone-Skins Erweiterung installieren / pruefen / reparieren
if not exist "%~dp0dateien\installer.ps1" (
  echo Bitte die Zip zuerst komplett entpacken ^(Rechtsklick ^> Alle extrahieren^) und dann diese Datei im entpackten Ordner starten.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dateien\installer.ps1" %*
