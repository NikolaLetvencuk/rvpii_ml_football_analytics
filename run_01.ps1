# Pokrece scripts/01_data_processing_with_sparklyr.R sa garantovano ispravnim
# okruzenjem (JAVA_HOME + PATH), nezavisno od toga da li je terminal restartovan.

$ErrorActionPreference = "Stop"

# 1. Ucitaj sveze env varijable iz registra (zaobilazi zastarelu sesiju)
$env:JAVA_HOME = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
$env:PATH = "$env:JAVA_HOME\bin;" +
            [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')

if (-not (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
    throw "Java nije pronadjena na '$env:JAVA_HOME'. Instaliraj Temurin 17 i probaj ponovo."
}

$Rscript = "C:\Program Files\R\R-4.6.1\bin\x64\Rscript.exe"
if (-not (Test-Path $Rscript)) { throw "Rscript nije pronadjen na '$Rscript'." }

# 2. Radni direktorijum = koren projekta (skripta koristi relativne putanje)
Set-Location $PSScriptRoot

Write-Host "JAVA_HOME : $env:JAVA_HOME"
Write-Host "Projekat  : $PSScriptRoot"
Write-Host "Pokrecem 01_data_processing_with_sparklyr.R ...`n"

& $Rscript "scripts\01_data_processing_with_sparklyr.R"

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nSkripta je zavrsila sa greskom (exit $LASTEXITCODE)." -ForegroundColor Red
} else {
    Write-Host "`nGotovo." -ForegroundColor Green
}
