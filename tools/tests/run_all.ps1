# Runs every tools/tests/*_spec.lua with luajit, then syntax-checks every AutoInvitePlus\**\*.lua
# with `luajit -bl`. Prints per-spec pass/fail counts and a summary; exits non-zero on any failure.
# Usage (from anywhere):  powershell -File tools\tests\run_all.ps1
$ErrorActionPreference = 'Continue'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repo

$lj = Get-Command luajit -ErrorAction SilentlyContinue
if (-not $lj) { Write-Host 'luajit not found on PATH' -ForegroundColor Red; exit 2 }

$failed = 0
$totalPass = 0; $totalFail = 0

Write-Host '== Specs =='
foreach ($spec in (Get-ChildItem (Join-Path $PSScriptRoot '*_spec.lua') | Sort-Object Name)) {
    $out = & luajit $spec.FullName 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $summary = $out | Where-Object { $_ -match '(\d+) passed, (\d+) failed' } | Select-Object -Last 1
    $p = 0; $f = 0
    if ($summary -match '(\d+) passed, (\d+) failed') { $p = [int]$Matches[1]; $f = [int]$Matches[2] }
    $totalPass += $p; $totalFail += $f
    if ($code -ne 0 -or $f -gt 0) {
        $failed++
        Write-Host ("FAIL  {0,-28} {1} passed, {2} failed (exit {3})" -f $spec.Name, $p, $f, $code) -ForegroundColor Red
        $out | Select-Object -First 40 | ForEach-Object { Write-Host "      $_" }
    } else {
        if ($summary) { $cnt = "$p passed" } else { $cnt = 'passed (exit 0, no count line)' }
        Write-Host ("ok    {0,-28} {1}" -f $spec.Name, $cnt) -ForegroundColor Green
    }
}

Write-Host ''
Write-Host '== Syntax (luajit -bl) =='
$files = Get-ChildItem (Join-Path $repo 'AutoInvitePlus') -Recurse -Filter *.lua
$bad = 0
foreach ($file in $files) {
    $o = & luajit -bl $file.FullName 2>&1 | Where-Object { $_ -match '^luajit' -or $_ -match 'unexpected|expected near|<eof>' }
    if ($LASTEXITCODE -ne 0) {
        $bad++
        Write-Host ("SYNTAX {0}" -f $file.FullName.Substring($repo.Length + 1)) -ForegroundColor Red
        $o | Select-Object -First 3 | ForEach-Object { Write-Host "      $_" }
    }
}
Write-Host ("{0} files checked, {1} with syntax errors" -f $files.Count, $bad)

Write-Host ''
Write-Host '== Summary =='
Write-Host ("specs failed: {0}   assertions: {1} passed, {2} failed   syntax errors: {3}" -f $failed, $totalPass, $totalFail, $bad)
if ($failed -gt 0 -or $bad -gt 0) { exit 1 }
exit 0
