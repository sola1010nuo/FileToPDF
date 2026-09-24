#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root 'publish\win-x64\FileToPDF.exe'
if (!(Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Run scripts/Publish.ps1 first.' }

function Assert-True([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw "FAIL: $Message" }
}

# Preserve any pre-existing installation, including registry value kinds and subkeys.
function Read-Key([Microsoft.Win32.RegistryKey]$Key) {
    if ($null -eq $Key) { return $null }
    $node = @{ Values = @(); Children = @{} }
    foreach ($name in $Key.GetValueNames()) {
        $node.Values += @{ Name = $name; Data = $Key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames); Kind = $Key.GetValueKind($name) }
    }
    foreach ($name in $Key.GetSubKeyNames()) {
        $child = $Key.OpenSubKey($name)
        try { $node.Children[$name] = Read-Key $child } finally { $child.Dispose() }
    }
    return $node
}
function Write-Key([Microsoft.Win32.RegistryKey]$Key, $Node) {
    foreach ($value in $Node.Values) { $Key.SetValue($value.Name, $value.Data, $value.Kind) }
    foreach ($name in $Node.Children.Keys) {
        $child = $Key.CreateSubKey($name)
        try { Write-Key $child $Node.Children[$name] } finally { $child.Dispose() }
    }
}

$extensions = @('.doc', '.docx', '.ppt', '.pptx', '.jpg', '.jpeg', '.png')
$backups = @{}
foreach ($extension in $extensions) {
    $path = "Software\Classes\SystemFileAssociations\$extension\shell\FileToPDF.ConvertToPdf"
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path)
    try { $backups[$path] = Read-Key $key } finally { if ($null -ne $key) { $key.Dispose() } }
}

$tag = 'FileToPDF-context-' + [Guid]::NewGuid().ToString('N')
$work = Join-Path $root "artifacts\tests\$tag"
[void][IO.Directory]::CreateDirectory($work)
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
$outputs = @()
$sentinelPath = "Software\Classes\SystemFileAssociations\.png\shell\$tag"
$shell = $null
try {
    # Test executable path quoting as well as source path quoting.
    $testExe = Join-Path $work 'File To PDF.exe'
    Copy-Item -LiteralPath $exe -Destination $testExe
    & "$PSScriptRoot\Install-ContextMenu.ps1" -ExePath $testExe
    & "$PSScriptRoot\Install-ContextMenu.ps1" -ExePath $testExe
    $expected = '"{0}" "%1"' -f $testExe
    foreach ($path in $backups.Keys) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path)
        try {
            Assert-True ($key.GetValue('') -ceq 'Convert to PDF') 'menu label'
            Assert-True ($key.GetValue('MultiSelectModel') -ceq 'Single') 'single-source verb'
            $commandKey = $key.OpenSubKey('command')
            try { Assert-True ($commandKey.GetValue('') -ceq $expected) 'quoted EXE and source placeholder' }
            finally { $commandKey.Dispose() }
        }
        finally { $key.Dispose() }
    }
    $rejected = $false
    try { & "$PSScriptRoot\Install-ContextMenu.ps1" -ExePath (Join-Path $work 'missing.exe') }
    catch { $rejected = $true }
    Assert-True $rejected 'missing executable rejected'
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Classes\SystemFileAssociations\.png\shell\FileToPDF.ConvertToPdf\command')
    try { Assert-True ($key.GetValue('') -ceq $expected) 'invalid installation leaves existing command intact' }
    finally { $key.Dispose() }

    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.NameSpace($work)
    $fixtures = @('report.doc', 'report.docx', 'slides.ppt', 'slides.pptx', 'photo.jpg', 'photo.jpg', ([string][char]0x900F + [char]0x660E + ' image.png'))
    for ($i = 0; $i -lt $extensions.Count; $i++) {
        $extension = $extensions[$i]
        # Unicode, spaces, parentheses and shell metacharacters must remain one literal argument.
        $name = $tag + ' ' + [char]0x6E2C + [char]0x8A66 + ' & (source)' + $extension
        $source = Join-Path $work $name
        Copy-Item -LiteralPath (Join-Path $root "artifacts\tests\$($fixtures[$i])") -Destination $source
        # All seven files have the same stem, so resolve every subsequent numeric suffix.
        $index = 0
        $stem = [IO.Path]::GetFileNameWithoutExtension($name)
        do {
            $suffix = if ($index -eq 0) { '' } else { "_$index" }
            $output = Join-Path $desktop "$stem$suffix.pdf"
            $index++
        } while ($outputs -contains $output)
        $outputs += $output
        $item = $folder.ParseName($name)
        $verbs = $item.Verbs()
        $menu = $null
        for ($v = 0; $v -lt $verbs.Count; $v++) {
            $verb = $verbs.Item($v)
            if ($verb.Name.Replace('&', '').Trim() -ceq 'Convert to PDF') { $menu = $verb; break }
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($verb)
        }
        Assert-True ($null -ne $menu) "Explorer exposes menu for $extension"
        try { $menu.DoIt() }
        finally {
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($menu)
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($verbs)
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($item)
        }
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while (!(Test-Path -LiteralPath $output) -and $timer.Elapsed.TotalSeconds -lt 200) { Start-Sleep -Milliseconds 250 }
        Assert-True (Test-Path -LiteralPath $output) "Shell verb generated Desktop PDF for $extension"
        $stream = [IO.File]::OpenRead($output)
        try {
            $header = New-Object byte[] 5
            [void]$stream.Read($header, 0, 5)
            Assert-True ([Text.Encoding]::ASCII.GetString($header) -ceq '%PDF-') 'PDF header'
        }
        finally { $stream.Dispose() }
        Write-Output "PASS: actual Shell context-menu invocation $extension -> Desktop PDF"
    }
    # Uninstall must not delete adjacent verbs or depend on the EXE still existing.
    $sentinel = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($sentinelPath)
    $sentinel.SetValue('', 'Unrelated test verb')
    $sentinel.Dispose()
    & "$PSScriptRoot\Uninstall-ContextMenu.ps1"
    & "$PSScriptRoot\Uninstall-ContextMenu.ps1"
    foreach ($path in $backups.Keys) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path)
        try { Assert-True ($null -eq $key) 'uninstalled all seven verbs' }
        finally { if ($null -ne $key) { $key.Dispose() } }
    }
    $sentinel = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($sentinelPath)
    try { Assert-True ($sentinel.GetValue('') -ceq 'Unrelated test verb') 'unrelated verb preserved' }
    finally { $sentinel.Dispose() }
    Write-Output 'PASS: idempotent install/uninstall, missing EXE rejection, quoting, unrelated registry preservation'
}
finally {
    foreach ($path in $backups.Keys) {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($path, $false)
        if ($null -ne $backups[$path]) {
            $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($path)
            try { Write-Key $key $backups[$path] } finally { $key.Dispose() }
        }
    }
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($sentinelPath, $false)
    if ($null -ne $shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    foreach ($output in $outputs) { if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output } }
    if ($null -ne ('FileToPDF.ContextMenuNotification' -as [type])) {
        [FileToPDF.ContextMenuNotification]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    }
}
