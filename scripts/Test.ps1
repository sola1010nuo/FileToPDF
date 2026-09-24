param([switch]$Office)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
dotnet build tests/FileToPDF.Tests
if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
$testArgs = @()
if ($Office) { $testArgs = @('--word', '--powerpoint') }
dotnet run --project tests/FileToPDF.Tests --no-build -- @testArgs
if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
