#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ExePath,
    [string]$IntegrationPath,
    [ValidateSet('Auto', 'Modern', 'Legacy')][string]$Mode = 'Auto'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Defaults must be resolved after parameter binding, not in the param declaration.
$root = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($ExePath)) { $ExePath = Join-Path $root 'publish\win-x64\FileToPDF.exe' }
if ([string]::IsNullOrWhiteSpace($IntegrationPath)) { $IntegrationPath = Join-Path $root 'publish\shell-integration' }
. "$PSScriptRoot\ContextMenu.Common.ps1"
if (![Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'Use Windows x64 PowerShell for this x64 integration.' }
$exe = Get-Item -LiteralPath $ExePath
if ($exe.PSIsContainer -or $exe.Extension -ine '.exe') { throw 'ExePath must be an existing .exe. Publish FileToPDF first.' }
$modeName = Get-MenuMode $Mode
$files = @('FileToPDF.ShellExtension.dll', 'FileToPDF.ShellHost.exe')
if ($modeName -eq 'Modern') { $files += 'FileToPDF.ContextMenu.msix' }
foreach ($file in $files) {
    if (!(Test-Path -LiteralPath (Join-Path $IntegrationPath $file) -PathType Leaf)) { throw "Missing $file. Run scripts/Build-ShellIntegration.ps1 first." }
}
if (!$PSCmdlet.ShouldProcess("$modeName context menu for current user", "Install using $($exe.FullName)")) { return }
$previous = Get-MenuSettings
$oldPackages = @(Get-OwnedMenuPackages)
$importedThumbprint = $null
$managedThumbprint = $null
$removedPackage = $false
try {
    if ($modeName -eq 'Modern') {
        $package = Join-Path $IntegrationPath 'FileToPDF.ContextMenu.msix'
        $signing = Get-Content (Join-Path $IntegrationPath 'Signing.json') -Raw | ConvertFrom-Json
        $signature = Get-AuthenticodeSignature -LiteralPath $package
        if (!$signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $signing.Thumbprint -or
            $signature.SignerCertificate.Subject -ne $signing.Publisher -or $signature.Status -in @('HashMismatch', 'NotSigned')) {
            throw 'The identity package signature does not match the supplied publisher.'
        }
        # MSIX validates machine trust. Only the certificate helper elevates; package registration stays per-user.
        # Production bundles can be built with -CertificateThumbprint and do not import trust.
        if ($signing.Development -and !(Test-Path "Cert:\LocalMachine\TrustedPeople\$($signing.Thumbprint)")) {
            $public = New-Object Security.Cryptography.X509Certificates.X509Certificate2((Join-Path $IntegrationPath 'Publisher.cer'))
            if ($public.Thumbprint -ne $signing.Thumbprint -or $public.Subject -ne 'CN=FileToPDF' -or $public.Subject -ne $public.Issuer) { throw 'Invalid local development certificate.' }
            if (Set-MenuDevelopmentTrust 'Add' $public.Thumbprint (Join-Path $IntegrationPath 'Publisher.cer')) { $importedThumbprint = $public.Thumbprint }
            Write-Output 'Trusted the FileToPDF local development certificate in LocalMachine\TrustedPeople.'
        }
        if ($signing.Development -and (Test-Path "HKLM:\SOFTWARE\FileToPDF\DevelopmentTrust\$($signing.Thumbprint)")) {
            # Also track trust installed by this tool for another user, without owning pre-existing external trust.
            $managedThumbprint = $signing.Thumbprint
        }
        foreach ($p in $oldPackages) {
            if ($p.Publisher -ne $signing.Publisher) { throw 'An identity package with a different publisher is already installed. Uninstall it explicitly first.' }
        }
    }
    # Immutable versioned payloads avoid overwriting a DLL currently loaded by Explorer.
    $hashes = ($files | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $IntegrationPath $_) -Algorithm SHA256).Hash }) -join ''
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $version = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($hashes)))).Replace('-', '').Substring(0,32) }
    finally { $sha.Dispose() }
    $payload = Join-Path $script:PayloadRoot $version
    [void][IO.Directory]::CreateDirectory($payload)
    foreach ($file in $files) {
        $target = Join-Path $payload $file
        if (!(Test-Path -LiteralPath $target)) { Copy-Item -LiteralPath (Join-Path $IntegrationPath $file) -Destination $target }
    }
    if ($modeName -eq 'Modern') {
        foreach ($p in $oldPackages) { Remove-AppxPackage -Package $p.PackageFullName; $removedPackage = $true }
        Add-AppxPackage -Path (Join-Path $payload 'FileToPDF.ContextMenu.msix') -ExternalLocation $payload
    } else {
        foreach ($p in $oldPackages) { Remove-AppxPackage -Package $p.PackageFullName; $removedPackage = $true }
    }
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:SettingsPath)
    try {
        $key.SetValue('ExePath', $exe.FullName)
        $key.SetValue('Mode', $modeName)
        $key.SetValue('PayloadDirectory', $payload)
        if ($modeName -eq 'Modern') { $key.SetValue('Publisher', $signing.Publisher) }
        $thumbprints = @($previous['TrustedThumbprints'] | Where-Object { $_ })
        if ($managedThumbprint) { $thumbprints += $managedThumbprint }
        $key.SetValue('TrustedThumbprints', [string[]]@($thumbprints | Select-Object -Unique), [Microsoft.Win32.RegistryValueKind]::MultiString)
    } finally { $key.Dispose() }
    Remove-MenuVerbs
    if ($modeName -eq 'Legacy') { Register-LegacyMenu (Join-Path $payload 'FileToPDF.ShellExtension.dll') }
    Send-MenuChanged
    Write-Output "Installed $modeName Convert to PDF for current user: $($exe.FullName)"
    Write-Output 'If Explorer cached an older menu, close its windows and sign out/in once. No global menu settings were changed.'
} catch {
    if ($removedPackage -and $previous['Mode'] -eq 'Modern' -and $previous['PayloadDirectory']) {
        $oldPayload = $previous['PayloadDirectory']
        try { Add-AppxPackage -Path (Join-Path $oldPayload 'FileToPDF.ContextMenu.msix') -ExternalLocation $oldPayload }
        catch { Write-Warning "Could not restore the previous package: $_" }
    }
    if ($importedThumbprint) {
        try { [void](Set-MenuDevelopmentTrust 'Remove' $importedThumbprint) }
        catch { Write-Warning "Remove the FileToPDF development trust using Set-DevelopmentTrust.ps1: $_" }
    }
    throw
}
