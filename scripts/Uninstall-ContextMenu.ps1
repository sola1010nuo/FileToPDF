#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($extension in @('.doc', '.docx', '.ppt', '.pptx', '.jpg', '.jpeg', '.png')) {
    # Delete only our named verb. Leave extension associations and other applications intact.
    $path = "Software\Classes\SystemFileAssociations\$extension\shell\FileToPDF.ConvertToPdf"
    if ($PSCmdlet.ShouldProcess("HKCU\$path", 'Remove Convert to PDF')) {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($path, $false)
    }
}

if (!$WhatIfPreference) {
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
    Write-Output 'Removed Convert to PDF for the current user. FileToPDF.exe and existing PDFs were not removed.'
}
