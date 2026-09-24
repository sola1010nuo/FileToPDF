#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ExePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'publish\win-x64\FileToPDF.exe')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Resolve once, before changing the registry. Installation does not run the EXE.
$exe = Get-Item -LiteralPath $ExePath -ErrorAction Stop
if ($exe.PSIsContainer -or $exe.Extension -ine '.exe') {
    throw 'ExePath must point to an existing Windows .exe file. Publish FileToPDF first.'
}
$command = '"{0}" "%1"' -f $exe.FullName
$extensions = @('.doc', '.docx', '.ppt', '.pptx', '.jpg', '.jpeg', '.png')

foreach ($extension in $extensions) {
    # Extension-specific verbs remain available when the default application changes.
    $path = "Software\Classes\SystemFileAssociations\$extension\shell\FileToPDF.ConvertToPdf"
    if (!$PSCmdlet.ShouldProcess("HKCU\$path", 'Register Convert to PDF')) { continue }
    $verb = $null
    $commandKey = $null
    try {
        $verb = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($path)
        $verb.SetValue('', 'Convert to PDF', [Microsoft.Win32.RegistryValueKind]::String)
        $verb.SetValue('Icon', ('"{0}",0' -f $exe.FullName), [Microsoft.Win32.RegistryValueKind]::String)
        # Each right-click action passes one source file. Drag-and-drop still accepts a batch.
        $verb.SetValue('MultiSelectModel', 'Single', [Microsoft.Win32.RegistryValueKind]::String)
        $commandKey = $verb.CreateSubKey('command')
        $commandKey.SetValue('', $command, [Microsoft.Win32.RegistryValueKind]::String)
    }
    finally {
        if ($null -ne $commandKey) { $commandKey.Dispose() }
        if ($null -ne $verb) { $verb.Dispose() }
    }
}

if (!$WhatIfPreference) {
    # Refresh Shell associations without restarting Explorer or requiring elevation.
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
    Write-Output "Registered Convert to PDF for the current user: $($exe.FullName)"
    Write-Output 'Windows 11: right-click a supported source file, then choose Show more options.'
}
