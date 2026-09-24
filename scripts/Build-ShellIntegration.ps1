#requires -Version 5.1
[CmdletBinding()]
param([string]$CertificateThumbprint)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (!(Test-Path -LiteralPath $vswhere)) { throw 'Install Visual Studio 2022 C++ desktop tools and Windows 11 SDK.' }
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Visual Studio C++ x64 tools were not found.' }
$msbuild = Join-Path $vs 'MSBuild\Current\Bin\MSBuild.exe'
$kits = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots').KitsRoot10
$sdk = Get-ChildItem (Join-Path $kits 'bin') -Directory | Where-Object {
    $_.Name -match '^10\.0\.\d+\.0$' -and (Test-Path (Join-Path $_.FullName 'x64\makeappx.exe'))
} | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (!$sdk) { throw 'Windows SDK MakeAppx/SignTool not found.' }
$makeappx = Join-Path $sdk.FullName 'x64\makeappx.exe'
$signtool = Join-Path $sdk.FullName 'x64\signtool.exe'
$work = Join-Path $root 'artifacts\shell-package'
$out = Join-Path $root 'publish\shell-integration'
[void][IO.Directory]::CreateDirectory($work)
[void][IO.Directory]::CreateDirectory($out)
$development = [string]::IsNullOrWhiteSpace($CertificateThumbprint)
if ($development) {
    $thumbFile = Join-Path $work 'development-thumbprint.txt'
    if (Test-Path -LiteralPath $thumbFile) { $CertificateThumbprint = (Get-Content $thumbFile -Raw).Trim() }
    $certificate = if ($CertificateThumbprint) { Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction SilentlyContinue }
    if (!$certificate -or !$certificate.HasPrivateKey -or $certificate.NotAfter -lt (Get-Date).AddDays(7)) {
        $certificate = New-SelfSignedCertificate -Type Custom -Subject 'CN=FileToPDF' -FriendlyName 'FileToPDF local development signing' `
            -CertStoreLocation Cert:\CurrentUser\My -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
            -KeyUsage DigitalSignature -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddYears(1) `
            -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
        Set-Content -LiteralPath $thumbFile -Value $certificate.Thumbprint -Encoding ASCII
    }
} else { $certificate = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint" }
if (!$certificate.HasPrivateKey) { throw 'The signing certificate must have a private key in CurrentUser\My.' }
$publisher = [Security.SecurityElement]::Escape($certificate.Subject)
$hostManifest = Join-Path $work 'ShellHost.manifest'
(Get-Content (Join-Path $root 'src\FileToPDF.ShellExtension\ShellHost.manifest') -Raw).Replace('CN=FileToPDF', $publisher) |
    Set-Content -LiteralPath $hostManifest -Encoding UTF8
foreach ($name in @('FileToPDF.ShellExtension', 'FileToPDF.ShellHost')) {
    & $msbuild (Join-Path $root "src\FileToPDF.ShellExtension\$name.vcxproj") /nologo /verbosity:minimal /p:Configuration=Release /p:Platform=x64 "/p:ShellAppManifest=$hostManifest"
    if ($LASTEXITCODE -ne 0) { throw "Native build failed: $name" }
}
$packageDir = Join-Path $work 'package'
[void][IO.Directory]::CreateDirectory((Join-Path $packageDir 'Assets'))
(Get-Content (Join-Path $root 'packaging\ContextMenu\AppxManifest.xml') -Raw).Replace('CN=FileToPDF', $publisher) |
    Set-Content -LiteralPath (Join-Path $packageDir 'AppxManifest.xml') -Encoding UTF8
# Required package assets; the context-menu icon itself is optional FileToPDF.ico beside the converter.
Add-Type -AssemblyName System.Drawing
foreach ($asset in @(@('StoreLogo.png',50), @('Square44x44Logo.png',44), @('Square150x150Logo.png',150))) {
    $image = New-Object Drawing.Bitmap([int]$asset[1], [int]$asset[1])
    $graphics = [Drawing.Graphics]::FromImage($image)
    try {
        $graphics.Clear([Drawing.Color]::FromArgb(35,80,130))
        $graphics.FillRectangle([Drawing.Brushes]::White, [int]($asset[1]/3), [int]($asset[1]/5), [int]($asset[1]/3), [int]($asset[1]*3/5))
        $image.Save((Join-Path $packageDir "Assets\$($asset[0])"), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $image.Dispose() }
}
$package = Join-Path $out 'FileToPDF.ContextMenu.msix'
# /nv is required for a sparse package: native binaries live in the external location.
& $makeappx pack /o /nv /d $packageDir /p $package
if ($LASTEXITCODE -ne 0) { throw 'Sparse package creation failed.' }
& $signtool sign /fd SHA256 /sha1 $certificate.Thumbprint /s My $package
if ($LASTEXITCODE -ne 0) { throw 'Sparse package signing failed.' }
Export-Certificate -Cert $certificate -FilePath (Join-Path $out 'Publisher.cer') | Out-Null
@{ Publisher = $certificate.Subject; Thumbprint = $certificate.Thumbprint; Development = $development } |
    ConvertTo-Json | Set-Content (Join-Path $out 'Signing.json') -Encoding UTF8
foreach ($file in @('FileToPDF.ShellExtension.dll', 'FileToPDF.ShellHost.exe')) {
    Copy-Item -LiteralPath (Join-Path $root "artifacts\native\Release\$file") -Destination $out -Force
}
Write-Output "Built signed sparse package and native components: $out"
