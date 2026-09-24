#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\ContextMenu.Common.ps1"
if (!$PSCmdlet.ShouldProcess('FileToPDF context menu for current user', 'Remove package, owned registration and integration payloads')) { return }
$settings = Get-MenuSettings
foreach ($package in @(Get-OwnedMenuPackages)) { Remove-AppxPackage -Package $package.PackageFullName }
Remove-MenuVerbs
foreach ($thumbprint in @($settings['TrustedThumbprints'])) {
    if ($thumbprint -match '^[A-Fa-f0-9]{40}$') {
        $path = "Cert:\LocalMachine\TrustedPeople\$thumbprint"
        if (Test-Path -LiteralPath $path) {
            if (!(Set-MenuDevelopmentTrust 'Remove' $thumbprint)) { Write-Output 'Kept a shared or pre-existing signing certificate.' }
        }
    }
}
[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($script:SettingsPath, $false)
Send-MenuChanged
try { Remove-MenuPayloads }
catch { throw "Registration was removed, but Windows still holds a payload file. Sign out/in and rerun uninstall to finish cleanup. Details: $_" }
Write-Output 'Removed FileToPDF integration. The converter EXE, PDFs and other applications were not changed.'
