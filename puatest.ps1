$ErrorActionPreference = 'Stop'
$base = Join-Path $env:TEMP ('puatest_' + [guid]::NewGuid().ToString('N').Substring(0,8))
$log  = Join-Path $env:TEMP 'PUATEST.log'
if (Test-Path $log) { Remove-Item $log -Force }

$fix = @{}
function Track($k,$v){ $script:fix[$k]=$v }

# --- plant OpenBook fixtures ---
$obDir = Join-Path $env:LOCALAPPDATA 'OpenBook'
New-Item -ItemType Directory -Path $obDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $obDir 'OpenBook.exe') -Value 'stub' -Force
Track 'ob-dir' $obDir

$nwDir = Join-Path $env:TEMP ('nw' + '99001_2')
New-Item -ItemType Directory -Path $nwDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $nwDir 'package.json') -Value '{"name":"OpenBook","main":"index.html"}' -Force
Track 'ob-nw' $nwDir

$runK = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
New-ItemProperty -Path $runK -Name 'OpenBook' -Value "$obDir\OpenBook.exe" -PropertyType String -Force | Out-Null
Track 'ob-run' "$runK\OpenBook"

$obUn = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OpenBook'
New-Item -Path $obUn -Force | Out-Null
New-ItemProperty -Path $obUn -Name 'DisplayName' -Value 'OpenBook' -Force | Out-Null
New-ItemProperty -Path $obUn -Name 'UninstallString' -Value "$obDir\Uninstall.exe" -Force | Out-Null
Track 'ob-uninst' $obUn

# OpenBook URL-protocol/class
$obCls = 'HKCU:\Software\Classes\OpenBook'
New-Item -Path $obCls -Force | Out-Null
New-ItemProperty -Path $obCls -Name '(default)' -Value 'URL:OpenBook Protocol' -Force | Out-Null
Track 'ob-class' $obCls

# --- plant ConvertMate fixtures ---
$cmDir = Join-Path $env:LOCALAPPDATA 'ConvertMate'
New-Item -ItemType Directory -Path $cmDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $cmDir 'Uninstaller.exe') -Value 'stub' -Force
Track 'cm-dir' $cmDir

# ConvertMate uninstall keyed only by Publisher=Amaryllis (obfuscated key name + DisplayName)
$cmUn = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{9A3C-OBF-1234}'
New-Item -Path $cmUn -Force | Out-Null
New-ItemProperty -Path $cmUn -Name 'DisplayName' -Value 'Free File Converter' -Force | Out-Null
New-ItemProperty -Path $cmUn -Name 'Publisher'   -Value 'Amaryllis' -Force | Out-Null
New-ItemProperty -Path $cmUn -Name 'InstallLocation' -Value $cmDir -Force | Out-Null
Track 'cm-uninst-pub' $cmUn

# dropper in Downloads
$dl = Join-Path $env:USERPROFILE 'Downloads'
if (Test-Path $dl) {
    $drop = Join-Path $dl 'ConvertMate-Setup.exe'
    Set-Content -LiteralPath $drop -Value 'stub' -Force
    Track 'cm-dropper' $drop
}

# --- plant PDFEditor fixtures ---
$peDir = Join-Path $env:LOCALAPPDATA 'Programs\PDFEditor'
New-Item -ItemType Directory -Path $peDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $peDir 'PDFEditor.exe') -Value 'stub' -Force
Track 'pe-dir' $peDir

New-ItemProperty -Path $runK -Name 'PDFEditor' -Value "$peDir\PDFEditor.exe" -PropertyType String -Force | Out-Null
Track 'pe-run' "$runK\PDFEditor"

# PDFEditor uninstall keyed only by Publisher=AppSuite (obfuscated key name + DisplayName)
$peUn = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{PE-OBF-7788}'
New-Item -Path $peUn -Force | Out-Null
New-ItemProperty -Path $peUn -Name 'DisplayName' -Value 'PDF Tools' -Force | Out-Null
New-ItemProperty -Path $peUn -Name 'Publisher'   -Value 'AppSuite' -Force | Out-Null
New-ItemProperty -Path $peUn -Name 'InstallLocation' -Value $peDir -Force | Out-Null
Track 'pe-uninst-pub' $peUn

Write-Host "Fixtures planted. Running DryRun..."
"`r`n" | & powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\nep\Downloads\hosted-removal.ps1" -DryRun -Harden -LogPath $log *> $null

$txt = if (Test-Path $log) { Get-Content -Raw $log } else { '' }

$checks = @(
    @{ id='OpenBook install dir';          rx=[regex]::Escape($obDir) },
    @{ id='OpenBook nw temp dir';          rx=[regex]::Escape($nwDir) },
    @{ id='OpenBook Run value';            rx='Run value.*OpenBook' },
    @{ id='OpenBook Uninstall key';        rx='Uninstall key OpenBook' },
    @{ id='OpenBook class/protocol';       rx='class OpenBook' },
    @{ id='ConvertMate install dir';       rx=[regex]::Escape($cmDir) },
    @{ id='ConvertMate Uninstall (Amaryllis pub)'; rx='Uninstall key \{9A3C-OBF-1234\}' },
    @{ id='ConvertMate dropper';           rx='dropper.*ConvertMate-Setup\.exe' },
    @{ id='PDFEditor install dir';         rx=[regex]::Escape($peDir) },
    @{ id='PDFEditor Run value';           rx='Run value.*PDFEditor' },
    @{ id='PDFEditor Uninstall (AppSuite pub)'; rx='Uninstall key \{PE-OBF-7788\}' }
)
$pass = 0; $fail = 0
Write-Host ""
Write-Host "== Detection results (DryRun 'would remove') =="
foreach ($c in $checks) {
    $ok = ($txt -match $c.rx)
    if ($ok) { Write-Host ("  [PASS] " + $c.id) -ForegroundColor Green; $pass++ }
    else     { Write-Host ("  [FAIL] " + $c.id) -ForegroundColor Red;   $fail++ }
}

# cleanup
foreach ($v in $fix.Values) {
    try {
        if ($v -match '^HK') { Remove-Item -Path $v -Recurse -Force -ErrorAction SilentlyContinue }
        elseif (Test-Path -LiteralPath $v) { Remove-Item -LiteralPath $v -Recurse -Force -ErrorAction SilentlyContinue }
    } catch {}
}
try { Remove-ItemProperty -Path $runK -Name 'OpenBook' -Force -ErrorAction SilentlyContinue } catch {}
try { Remove-ItemProperty -Path $runK -Name 'PDFEditor' -Force -ErrorAction SilentlyContinue } catch {}

Write-Host ""
Write-Host ("RESULT: {0}  (pass={1} fail={2})" -f (@('FAIL','PASS')[[int]($fail -eq 0)]), $pass, $fail)
