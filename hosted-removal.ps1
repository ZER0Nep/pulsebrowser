[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Run,
    [switch]$Headless,
    [switch]$NoElevate,
    [switch]$Harden,
    [string]$StatId,
    [string]$LogPath
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

if ($Headless) { $Run = $true }

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess -and $PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue)) {
    $ps64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $ps64 -ErrorAction SilentlyContinue) {
        try {
            $reArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
            if ($DryRun)    { $reArgs += '-DryRun' }
            if ($Headless)  { $reArgs += '-Headless' } elseif ($Run) { $reArgs += '-Run' }
            if ($NoElevate) { $reArgs += '-NoElevate' }
            if ($Harden)    { $reArgs += '-Harden' }
            if ($StatId)    { $reArgs += @('-StatId',$StatId) }
            Start-Process -FilePath $ps64 -ArgumentList $reArgs -Wait
            return
        } catch {}
    }
}

$ScriptVersion = '1.3.2'
$ScriptUrl     = 'https://script.nep.red'
$StatsUrl      = 'https://script.nep.red/stat'
$RunId         = if ($StatId) { $StatId } else { [guid]::NewGuid().ToString() }

if (-not $LogPath) {
    $LogPath = Join-Path $env:TEMP 'PUAKILLER.log'
}
$script:Removed = 0
$script:Skipped = 0
$script:Errors  = 0
$script:LoadedHives = New-Object System.Collections.Generic.List[string]
$MySid = try { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { 'S-1-5-32-544' }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Send-Stat([string]$Phase) {
    try {
        $payload = @{
            v        = $ScriptVersion
            runId    = $RunId
            phase    = $Phase
            action   = if ($DryRun) { 'preview' } else { 'remove' }
            headless = [bool]$Headless
            noelev   = [bool]$NoElevate
            harden   = [bool]$Harden
            admin    = (Test-Admin)
            removed  = $script:Removed
            errors   = $script:Errors
            os       = [string][System.Environment]::OSVersion.Version
            ps       = [string]$PSVersionTable.PSVersion
        } | ConvertTo-Json -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $req = [System.Net.HttpWebRequest]::Create($StatsUrl)
        $req.Method = 'POST'
        $req.ContentType = 'application/json'
        $req.Timeout = 5000
        $req.ContentLength = $bytes.Length
        $rs = $req.GetRequestStream(); $rs.Write($bytes, 0, $bytes.Length); $rs.Close()
        $resp = $req.GetResponse(); $resp.Close()
    } catch {}
}

if (-not $DryRun -and -not $Run) {
    if (-not [Environment]::UserInteractive) { return }
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   PUA Removal  -  Pulse / OpenBook / ConvertMate / PDFEditor" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   [1]  Preview only  (show what would be removed, no changes)" -ForegroundColor Gray
    Write-Host "   [2]  Remove now" -ForegroundColor Gray
    Write-Host "   [3]  Exit" -ForegroundColor Gray
    Write-Host ""
    $choice = $null
    try { $choice = Read-Host "Select an option (1/2/3)" } catch { return }
    switch ($choice) {
        '1' { $DryRun = $true }
        '2' { $Run = $true }
        default { return }
    }
}

if ($Run -and -not $NoElevate -and -not (Test-Admin)) {
    try {
        $modeArg = if ($Headless) { '-Headless' } else { '-Run' }
        $extra   = @('-StatId',$RunId)
        if ($Harden) { $extra += '-Harden' }
        $hardStr = if ($Harden) { ' -Harden' } else { '' }
        $launch  = $null
        if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue)) {
            $launch = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",$modeArg) + $extra
        } else {
            $selfTxt = ''
            try { $selfTxt = $MyInvocation.MyCommand.ScriptBlock.ToString() } catch {}
            if ($selfTxt.Length -gt 4000 -and ($selfTxt -match 'Remove-PathForce')) {
                $selfPath = Join-Path $env:TEMP 'PUAKILLER-self.ps1'
                $selfTxt | Out-File -FilePath $selfPath -Encoding UTF8 -Force
                $launch = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$selfPath`"",$modeArg) + $extra
            } else {
                $boot = Join-Path $env:TEMP 'PUAKILLER-boot.ps1'
                "& ([scriptblock]::Create((Invoke-RestMethod -Uri '$ScriptUrl' -TimeoutSec 30))) $modeArg -StatId '$RunId'$hardStr" |
                    Out-File -FilePath $boot -Encoding UTF8 -Force
                $launch = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$boot`"")
            }
        }
        $psExe = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) { Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe' } else { 'powershell.exe' }
        Start-Process -FilePath $psExe -Verb RunAs -ArgumentList $launch -ErrorAction Stop
        return
    } catch {
        Write-Host "[!] Elevation declined/unavailable - continuing with current privileges." -ForegroundColor Yellow
    }
}

try { Start-Transcript -Path $LogPath -Append -ErrorAction SilentlyContinue | Out-Null } catch {}

Send-Stat 'start'

$mode = if ($DryRun) { 'DRY-RUN (no changes)' } else { 'LIVE REMOVAL' }
$ctx  = if (Test-Admin) { 'Administrator' } else { 'Standard user' }
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  PUA Removal (Pulse / OpenBook / ConvertMate / PDFEditor)  -  $mode" -ForegroundColor Cyan
Write-Host "  Privilege: $ctx   Log: $LogPath" -ForegroundColor DarkGray
if ($NoElevate -and -not (Test-Admin)) {
    Write-Host "  Scope: current user only (no elevation requested)" -ForegroundColor DarkGray
}
Write-Host "============================================================" -ForegroundColor Cyan

$PulseRegex = '(?i)(PulseSoftware|PulseBrowser|Pulse\s+Browser|Pulse\s+Software)'

$PulseGuids = @(
    '{2F4E88B4-E690-4E1F-AA9E-B7A4617F881D}',
    '{30546620-7888-4826-95be-9631ae2eea6e}',
    '{8EFCD3AA-AA03-4E1A-B316-9D654EEC019D}',
    '{A0C1F415-D2CE-4ddc-9B48-14E56FD55162}',
    '{E38B2D03-35C6-47FC-8DF5-1E4ED738436D}',
    '{a20c8354-a2f6-40c5-91d3-2f7efdf60deb}',
    '{d6acc642-8982-441d-949b-312d5ccb559f}'
) | ForEach-Object { $_.Trim('{','}').ToUpper() }

function Test-IsPulseGuid([string]$s) {
    if (-not $s) { return $false }
    return $PulseGuids -contains ($s.Trim('{','}').ToUpper())
}

function Get-RegSubKeys([string]$path) {
    try {
        $base = $null; $sub = ''
        if     ($path -match '^HKLM:\\(.+)$')                       { $base = [Microsoft.Win32.Registry]::LocalMachine; $sub = $Matches[1] }
        elseif ($path -match '^HKCU:\\(.+)$')                       { $base = [Microsoft.Win32.Registry]::CurrentUser;  $sub = $Matches[1] }
        elseif ($path -match '(?:Registry::)?HKEY_USERS\\(.+)$')         { $base = [Microsoft.Win32.Registry]::Users;        $sub = $Matches[1] }
        elseif ($path -match '(?:Registry::)?HKEY_LOCAL_MACHINE\\(.+)$') { $base = [Microsoft.Win32.Registry]::LocalMachine; $sub = $Matches[1] }
        if (-not $base) { return @() }
        $k = $base.OpenSubKey($sub)
        if (-not $k) { return @() }
        $n = $k.GetSubKeyNames(); $k.Close(); return $n
    } catch { return @() }
}

function Section([string]$t) {
    Write-Host ""
    Write-Host "[*] $t" -ForegroundColor White
}

function Remove-PathForce([string]$path) {
    if (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)) { return $true }
    for ($i = 0; $i -lt 5; $i++) {
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)) { return $true }
        } catch {}
        & icacls.exe "$path" /setowner "*$MySid" /T /C /Q *> $null
        & icacls.exe "$path" /grant "*S-1-5-32-544:(F)" /T /C /Q *> $null
        & icacls.exe "$path" /grant "*$($MySid):(F)" /T /C /Q *> $null
        try {
            Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue |
                ForEach-Object { try { $_.Attributes = 'Normal' } catch {} }
            (Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue).Attributes = 'Normal'
        } catch {}
        try { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop } catch {}
        if (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)) { return $true }
        Start-Sleep -Milliseconds 400
    }
    try {
        $stage = Join-Path ([System.IO.Path]::GetTempPath()) ('pulsedel_' + [System.IO.Path]::GetRandomFileName())
        Move-Item -LiteralPath $path -Destination $stage -Force -ErrorAction Stop
        try { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Stop } catch {}
        if (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)) {
            if (Test-Path -LiteralPath $stage -ErrorAction SilentlyContinue) {
                Write-Host "    [staged] in use - moved out of install path (neutralized): $stage" -ForegroundColor DarkYellow
            }
            return $true
        }
    } catch {}
    return (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue))
}

function Remove-RegForce([string]$psPath) {
    if (-not (Test-Path -LiteralPath $psPath -ErrorAction SilentlyContinue)) { return $true }
    try {
        Remove-Item -LiteralPath $psPath -Recurse -Force -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $psPath -ErrorAction SilentlyContinue)) { return $true }
    } catch {}
    $rp = $psPath -replace '^Microsoft\.PowerShell\.Core\\Registry::',''
    $rp = $rp -replace '^Registry::',''
    $rp = $rp -replace '^HKEY_LOCAL_MACHINE','HKLM'
    $rp = $rp -replace '^HKEY_CURRENT_USER','HKCU'
    $rp = $rp -replace '^HKEY_CLASSES_ROOT','HKCR'
    $rp = $rp -replace '^HKEY_USERS','HKU'
    $rp = $rp -replace '^HKLM:\\','HKLM\'
    $rp = $rp -replace '^HKCU:\\','HKCU\'
    $rp = $rp -replace '^HKCR:\\','HKCR\'
    $rp = $rp -replace '^HKU:\\','HKU\'
    & reg.exe delete "$rp" /f *> $null
    return (-not (Test-Path -LiteralPath $psPath -ErrorAction SilentlyContinue))
}

function Invoke-Action {
    param([string]$What, [scriptblock]$Do)
    if ($DryRun) {
        Write-Host "    [DRY] would remove: $What" -ForegroundColor DarkYellow
        $script:Skipped++
    } else {
        try {
            & $Do
            Write-Host "    [OK ] $What" -ForegroundColor Green
            $script:Removed++
        } catch {
            Write-Host "    [ERR] $What  ->  $($_.Exception.Message)" -ForegroundColor Red
            $script:Errors++
        }
    }
}

function Invoke-PuaSweep {
    param([string]$Name,[string]$Rx,[string[]]$Proc,[string[]]$Dirs,[string]$Pub = '',[bool]$Nw = $false)

    Section "Removing $Name (PUA) - processes"
    $sweepPasses = if ($DryRun) { 1 } else { 2 }
    foreach ($pass in 1..$sweepPasses) {
        Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
            $p = $_; $path = $null
            try { $path = $p.Path } catch {}
            $hit = $false
            if ($Proc -contains $p.ProcessName) { $hit = $true }
            elseif ($path -and ($path -match $Rx)) { $hit = $true }
            if ($hit) {
                $desc = "$($p.ProcessName) (PID $($p.Id))" + $(if ($path) { " [$path]" } else { "" })
                Invoke-Action "kill $desc" {
                    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                    & taskkill.exe /PID $p.Id /T /F *> $null
                    if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) { throw 'still running' }
                }
            }
        }
    }

    Section "Removing $Name (PUA) - scheduled tasks"
    if ($hasSchedCmd) {
        Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
            $t = $_; $hay = @($t.TaskName,$t.TaskPath)
            try { $hay += ($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) } catch {}
            if (($hay -join ' ') -match $Rx) {
                Invoke-Action "task $($t.TaskPath)$($t.TaskName)" {
                    Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
                }
            }
        }
    }
    & schtasks.exe /Query /FO CSV /NH 2>$null | ForEach-Object {
        if ($_ -match $Rx) {
            $tn = ($_ -split '","')[0].Trim('"')
            if ($tn) { Invoke-Action "task(schtasks) $tn" { & schtasks.exe /Delete /TN "$tn" /F *> $null; if ($LASTEXITCODE -ne 0) { throw "schtasks delete failed ($LASTEXITCODE)" } } }
        }
    }

    Section "Removing $Name (PUA) - services"
    Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | ForEach-Object {
        $svc = $_
        if ("$($svc.Name) $($svc.DisplayName) $($svc.PathName)" -match $Rx) {
            Invoke-Action "service $($svc.Name) [$($svc.DisplayName)]" {
                if ($svc.State -ne 'Stopped') { Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue; & taskkill.exe /F /FI "SERVICES eq $($svc.Name)" *> $null }
                & sc.exe config $svc.Name start= disabled *> $null
                & sc.exe delete $svc.Name *> $null
                if ($LASTEXITCODE -ne 0 -and (Get-Service -Name $svc.Name -ErrorAction SilentlyContinue)) { throw "sc delete failed ($LASTEXITCODE)" }
            }
        }
    }

    Section "Removing $Name (PUA) - autostart / app paths / classes"
    $rkList = New-Object System.Collections.Generic.List[string]
    foreach ($b in @('HKLM:\Software\Microsoft\Windows\CurrentVersion','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion')) { $rkList.Add("$b\Run"); $rkList.Add("$b\RunOnce") }
    foreach ($r in $softwareHiveRoots) { $rkList.Add("$r\Software\Microsoft\Windows\CurrentVersion\Run"); $rkList.Add("$r\Software\Microsoft\Windows\CurrentVersion\RunOnce") }
    foreach ($rk in $rkList) {
        if (-not (Test-Path $rk -ErrorAction SilentlyContinue)) { continue }
        $props = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -like 'PS*') { continue }
            if (("$($p.Name) $($p.Value)") -match $Rx) {
                Invoke-Action "Run value $rk\$($p.Name)" { Remove-ItemProperty -Path $rk -Name $p.Name -Force -ErrorAction Stop }
            }
        }
    }
    $apList = New-Object System.Collections.Generic.List[string]
    $apList.Add('HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths')
    $apList.Add('HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths')
    foreach ($r in $softwareHiveRoots) { $apList.Add("$r\Software\Microsoft\Windows\CurrentVersion\App Paths") }
    foreach ($apr in $apList) {
        if (-not (Test-Path $apr -ErrorAction SilentlyContinue)) { continue }
        Get-ChildItem -LiteralPath $apr -ErrorAction SilentlyContinue | ForEach-Object {
            $k = $_; $m = ($k.PSChildName -match $Rx)
            if (-not $m) { try { $d = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).'(default)'; if ($d -and ($d -match $Rx)) { $m = $true } } catch {} }
            if ($m) { Invoke-Action "AppPath $($k.PSChildName)" { if (-not (Remove-RegForce $k.PSPath)) { throw 'key remained' } } }
        }
    }
    foreach ($cr in $classContainers) {
        foreach ($nm in (Get-RegSubKeys $cr)) {
            if ($nm -match $Rx) { $kp = "$cr\$nm"; Invoke-Action "class $nm" { if (-not (Remove-RegForce $kp)) { throw 'key remained' } } }
        }
    }

    Section "Removing $Name (PUA) - uninstall entries"
    $unList = New-Object System.Collections.Generic.List[string]
    $unList.Add('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall')
    $unList.Add('HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
    foreach ($r in $softwareHiveRoots) { $unList.Add("$r\Software\Microsoft\Windows\CurrentVersion\Uninstall") }
    foreach ($ur in $unList) {
        if (-not (Test-Path $ur -ErrorAction SilentlyContinue)) { continue }
        Get-ChildItem -LiteralPath $ur -ErrorAction SilentlyContinue | ForEach-Object {
            $key = $_; $remove = ($key.PSChildName -match $Rx)
            if (-not $remove) {
                try {
                    $ip = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
                    if ("$($ip.DisplayName) $($ip.InstallLocation) $($ip.UninstallString) $($ip.DisplayIcon)" -match $Rx) { $remove = $true }
                    elseif ($Pub -and $ip.Publisher -and ($ip.Publisher -match $Pub)) { $remove = $true }
                } catch {}
            }
            if ($remove) { Invoke-Action "Uninstall key $($key.PSChildName)" { if (-not (Remove-RegForce $key.PSPath)) { throw 'key remained' } } }
        }
    }

    Section "Removing $Name (PUA) - files, shortcuts, temp, dropper"
    foreach ($d in ($Dirs | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $d -ErrorAction SilentlyContinue) {
            Invoke-Action "dir $d" { if (-not (Remove-PathForce $d)) { throw 'in use - could not fully remove' } }
        }
    }
    $lnkRoots = @()
    foreach ($u in $userRoots) {
        $lnkRoots += (Join-Path $u 'Desktop')
        $lnkRoots += (Join-Path $u 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs')
        $lnkRoots += (Join-Path $u 'AppData\Roaming\Microsoft\Internet Explorer\Quick Launch')
    }
    $lnkRoots += (Join-Path $env:Public 'Desktop')
    if ($env:ProgramData) { $lnkRoots += (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs') }
    foreach ($root in ($lnkRoots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root -ErrorAction SilentlyContinue)) { continue }
        Get-ChildItem -LiteralPath $root -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object {
            $lnk = $_; $is = ($lnk.Name -match $Rx)
            if (-not $is) { try { $sc = $wsh.CreateShortcut($lnk.FullName); if (("$($sc.TargetPath) $($sc.Arguments) $($sc.WorkingDirectory)") -match $Rx) { $is = $true } } catch {} }
            if ($is) { Invoke-Action "shortcut $($lnk.FullName)" { if (-not (Remove-PathForce $lnk.FullName)) { throw 'in use - could not remove' } } }
        }
    }
    foreach ($u in $userRoots) {
        $dl = Join-Path $u 'Downloads'
        if (-not (Test-Path -LiteralPath $dl -ErrorAction SilentlyContinue)) { continue }
        Get-ChildItem -LiteralPath $dl -Filter *.exe -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $Rx } | ForEach-Object {
            Invoke-Action "dropper $($_.FullName)" { if (-not (Remove-PathForce $_.FullName)) { throw 'in use - could not remove' } }
        }
    }
    $tmpRoots = @($env:TEMP)
    foreach ($u in $userRoots) { $tmpRoots += (Join-Path $u 'AppData\Local\Temp') }
    foreach ($tr in ($tmpRoots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $tr -ErrorAction SilentlyContinue)) { continue }
        Get-ChildItem -LiteralPath $tr -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $Rx } | ForEach-Object {
            Invoke-Action "temp $($_.FullName)" { if (-not (Remove-PathForce $_.FullName)) { throw 'in use - could not remove' } }
        }
        if ($Nw) {
            Get-ChildItem -LiteralPath $tr -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^nw[0-9]' } | ForEach-Object {
                $nwDir = $_.FullName; $match = $false
                foreach ($mf in @('package.json','package.nw','manifest.json')) {
                    $mp = Join-Path $nwDir $mf
                    if (Test-Path -LiteralPath $mp -ErrorAction SilentlyContinue) {
                        try { if (([System.IO.File]::ReadAllText($mp)) -match $Rx) { $match = $true; break } } catch {}
                    }
                }
                if (-not $match) {
                    try { if (Get-ChildItem -LiteralPath $nwDir -Filter *.exe -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $Rx }) { $match = $true } } catch {}
                }
                if ($match) { Invoke-Action "temp(nw) $nwDir" { if (-not (Remove-PathForce $nwDir)) { throw 'in use - could not remove' } } }
            }
        }
    }
}

$hasSchedCmd = [bool](Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)

Section "Stopping Pulse processes"
$procNames  = @('PulseBrowser','Pulse BrowserUpdate','PulseBrowserUpdate','PulseSoftwareUpdate')
$genericExe = @('updater','enterprise_companion','setup')
$passes = if ($DryRun) { 1 } else { 2 }
foreach ($pass in 1..$passes) {
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        $p = $_; $path = $null
        try { $path = $p.Path } catch {}
        $isPulse = $false
        if ($procNames -contains $p.ProcessName) { $isPulse = $true }
        elseif ($genericExe -contains $p.ProcessName -and $path -and ($path -match $PulseRegex)) { $isPulse = $true }
        elseif ($path -and ($path -match $PulseRegex)) { $isPulse = $true }
        if ($isPulse) {
            $desc = "$($p.ProcessName) (PID $($p.Id))" + $(if ($path) { " [$path]" } else { "" })
            Invoke-Action "kill $desc" {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                & taskkill.exe /PID $p.Id /T /F *> $null
                if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) { throw 'still running' }
            }
        }
    }
}

Section "Closing other processes with Pulse modules loaded (no reboot)"
Get-Process -Name explorer,dllhost,rundll32 -ErrorAction SilentlyContinue | ForEach-Object {
    $p = $_
    $hit = $null
    try { $hit = $p.Modules | Where-Object { $_.FileName -match $PulseRegex } } catch {}
    if ($hit) {
        if ($p.ProcessName -eq 'explorer') {
            Invoke-Action "restart explorer (Pulse shell extension loaded)" {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 800
                if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
            }
        } else {
            Invoke-Action "kill $($p.ProcessName) (PID $($p.Id)) - Pulse module loaded" {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                & taskkill.exe /PID $p.Id /T /F *> $null
                if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) { throw 'still running' }
            }
        }
    }
}

Section "Removing scheduled tasks"
if ($hasSchedCmd) {
    Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
        $t = $_; $hay = @($t.TaskName, $t.TaskPath)
        try { $hay += ($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) } catch {}
        if (($hay -join ' ') -match $PulseRegex) {
            $full = ($t.TaskPath + $t.TaskName)
            Invoke-Action "task $full" {
                Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
            }
        }
    }
}
& schtasks.exe /Query /FO CSV /NH 2>$null | ForEach-Object {
    if ($_ -match $PulseRegex) {
        $name = ($_ -split '","')[0].Trim('"')
        if ($name) {
            Invoke-Action "task(schtasks) $name" {
                & schtasks.exe /Delete /TN "$name" /F *> $null
                if ($LASTEXITCODE -ne 0) { throw "schtasks delete failed ($LASTEXITCODE)" }
            }
        }
    }
}

Section "Removing services"
Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | ForEach-Object {
    $svc = $_
    if ("$($svc.Name) $($svc.DisplayName) $($svc.PathName)" -match $PulseRegex) {
        Invoke-Action "service $($svc.Name) [$($svc.DisplayName)]" {
            if ($svc.State -ne 'Stopped') {
                Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                & taskkill.exe /F /FI "SERVICES eq $($svc.Name)" *> $null
            }
            & sc.exe config $svc.Name start= disabled *> $null
            & sc.exe delete $svc.Name *> $null
            if ($LASTEXITCODE -ne 0 -and (Get-Service -Name $svc.Name -ErrorAction SilentlyContinue)) {
                throw "sc delete failed ($LASTEXITCODE)"
            }
        }
    }
}

Section "Discovering user registry hives (all profiles)"
$softwareHiveRoots = New-Object System.Collections.Generic.List[string]
$classesHiveRoots  = New-Object System.Collections.Generic.List[string]
$loadedSids = @{}
Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue | ForEach-Object {
    $n = $_.PSChildName
    if ($n -match '^S-1-5-21-[\d-]+_Classes$') {
        $classesHiveRoots.Add("Registry::HKEY_USERS\$n")
        $loadedSids[($n -replace '_Classes$','')] = $true
    } elseif ($n -match '^S-1-5-21-[\d-]+$') {
        $softwareHiveRoots.Add("Registry::HKEY_USERS\$n")
        $loadedSids[$n] = $true
    }
}
if (Test-Admin) {
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue | ForEach-Object {
        $sid = $_.PSChildName
        if ($sid -match '^S-1-5-21-[\d-]+$' -and -not $loadedSids[$sid]) {
            $pp = (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
            if ($pp) {
                $nt = Join-Path $pp 'NTUSER.DAT'
                if (Test-Path -LiteralPath $nt -ErrorAction SilentlyContinue) {
                    & reg.exe load "HKU\PulseTmp_$sid" "$nt" *> $null
                    if ($LASTEXITCODE -eq 0) {
                        $script:LoadedHives.Add("HKU\PulseTmp_$sid")
                        $softwareHiveRoots.Add("Registry::HKEY_USERS\PulseTmp_$sid")
                    }
                }
                $uc = Join-Path $pp 'AppData\Local\Microsoft\Windows\UsrClass.dat'
                if (Test-Path -LiteralPath $uc -ErrorAction SilentlyContinue) {
                    & reg.exe load "HKU\PulseTmpC_$sid" "$uc" *> $null
                    if ($LASTEXITCODE -eq 0) {
                        $script:LoadedHives.Add("HKU\PulseTmpC_$sid")
                        $classesHiveRoots.Add("Registry::HKEY_USERS\PulseTmpC_$sid")
                    }
                }
            }
        }
    }
}
Write-Host "    user software hives: $($softwareHiveRoots.Count)   class hives: $($classesHiveRoots.Count)" -ForegroundColor DarkGray

$classContainers = New-Object System.Collections.Generic.List[string]
$classContainers.Add('HKLM:\Software\Classes')
$classContainers.Add('HKLM:\Software\Wow6432Node\Classes')
foreach ($r in $softwareHiveRoots) { $classContainers.Add("$r\Software\Classes") }
foreach ($r in $classesHiveRoots)  { $classContainers.Add($r) }

Section "Removing autostart (Run) entries"
$runKeys = New-Object System.Collections.Generic.List[string]
foreach ($b in @('HKLM:\Software\Microsoft\Windows\CurrentVersion','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion')) {
    $runKeys.Add("$b\Run"); $runKeys.Add("$b\RunOnce")
}
foreach ($r in $softwareHiveRoots) {
    $runKeys.Add("$r\Software\Microsoft\Windows\CurrentVersion\Run")
    $runKeys.Add("$r\Software\Microsoft\Windows\CurrentVersion\RunOnce")
}
foreach ($rk in $runKeys) {
    if (-not (Test-Path $rk -ErrorAction SilentlyContinue)) { continue }
    $props = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
    if (-not $props) { continue }
    foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -like 'PS*') { continue }
        if (("$($p.Name) $($p.Value)") -match $PulseRegex) {
            Invoke-Action "Run value $rk\$($p.Name)" {
                Remove-ItemProperty -Path $rk -Name $p.Name -Force -ErrorAction Stop
            }
        }
    }
}

Section "Removing App Paths"
$appPathRoots = New-Object System.Collections.Generic.List[string]
$appPathRoots.Add('HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths')
$appPathRoots.Add('HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths')
foreach ($r in $softwareHiveRoots) { $appPathRoots.Add("$r\Software\Microsoft\Windows\CurrentVersion\App Paths") }
foreach ($apr in $appPathRoots) {
    if (-not (Test-Path $apr -ErrorAction SilentlyContinue)) { continue }
    Get-ChildItem -LiteralPath $apr -ErrorAction SilentlyContinue | ForEach-Object {
        $k = $_; $match = ($k.PSChildName -match $PulseRegex)
        if (-not $match) {
            try {
                $d = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).'(default)'
                if ($d -and ($d -match $PulseRegex)) { $match = $true }
            } catch {}
        }
        if ($match) {
            Invoke-Action "AppPath $($k.PSChildName)" { if (-not (Remove-RegForce $k.PSPath)) { throw 'key remained' } }
        }
    }
}

Section "Removing registry keys (vendor / policies)"
$vendorKeys = New-Object System.Collections.Generic.List[string]
$vendorKeys.Add('HKLM:\Software\PulseSoftware')
$vendorKeys.Add('HKLM:\Software\WOW6432Node\PulseSoftware')
$vendorKeys.Add('HKLM:\Software\Policies\PulseSoftware')
$vendorKeys.Add('HKLM:\Software\WOW6432Node\Policies\PulseSoftware')
foreach ($r in $softwareHiveRoots) {
    $vendorKeys.Add("$r\Software\PulseSoftware")
    $vendorKeys.Add("$r\Software\Policies\PulseSoftware")
}
foreach ($k in $vendorKeys) {
    if (Test-Path $k -ErrorAction SilentlyContinue) {
        Invoke-Action "regkey $k" { if (-not (Remove-RegForce $k)) { throw "key remained" } }
    }
}

Section "Removing COM / AppID / TypeLib / Interface registrations (Pulse only)"
foreach ($c in $classContainers) {
    foreach ($leaf in @('CLSID','AppID','Interface','Wow6432Node\CLSID','Wow6432Node\AppID','Wow6432Node\Interface')) {
        $root = "$c\$leaf"
        foreach ($g in $PulseGuids) {
            $kp = "$root\{$g}"
            if (Test-Path -LiteralPath $kp -ErrorAction SilentlyContinue) {
                Invoke-Action "COM $kp" { if (-not (Remove-RegForce $kp)) { throw "key remained" } }
            }
        }
    }
    foreach ($tl in @("$c\TypeLib","$c\Wow6432Node\TypeLib")) {
        if (-not (Test-Path $tl -ErrorAction SilentlyContinue)) { continue }
        Get-ChildItem -LiteralPath $tl -ErrorAction SilentlyContinue | ForEach-Object {
            $sub = $_; $remove = (Test-IsPulseGuid $sub.PSChildName)
            if (-not $remove) {
                try {
                    $def = (Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue).'(default)'
                    if ($def -and ($def -match $PulseRegex)) { $remove = $true }
                } catch {}
            }
            if ($remove) {
                $disp = $sub.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::',''
                Invoke-Action "TypeLib $disp" { if (-not (Remove-RegForce $sub.PSPath)) { throw "key remained" } }
            }
        }
    }
}

Section "Removing ProgID classes (Pulse)"
foreach ($cr in $classContainers) {
    foreach ($name in (Get-RegSubKeys $cr)) {
        if ($name -match $PulseRegex) {
            $kp = "$cr\$name"
            Invoke-Action "ProgID $name" { if (-not (Remove-RegForce $kp)) { throw "key remained" } }
        }
    }
}

Section "Removing Add/Remove Programs (Uninstall) entries"
$uninstallRoots = New-Object System.Collections.Generic.List[string]
$uninstallRoots.Add('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall')
$uninstallRoots.Add('HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
foreach ($r in $softwareHiveRoots) { $uninstallRoots.Add("$r\Software\Microsoft\Windows\CurrentVersion\Uninstall") }
foreach ($ur in $uninstallRoots) {
    if (-not (Test-Path $ur -ErrorAction SilentlyContinue)) { continue }
    Get-ChildItem -LiteralPath $ur -ErrorAction SilentlyContinue | ForEach-Object {
        $key = $_; $remove = (Test-IsPulseGuid $key.PSChildName)
        if (-not $remove) {
            try {
                $ip = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
                if ("$($ip.DisplayName) $($ip.Publisher) $($ip.InstallLocation) $($ip.UninstallString)" -match $PulseRegex) { $remove = $true }
            } catch {}
        }
        if ($remove) {
            Invoke-Action "Uninstall key $($key.PSChildName)" { if (-not (Remove-RegForce $key.PSPath)) { throw "key remained" } }
        }
    }
}

Section "Removing files and folders"
$userRoots = New-Object System.Collections.Generic.List[string]
$userRoots.Add($env:USERPROFILE)
try {
    Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue | ForEach-Object {
        $pp = (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
        if ($pp -and (Test-Path -LiteralPath $pp -ErrorAction SilentlyContinue)) { $userRoots.Add($pp) }
    }
} catch {}
try {
    $profilesDir = Split-Path -Parent $env:USERPROFILE
    if ($profilesDir -and (Test-Path -LiteralPath $profilesDir -ErrorAction SilentlyContinue)) {
        Get-ChildItem -LiteralPath $profilesDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $userRoots.Add($_.FullName) }
    }
} catch {}
$userRoots = $userRoots | Where-Object { $_ } | Select-Object -Unique

$dirCandidates = New-Object System.Collections.Generic.List[string]
if ($env:ProgramFiles)        { $dirCandidates.Add((Join-Path $env:ProgramFiles 'PulseSoftware')) }
if (${env:ProgramFiles(x86)}) { $dirCandidates.Add((Join-Path ${env:ProgramFiles(x86)} 'PulseSoftware')) }
if ($env:ProgramData)         { $dirCandidates.Add((Join-Path $env:ProgramData 'PulseSoftware')) }
foreach ($u in $userRoots) {
    $dirCandidates.Add((Join-Path $u 'AppData\Local\PulseSoftware'))
    $dirCandidates.Add((Join-Path $u 'AppData\Roaming\PulseSoftware'))
    $dirCandidates.Add((Join-Path $u 'AppData\Local\Pulse Browser'))
    $dirCandidates.Add((Join-Path $u 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Pulse Browser'))
}
if ($env:ProgramData) { $dirCandidates.Add((Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Pulse Browser')) }

foreach ($d in ($dirCandidates | Select-Object -Unique)) {
    if (Test-Path -LiteralPath $d -ErrorAction SilentlyContinue) {
        Invoke-Action "dir $d" { if (-not (Remove-PathForce $d)) { throw 'in use - could not fully remove' } }
    }
}

Section "Removing Pulse shortcuts (.lnk)"
$lnkScanRoots = @()
foreach ($u in $userRoots) {
    $lnkScanRoots += (Join-Path $u 'Desktop')
    $lnkScanRoots += (Join-Path $u 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs')
    $lnkScanRoots += (Join-Path $u 'AppData\Roaming\Microsoft\Internet Explorer\Quick Launch')
}
$lnkScanRoots += (Join-Path $env:Public 'Desktop')
if ($env:ProgramData) { $lnkScanRoots += (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs') }
$wsh = New-Object -ComObject WScript.Shell
foreach ($root in ($lnkScanRoots | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $root -ErrorAction SilentlyContinue)) { continue }
    Get-ChildItem -LiteralPath $root -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object {
        $lnk = $_; $isPulse = ($lnk.Name -match $PulseRegex)
        if (-not $isPulse) {
            try {
                $sc = $wsh.CreateShortcut($lnk.FullName)
                if (("$($sc.TargetPath) $($sc.Arguments) $($sc.WorkingDirectory)") -match $PulseRegex) { $isPulse = $true }
            } catch {}
        }
        if ($isPulse) {
            Invoke-Action "shortcut $($lnk.FullName)" { if (-not (Remove-PathForce $lnk.FullName)) { throw 'in use - could not remove' } }
        }
    }
}

Section "Removing temp leftovers"
$tempRoots = @($env:TEMP, "$env:SystemRoot\Temp")
foreach ($u in $userRoots) { $tempRoots += (Join-Path $u 'AppData\Local\Temp') }
foreach ($tr in ($tempRoots | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $tr -ErrorAction SilentlyContinue)) { continue }
    Get-ChildItem -LiteralPath $tr -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $PulseRegex } | ForEach-Object {
            Invoke-Action "temp $($_.FullName)" { if (-not (Remove-PathForce $_.FullName)) { throw 'in use - could not remove' } }
        }
}

Section "Removing the Pulse installer (dropper)"
foreach ($u in $userRoots) {
    $dlDir = Join-Path $u 'Downloads'
    if (-not (Test-Path -LiteralPath $dlDir -ErrorAction SilentlyContinue)) { continue }
    Get-ChildItem -LiteralPath $dlDir -Filter *.exe -File -ErrorAction SilentlyContinue | ForEach-Object {
        $dl = $_.FullName
        $isPulse = ($_.Name -match $PulseRegex)
        if (-not $isPulse -and $_.Length -le 67108864) {
            try {
                $buf   = [System.IO.File]::ReadAllBytes($dl)
                $ascii = [System.Text.Encoding]::ASCII.GetString($buf)
                $uni   = [System.Text.Encoding]::Unicode.GetString($buf)
                if (($ascii -match 'PulseSoftware|PulseBrowser') -or ($uni -match 'PulseSoftware|PulseBrowser')) { $isPulse = $true }
            } catch {}
        }
        if ($isPulse) {
            Invoke-Action "dropper $dl" { if (-not (Remove-PathForce $dl)) { throw 'in use - could not remove' } }
        }
    }
}

$extraPuas = @(
    @{ Name='OpenBook';    Rx='(?i)\bOpenBook\b';    Proc=@('OpenBook');    Pub='';                       Nw=$true  },
    @{ Name='ConvertMate'; Rx='(?i)\bConvertMate\b'; Proc=@('ConvertMate'); Pub='(?i)Amaryllis';           Nw=$false },
    @{ Name='PDFEditor';   Rx='(?i)\bPDFEditor\b';   Proc=@('PDFEditor');   Pub='(?i)(AppSuite|Eclipse Media)'; Nw=$false },
    # EpiBrowser / EpiStart - Chromium-clone PUA. Vendor folder is %LOCALAPPDATA%\EPISoftware (all-caps EPI), signed with an
    # abused code-signing cert "Byte Media Sdn. Bhd." (Johor, MY); part of the TamperedChef shell-company cluster.
    # Verified: todyl.com/blog/epibrowser, pcrisk.com/removal-guides/32056, file.net, any.run. Detections: Malwarebytes
    # PUP.Optional.EpiBrowser, Sophos "Epi Browser (PUA)". Install: AppData\Local\EPISoftware\EpiBrowser\Application\<ver>\
    # (epibrowser.exe, notification_helper.exe); stager Temp\epibrowser-bin\epibrowser.exe. Reg: HKCU\Software\EPISoftware\
    # {EpiBrowser*,Update*} and HKCU\Software\Policies\EPISoftware\EpiBrowser. Tasks: EpiBrowserUpdate, EpiBrowserStartup.
    # Verified full SHA256: installer 06b89c8a6bc45c652a12af9bddf17aed478f7bbd0c447a745c05f7486a7c2044,
    #                       app       2fe2d16e51488337de25bb02c7ca4a06e2b7e3229cd2af9903db7c9efdf88e31.
    # Name='EPISoftware' so the folder sweep removes the whole vendor tree (EpiBrowser + Application + Update). The broad Rx
    # catches EpiBrowser/EpiStart artifacts (tasks, run-values, shortcuts) regardless of folder; notification_helper.exe is
    # killed via path-match (under EPISoftware) rather than by generic process name to avoid touching other Chromium browsers.
    @{ Name='EPISoftware'; Rx='(?i)(EPISoftware|EpiBrowser|Epi\s+Browser|EpiStart)'; Proc=@('epibrowser','setup.epibrowser'); Pub='(?i)(EPISoftware|EPI\s*Software)'; Nw=$false }
)
foreach ($pua in $extraPuas) {
    $pd = New-Object System.Collections.Generic.List[string]
    foreach ($u in $userRoots) {
        $pd.Add((Join-Path $u "AppData\Local\$($pua.Name)"))
        $pd.Add((Join-Path $u "AppData\Roaming\$($pua.Name)"))
        $pd.Add((Join-Path $u "AppData\Local\Programs\$($pua.Name)"))
        $pd.Add((Join-Path $u "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\$($pua.Name)"))
    }
    if ($env:ProgramFiles)        { $pd.Add((Join-Path $env:ProgramFiles $pua.Name)) }
    if (${env:ProgramFiles(x86)}) { $pd.Add((Join-Path ${env:ProgramFiles(x86)} $pua.Name)) }
    if ($env:ProgramData)         { $pd.Add((Join-Path $env:ProgramData $pua.Name)); $pd.Add((Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\$($pua.Name)")) }
    $pua.Dirs = $pd
    Invoke-PuaSweep -Name $pua.Name -Rx $pua.Rx -Proc $pua.Proc -Dirs $pua.Dirs -Pub $pua.Pub -Nw $pua.Nw
}

Section "Verification"
$residual = @()
foreach ($k in $vendorKeys) { if (Test-Path $k -ErrorAction SilentlyContinue) { $residual += "reg: $k" } }
foreach ($d in ($dirCandidates | Select-Object -Unique)) { if (Test-Path -LiteralPath $d -ErrorAction SilentlyContinue) { $residual += "dir: $d" } }
if ($hasSchedCmd) {
    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { (($_.TaskName + $_.TaskPath) -match $PulseRegex) } |
        ForEach-Object { $residual += "task: $($_.TaskPath)$($_.TaskName)" }
}
Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
    Where-Object { "$($_.Name) $($_.DisplayName) $($_.PathName)" -match $PulseRegex } |
    ForEach-Object { $residual += "svc: $($_.Name)" }

foreach ($pua in $extraPuas) {
    foreach ($d in ($pua.Dirs | Select-Object -Unique)) { if (Test-Path -LiteralPath $d -ErrorAction SilentlyContinue) { $residual += "dir: $d" } }
    if ($hasSchedCmd) {
        Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { (($_.TaskName + $_.TaskPath) -match $pua.Rx) } |
            ForEach-Object { $residual += "task: $($_.TaskPath)$($_.TaskName)" }
    }
    Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { "$($_.Name) $($_.DisplayName) $($_.PathName)" -match $pua.Rx } |
        ForEach-Object { $residual += "svc: $($_.Name)" }
}

if ($DryRun) {
    Write-Host "    (DryRun) reflects current state, not post-removal." -ForegroundColor DarkYellow
}
if ($residual.Count -eq 0) {
    Write-Host "    No PUA artifacts detected (Pulse / OpenBook / ConvertMate / PDFEditor / EpiBrowser)." -ForegroundColor Green
} else {
    Write-Host "    Remaining (locked/permissioned - close the listed owner and re-run):" -ForegroundColor Yellow
    $residual | ForEach-Object { Write-Host "      - $_" -ForegroundColor Yellow }
}

if ($Harden) {
    Section "Hardening (block reinstall - user scope, no admin)"
    $vaxPaths = New-Object System.Collections.Generic.List[string]
    foreach ($u in ($userRoots | Where-Object { $_ -match '(?i)\\Users\\[^\\]+$' -and $_ -notmatch '(?i)\\Users\\(Public|Default|Default User|All Users)$' })) {
        $vaxPaths.Add((Join-Path $u 'AppData\Local\PulseSoftware'))
        $vaxPaths.Add((Join-Path $u 'AppData\Local\Pulse Browser'))
        $vaxPaths.Add((Join-Path $u 'AppData\Roaming\PulseSoftware'))
        $vaxPaths.Add((Join-Path $u 'AppData\Local\OpenBook'))
        $vaxPaths.Add((Join-Path $u 'AppData\Roaming\OpenBook'))
        $vaxPaths.Add((Join-Path $u 'AppData\Local\ConvertMate'))
        $vaxPaths.Add((Join-Path $u 'AppData\Local\PDFEditor'))
        $vaxPaths.Add((Join-Path $u 'AppData\Roaming\PDFEditor'))
        $vaxPaths.Add((Join-Path $u 'AppData\Local\Programs\PDFEditor'))
        $vaxPaths.Add((Join-Path $u 'AppData\Local\EPISoftware'))
        $vaxPaths.Add((Join-Path $u 'AppData\Roaming\EPISoftware'))
        $vaxPaths.Add((Join-Path $u 'AppData\Local\Programs\EPISoftware'))
    }
    foreach ($vp in ($vaxPaths | Select-Object -Unique)) {
        $parent = Split-Path -Parent $vp
        if (-not (Test-Path -LiteralPath $parent -ErrorAction SilentlyContinue)) { continue }
        if ($DryRun) {
            Write-Host "    [DRY] would plant block: $vp" -ForegroundColor DarkYellow
            $script:Skipped++
        } else {
            try {
                if (Test-Path -LiteralPath $vp -ErrorAction SilentlyContinue) {
                    if (-not (Remove-PathForce $vp)) { throw 'existing path could not be cleared' }
                }
                New-Item -ItemType File -Path $vp -Force -ErrorAction Stop | Out-Null
                $fi = Get-Item -LiteralPath $vp -Force -ErrorAction SilentlyContinue
                if ($fi) { $fi.Attributes = 'ReadOnly,Hidden,System' }
                & icacls.exe "$vp" /inheritance:r /grant:r "*S-1-5-32-544:(F)" /deny "*S-1-1-0:(WD,AD,DE,DC)" *> $null
                Write-Host "    [OK ] blocked: $vp" -ForegroundColor Green
                $script:Removed++
            } catch {
                Write-Host "    [ERR] vaccine $vp  ->  $($_.Exception.Message)" -ForegroundColor Red
                $script:Errors++
            }
        }
    }
}

if ($script:LoadedHives.Count -gt 0) {
    foreach ($h in $script:LoadedHives) {
        $unloaded = $false
        for ($u = 0; $u -lt 6; $u++) {
            [gc]::Collect(); [gc]::WaitForPendingFinalizers(); [gc]::Collect(); [gc]::WaitForPendingFinalizers()
            $null = & reg.exe unload $h 2>&1
            if ($LASTEXITCODE -eq 0) { $unloaded = $true; break }
            Start-Sleep -Milliseconds 400
        }
        if (-not $unloaded) { Write-Host "    [info] temp hive stays mounted until session end (not an error): $h" -ForegroundColor DarkGray }
    }
}

Send-Stat 'done'

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ("  Done. Removed: {0}  Previewed: {1}  Errors: {2}" -f $script:Removed,$script:Skipped,$script:Errors) -ForegroundColor Cyan
if ($DryRun) { Write-Host "  Preview only - run again and choose [2] to remove." -ForegroundColor Yellow }
Write-Host "============================================================" -ForegroundColor Cyan

try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}

if ([Environment]::UserInteractive -and -not $Headless) {
    Write-Host ""
    try { Read-Host "Press Enter to close" | Out-Null } catch {}
}
