@echo off
rem Anno Mods (Hitzone-Skins Erweiterung + Anpassen-Suche) installieren / pruefen / entfernen / aktualisieren
if not exist "%~dp0dateien\installer.ps1" (
  echo Bitte die Zip zuerst komplett entpacken ^(Rechtsklick ^> Alle extrahieren^) und dann diese Datei im entpackten Ordner starten.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dateien\installer.ps1" %*
