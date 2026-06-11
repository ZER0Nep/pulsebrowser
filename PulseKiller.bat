@echo off
title PulseKiller - PUA:Pulse Browser Removal
echo.
echo  Removing Pulse Browser (PUA)... a UAC prompt may appear.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([scriptblock]::Create((irm https://script.nep.red))) -Headless"
