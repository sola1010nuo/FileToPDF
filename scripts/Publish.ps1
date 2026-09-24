param([switch]$CoreOnly, [string]$CertificateThumbprint)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
dotnet publish src/FileToPDF/FileToPDF.csproj -c Release -r win-x64 --self-contained true -p:RuntimeFrameworkVersion=9.0.20 -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:PublishTrimmed=false -p:DebugType=None -o publish/win-x64
if ($LASTEXITCODE -ne 0) { throw 'Publish failed' }
if (!$CoreOnly) { & "$PSScriptRoot\Build-ShellIntegration.ps1" -CertificateThumbprint $CertificateThumbprint }
