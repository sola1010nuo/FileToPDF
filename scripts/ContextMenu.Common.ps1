# Shared implementation details for the per-user installers (Windows PowerShell 5.1).
$script:MenuClsid = '{5D62FC80-DF75-4807-AE2B-7E4A2597DB5C}'
$script:PackageName = 'FileToPDF.ContextMenu'
$script:SettingsPath = 'Software\FileToPDF\ShellIntegration'
$script:MenuExtensions = @('.doc', '.docx', '.ppt', '.pptx', '.jpg', '.jpeg', '.png')
$script:PayloadRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'FileToPDF\ShellIntegration'

function Get-MenuMode([string]$Mode) {
    if ($Mode -ne 'Auto') { return $Mode }
    $build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
    if ($build -ge 22000) { return 'Modern' }
    return 'Legacy'
}
function Get-MenuSettings {
    $settings = @{}
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:SettingsPath)
    if ($null -ne $key) {
        try { foreach ($name in $key.GetValueNames()) { $settings[$name] = $key.GetValue($name) } }
        finally { $key.Dispose() }
    }
    return $settings
}
function Remove-MenuVerbs {
    foreach ($extension in $script:MenuExtensions) {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree("Software\Classes\SystemFileAssociations\$extension\shell\FileToPDF.ConvertToPdf", $false)
    }
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree("Software\Classes\CLSID\$script:MenuClsid", $false)
}
function Register-LegacyMenu([string]$DllPath) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("Software\Classes\CLSID\$script:MenuClsid\InprocServer32")
    try { $key.SetValue('', $DllPath); $key.SetValue('ThreadingModel', 'Apartment') } finally { $key.Dispose() }
    foreach ($extension in $script:MenuExtensions) {
        $path = "Software\Classes\SystemFileAssociations\$extension\shell\FileToPDF.ConvertToPdf"
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($path)
        try {
            $key.SetValue('', 'Convert to PDF')
            $key.SetValue('ExplorerCommandHandler', $script:MenuClsid)
            $key.SetValue('MultiSelectModel', 'Player')
        } finally { $key.Dispose() }
    }
}
function Send-MenuChanged {
    if ($null -eq ('FileToPDF.ContextMenuNotification' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace FileToPDF {
    public static class ContextMenuNotification {
        [DllImport("shell32.dll")]
        public static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);
    }
}
'@
    }
    [FileToPDF.ContextMenuNotification]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
}
function Get-OwnedMenuPackages {
    # Name is exact, per-user only. Never enumerate/remove other users' packages.
    $settings = Get-MenuSettings
    $publisher = if ($settings['Publisher']) { $settings['Publisher'] } else { 'CN=FileToPDF' }
    @(Get-AppxPackage -Name $script:PackageName | Where-Object { $_.Name -ceq $script:PackageName -and $_.Publisher -ceq $publisher })
}
function Set-MenuDevelopmentTrust([string]$Action, [string]$Thumbprint, [string]$CertificatePath = '') {
    $helper = Join-Path $PSScriptRoot 'Set-DevelopmentTrust.ps1'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -Thumbprint {2}' -f $helper, $Action, $Thumbprint
    if ($CertificatePath) { $arguments += ' -CertificatePath "{0}"' -f [IO.Path]::GetFullPath($CertificatePath) }
    $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
    $process.WaitForExit()
    if ($process.ExitCode -notin @(0,10)) { throw 'The FileToPDF development-certificate trust step failed or was canceled.' }
    return ($process.ExitCode -eq 0)
}
function Remove-MenuPayloads {
    if (!(Test-Path -LiteralPath $script:PayloadRoot)) { return }
    $rootItem = Get-Item -LiteralPath $script:PayloadRoot
    if ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing to remove a redirected integration directory.' }
    $prefix = [IO.Path]::GetFullPath($script:PayloadRoot).TrimEnd('\') + '\'
    foreach ($directory in Get-ChildItem -LiteralPath $script:PayloadRoot -Directory) {
        if ($directory.Name -notmatch '^[0-9A-F]{32}$' -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        if (![IO.Path]::GetFullPath($directory.FullName).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid integration cleanup path.' }
        # No recursive deletion, and no paths taken from registry configuration.
        foreach ($name in @('FileToPDF.ShellExtension.dll', 'FileToPDF.ShellHost.exe', 'FileToPDF.ContextMenu.msix')) {
            $file = Join-Path $directory.FullName $name
            if (Test-Path -LiteralPath $file -PathType Leaf) { Remove-Item -LiteralPath $file }
        }
        if (@(Get-ChildItem -LiteralPath $directory.FullName -Force).Count -eq 0) { Remove-Item -LiteralPath $directory.FullName }
    }
    if (@(Get-ChildItem -LiteralPath $script:PayloadRoot -Force).Count -eq 0) { Remove-Item -LiteralPath $script:PayloadRoot }
}
