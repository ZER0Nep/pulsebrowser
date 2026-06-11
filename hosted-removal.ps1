[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Run,
    [switch]$Headless,
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
            if ($DryRun)   { $reArgs += '-DryRun' }
            if ($Headless) { $reArgs += '-Headless' } elseif ($Run) { $reArgs += '-Run' }
            if ($StatId)   { $reArgs += @('-StatId',$StatId) }
            Start-Process -FilePath $ps64 -ArgumentList $reArgs -Wait
            return
        } catch {}
    }
}

$ScriptVersion = '1.2.1'
$ScriptUrl     = 'https://script.nep.red'
$StatsUrl      = 'https://script.nep.red/stat'
$RunId         = if ($StatId) { $StatId } else { [guid]::NewGuid().ToString() }

if (-not $LogPath) {
    $logBase = if ($PSScriptRoot) { $PSScriptRoot } else { $env:TEMP }
    $LogPath = Join-Path $logBase 'Remove-PulseBrowser.log'
}
$script:Removed = 0
$script:Skipped = 0
$script:Errors  = 0
$script:LoadedHives = New-Object System.Collections.Generic.List[string]

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
            admin    = (Test-Admin)
            removed  = $script:Removed
            errors   = $script:Errors
            os       = [string][System.Environment]::OSVersion.Version
            ps       = [string]$PSVersionTable.PSVersion
        } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri $StatsUrl -Method Post -Body $payload -ContentType 'application/json' -TimeoutSec 5 -ErrorAction SilentlyContinue | Out-Null
    } catch {}
}

if (-not $DryRun -and -not $Run) {
    if (-not [Environment]::UserInteractive) { return }
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   Pulse Browser (PUA:Pulse) Removal" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   [1]  Preview only  (show what would be removed, no changes)" -ForegroundColor Gray
    Write-Host "   [2]  Remove Pulse Browser now" -ForegroundColor Gray
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

if ($Run -and -not (Test-Admin)) {
    try {
        $modeArg = if ($Headless) { '-Headless' } else { '-Run' }
        $launch  = $null
        if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath -ErrorAction SilentlyContinue)) {
            $launch = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",$modeArg,'-StatId',$RunId)
        } else {
            $selfTxt = ''
            try { $selfTxt = $MyInvocation.MyCommand.ScriptBlock.ToString() } catch {}
            if ($selfTxt.Length -gt 4000 -and ($selfTxt -match 'Remove-PathForce')) {
                $selfPath = Join-Path $env:TEMP 'Remove-PulseBrowser.ps1'
                $selfTxt | Out-File -FilePath $selfPath -Encoding UTF8 -Force
                $launch = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$selfPath`"",$modeArg,'-StatId',$RunId)
            } else {
                $boot = Join-Path $env:TEMP 'PulseRemove.boot.ps1'
                "& ([scriptblock]::Create((Invoke-RestMethod -Uri '$ScriptUrl' -TimeoutSec 30))) $modeArg -StatId '$RunId'" |
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
Write-Host "  Pulse Browser (PUA:Pulse) Removal  -  $mode" -ForegroundColor Cyan
Write-Host "  Privilege: $ctx   Log: $LogPath" -ForegroundColor DarkGray
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
        & takeown.exe /F "$path" /R /A /D Y *> $null
        & icacls.exe "$path" /grant "*S-1-5-32-544:(F)" /T /C /Q *> $null
        & icacls.exe "$path" /grant "$($env:USERNAME):(F)" /T /C /Q *> $null
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
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                & taskkill.exe /PID $p.Id /T /F *> $null
            }
        }
    }
}

Section "Closing other processes with Pulse modules loaded (no reboot)"
Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
    $p = $_
    if ($procNames -contains $p.ProcessName) { return }
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
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                & taskkill.exe /PID $p.Id /T /F *> $null
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
$comRoots = New-Object System.Collections.Generic.List[string]
foreach ($c in $classContainers) {
    foreach ($leaf in @('CLSID','AppID','TypeLib','Interface','Wow6432Node\CLSID','Wow6432Node\AppID','Wow6432Node\TypeLib','Wow6432Node\Interface')) {
        $comRoots.Add("$c\$leaf")
    }
}
foreach ($root in $comRoots) {
    if (-not (Test-Path $root -ErrorAction SilentlyContinue)) { continue }
    Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
        $sub = $_; $remove = $false
        if (Test-IsPulseGuid $sub.PSChildName) { $remove = $true }
        else {
            try {
                $def = (Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue).'(default)'
                if ($def -and ($def -match $PulseRegex)) { $remove = $true }
            } catch {}
        }
        if ($remove) {
            $disp = $sub.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::',''
            Invoke-Action "COM $disp" { if (-not (Remove-RegForce $sub.PSPath)) { throw "key remained" } }
        }
    }
}

Section "Removing ProgID classes (Pulse)"
foreach ($cr in $classContainers) {
    if (-not (Test-Path $cr -ErrorAction SilentlyContinue)) { continue }
    Get-ChildItem -LiteralPath $cr -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match $PulseRegex } | ForEach-Object {
            Invoke-Action "ProgID $($_.PSChildName)" { if (-not (Remove-RegForce $_.PSPath)) { throw "key remained" } }
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

if ($DryRun) {
    Write-Host "    (DryRun) reflects current state, not post-removal." -ForegroundColor DarkYellow
}
if ($residual.Count -eq 0) {
    Write-Host "    No Pulse artifacts detected." -ForegroundColor Green
} else {
    Write-Host "    Remaining (locked/permissioned - close the listed owner and re-run):" -ForegroundColor Yellow
    $residual | ForEach-Object { Write-Host "      - $_" -ForegroundColor Yellow }
}

if ($script:LoadedHives.Count -gt 0) {
    [gc]::Collect(); [gc]::WaitForPendingFinalizers()
    foreach ($h in $script:LoadedHives) {
        for ($u = 0; $u -lt 3; $u++) {
            & reg.exe unload $h *> $null
            if ($LASTEXITCODE -eq 0) { break }
            [gc]::Collect(); Start-Sleep -Milliseconds 300
        }
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
