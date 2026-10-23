param(
    [string]$PostgresBin = 'C:\Program Files\PostgreSQL\18\bin',
    [int]$Port = 55439
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$cluster = Join-Path $projectRoot ('target\pg-test-' + [guid]::NewGuid().ToString('N'))
$oldUrl = $env:TEST_DATABASE_URL
$oldUser = $env:TEST_DATABASE_USER
$oldPassword = $env:TEST_DATABASE_PASSWORD
New-Item -ItemType Directory -Path $cluster -Force | Out-Null
$started = $false
Push-Location $projectRoot
try {
    & "$PostgresBin\initdb.exe" -D $cluster -U nsi_test -A trust --encoding=UTF8 --locale=C
    if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
    & "$PostgresBin\pg_ctl.exe" -D $cluster -l (Join-Path $cluster 'server.log') -o "-p $Port -h 127.0.0.1" -w start
    if ($LASTEXITCODE -ne 0) { throw 'Test PostgreSQL failed to start' }
    $started = $true
    $env:TEST_DATABASE_URL = "jdbc:postgresql://127.0.0.1:$Port/postgres"
    $env:TEST_DATABASE_USER = 'nsi_test'
    $env:TEST_DATABASE_PASSWORD = ''
    & "$projectRoot\mvnw.cmd" verify
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
} finally {
    if ($started) { & "$PostgresBin\pg_ctl.exe" -D $cluster -m fast -w stop }
    $env:TEST_DATABASE_URL = $oldUrl
    $env:TEST_DATABASE_USER = $oldUser
    $env:TEST_DATABASE_PASSWORD = $oldPassword
    Pop-Location
}
