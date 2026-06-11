[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Run,
    [switch]$Headless,
    [string]$LogPath
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

if ($Headless) { $Run = $true }

$ScriptVersion = '1.1.0'
$StatsUrl      = 'https://script.nep.red/stat'
$RunId         = [guid]::NewGuid().ToString()

if (-not $LogPath) {
    $logBase = if ($PSScriptRoot) { $PSScriptRoot } else { $env:TEMP }
    $LogPath = Join-Path $logBase 'Remove-PulseBrowser.log'
}
$script:Removed = 0
$script:Skipped = 0
$script:Errors  = 0

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
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   Pulse Browser (PUA:Pulse) Removal" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   [1]  Preview only  (show what would be removed, no changes)" -ForegroundColor Gray
    Write-Host "   [2]  Remove Pulse Browser now" -ForegroundColor Gray
    Write-Host "   [3]  Exit" -ForegroundColor Gray
    Write-Host ""
    $choice = Read-Host "Select an option (1/2/3)"
    switch ($choice) {
        '1' { $DryRun = $true }
        '2' { $Run = $true }
        default { return }
    }
}

if ($Run -and -not (Test-Admin)) {
    try {
        if ($PSCommandPath) {
            $selfPath = $PSCommandPath
        } else {
            $selfPath = Join-Path $env:TEMP 'Remove-PulseBrowser.ps1'
            $MyInvocation.MyCommand.ScriptBlock.ToString() | Out-File -FilePath $selfPath -Encoding UTF8 -Force
        }
        $modeArg = if ($Headless) { '-Headless' } else { '-Run' }
        $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$selfPath`"",$modeArg)
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -ErrorAction Stop
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
    if (-not (Test-Path -LiteralPath $path)) { return $true }
    for ($i = 0; $i -lt 5; $i++) {
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $path)) { return $true }
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
        if (-not (Test-Path -LiteralPath $path)) { return $true }
        Start-Sleep -Milliseconds 400
    }
    try {
        $stage = Join-Path ([System.IO.Path]::GetTempPath()) ('pulsedel_' + [System.IO.Path]::GetRandomFileName())
        Move-Item -LiteralPath $path -Destination $stage -Force -ErrorAction Stop
        try { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Stop } catch {}
        if (-not (Test-Path -LiteralPath $path)) {
            if (Test-Path -LiteralPath $stage) {
                Write-Host "    [staged] in use - moved out of install path (neutralized): $stage" -ForegroundColor DarkYellow
            }
            return $true
        }
    } catch {}
    return (-not (Test-Path -LiteralPath $path))
}

function Remove-RegForce([string]$psPath) {
    if (-not (Test-Path $psPath)) { return $true }
    try {
        Remove-Item -LiteralPath $psPath -Recurse -Force -ErrorAction Stop
        if (-not (Test-Path $psPath)) { return $true }
    } catch {}
    $rp = $psPath -replace '^Microsoft\.PowerShell\.Core\\Registry::',''
    $rp = $rp -replace '^HKEY_LOCAL_MACHINE','HKLM' -replace '^HKEY_CURRENT_USER','HKCU' `
              -replace '^HKEY_CLASSES_ROOT','HKCR' -replace '^HKEY_USERS','HKU'
    $rp = $rp -replace '^HKLM:\\','HKLM\' -replace '^HKCU:\\','HKCU\' `
              -replace '^HKCR:\\','HKCR\' -replace '^HKU:\\','HKU\'
    & reg.exe delete "$rp" /f *> $null
    return (-not (Test-Path $psPath))
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

Section "Stopping Pulse processes"
$procNames  = @('PulseBrowser','Pulse BrowserUpdate','PulseBrowserUpdate','PulseSoftwareUpdate','setup')
$genericExe = @('updater','enterprise_companion')
foreach ($pass in 1..2) {
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

Section "Closing processes with Pulse modules loaded (no reboot)"
Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
    $p = $_; $hit = $null
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

Section "Removing autostart (Run) entries"
$runKeys = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce'
)
foreach ($rk in $runKeys) {
    if (-not (Test-Path $rk)) { continue }
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

Section "Removing registry keys (vendor / policies)"
$vendorKeys = @(
    'HKCU:\Software\PulseSoftware',
    'HKLM:\Software\PulseSoftware',
    'HKLM:\Software\WOW6432Node\PulseSoftware',
    'HKCU:\Software\Policies\PulseSoftware',
    'HKLM:\Software\Policies\PulseSoftware',
    'HKLM:\Software\WOW6432Node\Policies\PulseSoftware'
)
foreach ($k in $vendorKeys) {
    if (Test-Path $k) {
        Invoke-Action "regkey $k" { if (-not (Remove-RegForce $k)) { throw "key remained" } }
    }
}

Section "Removing COM / AppID / TypeLib registrations (Pulse GUIDs only)"
$comRoots = @(
    'HKCU:\Software\Classes\CLSID','HKLM:\Software\Classes\CLSID','HKLM:\Software\Classes\WOW6432Node\CLSID',
    'HKCU:\Software\Classes\AppID','HKLM:\Software\Classes\AppID','HKLM:\Software\Classes\WOW6432Node\AppID',
    'HKCU:\Software\Classes\TypeLib','HKLM:\Software\Classes\TypeLib','HKLM:\Software\Classes\WOW6432Node\TypeLib'
)
foreach ($root in $comRoots) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
        $sub = $_; $remove = $false
        if (Test-IsPulseGuid $sub.PSChildName) { $remove = $true }
        else {
            try {
                $def = (Get-ItemProperty -Path $sub.PSPath -ErrorAction SilentlyContinue).'(default)'
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
foreach ($cr in @('HKCU:\Software\Classes','HKLM:\Software\Classes','HKLM:\Software\Classes\WOW6432Node')) {
    if (-not (Test-Path $cr)) { continue }
    Get-ChildItem -Path $cr -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match $PulseRegex } | ForEach-Object {
            Invoke-Action "ProgID $($_.PSChildName)" { if (-not (Remove-RegForce $_.PSPath)) { throw "key remained" } }
        }
}

Section "Removing Add/Remove Programs (Uninstall) entries"
$uninstallRoots = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
foreach ($ur in $uninstallRoots) {
    if (-not (Test-Path $ur)) { continue }
    Get-ChildItem -Path $ur -ErrorAction SilentlyContinue | ForEach-Object {
        $key = $_; $remove = (Test-IsPulseGuid $key.PSChildName)
        if (-not $remove) {
            try {
                $ip = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
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
        $pp = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
        if ($pp -and (Test-Path -LiteralPath $pp)) { $userRoots.Add($pp) }
    }
} catch {}
try {
    $profilesDir = Split-Path -Parent $env:USERPROFILE
    if ($profilesDir -and (Test-Path -LiteralPath $profilesDir)) {
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
    if (Test-Path -LiteralPath $d) {
        Invoke-Action "dir $d" { if (-not (Remove-PathForce $d)) { } }
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
    if (-not (Test-Path -LiteralPath $root)) { continue }
    Get-ChildItem -LiteralPath $root -Recurse -Filter *.lnk -ErrorAction SilentlyContinue | ForEach-Object {
        $lnk = $_; $isPulse = ($lnk.Name -match $PulseRegex)
        if (-not $isPulse) {
            try {
                $sc = $wsh.CreateShortcut($lnk.FullName)
                if (("$($sc.TargetPath) $($sc.Arguments) $($sc.WorkingDirectory)") -match $PulseRegex) { $isPulse = $true }
            } catch {}
        }
        if ($isPulse) {
            Invoke-Action "shortcut $($lnk.FullName)" { if (-not (Remove-PathForce $lnk.FullName)) { } }
        }
    }
}

Section "Removing temp leftovers"
$tempRoots = @($env:TEMP, "$env:SystemRoot\Temp")
foreach ($u in $userRoots) { $tempRoots += (Join-Path $u 'AppData\Local\Temp') }
foreach ($tr in ($tempRoots | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $tr)) { continue }
    Get-ChildItem -LiteralPath $tr -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $PulseRegex } | ForEach-Object {
            Invoke-Action "temp $($_.FullName)" { if (-not (Remove-PathForce $_.FullName)) { } }
        }
}

Section "Removing the Pulse installer (dropper)"
foreach ($u in $userRoots) {
    $dl = Join-Path $u 'Downloads\setup.exe'
    if (Test-Path -LiteralPath $dl) {
        $isPulse = $false
        try {
            $ascii = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($dl))
            if ($ascii -match 'PulseSoftware|PulseBrowser') { $isPulse = $true }
        } catch {}
        if ($isPulse) {
            Invoke-Action "dropper $dl" { if (-not (Remove-PathForce $dl)) { } }
        } else {
            Write-Host "    [skip] $dl is not the Pulse installer" -ForegroundColor DarkGray
        }
    }
}

Section "Verification"
$residual = @()
foreach ($k in $vendorKeys) { if (Test-Path $k) { $residual += "reg: $k" } }
foreach ($d in ($dirCandidates | Select-Object -Unique)) { if (Test-Path -LiteralPath $d) { $residual += "dir: $d" } }
Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { (($_.TaskName + $_.TaskPath) -match $PulseRegex) } |
    ForEach-Object { $residual += "task: $($_.TaskPath)$($_.TaskName)" }
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
