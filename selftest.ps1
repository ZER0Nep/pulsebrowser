$base = 'C:\Users\nep\Downloads'
$log  = Join-Path $env:TEMP 'PUAKILLER.log'
$fail = 0
Write-Host "== PUAKILLER self-test ==" -ForegroundColor Cyan
foreach ($f in @('PUAKILLER-LOCAL.ps1','hosted-removal.ps1')) {
    $p = Join-Path $base $f
    if (-not (Test-Path $p)) { Write-Host "MISSING $f" -ForegroundColor Red; $fail++; continue }
    $e = $null; $t = $null
    [System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e) | Out-Null
    $cmts = (Get-Content $p | Select-String '^\s*#').Count
    if ($e.Count) { Write-Host "PARSE FAIL $f -> $($e[0].Message)" -ForegroundColor Red; $fail++ }
    else { Write-Host "PARSE OK   $f  tokens=$($t.Count) comments=$cmts" -ForegroundColor Green }
}
Remove-Item $log -Force -ErrorAction SilentlyContinue
& (Join-Path $base 'PUAKILLER-LOCAL.ps1') -DryRun -Harden *> $null
if (Test-Path $log) {
    $txt = Get-Content $log -Raw
    $err = [regex]::Match($txt,'Errors:\s*(\d+)').Groups[1].Value
    $verify = [bool]($txt -match 'Verification')
    $harden = [bool]($txt -match 'would plant block')
    $color  = if ($err -eq '0' -and $verify -and $harden) { 'Green' } else { 'Yellow' }
    Write-Host "DRYRUN  log=$log  Errors=$err  verify=$verify  harden=$harden" -ForegroundColor $color
    if (-not ($verify -and $harden -and $err -eq '0')) { $fail++ }
} else { Write-Host "DRYRUN produced NO log!" -ForegroundColor Red; $fail++ }
Write-Host ("RESULT: " + $(if ($fail) { "FAIL ($fail)" } else { "PASS" })) -ForegroundColor $(if ($fail) { 'Red' } else { 'Cyan' })
