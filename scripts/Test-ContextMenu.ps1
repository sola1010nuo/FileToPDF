#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot\ContextMenu.Common.ps1"
function Assert-True([bool]$Condition, [string]$Message) { if (!$Condition) { throw "FAIL: $Message" } }
$previous = Get-MenuSettings
$exe = Join-Path $root 'publish\win-x64\FileToPDF.exe'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
& (Join-Path $vs 'MSBuild\Current\Bin\MSBuild.exe') (Join-Path $root 'tests\FileToPDF.ShellExtension.Tests\FileToPDF.ShellExtension.Tests.vcxproj') /nologo /verbosity:minimal /p:Configuration=Release /p:Platform=x64
if ($LASTEXITCODE -ne 0) { throw 'Native tests build failed.' }
$runner = Join-Path $root 'artifacts\native\Release\FileToPDF.ShellExtension.Tests.exe'
$dll = Join-Path $root 'publish\shell-integration\FileToPDF.ShellExtension.dll'
& $runner --unit $dll
if ($LASTEXITCODE -ne 0) { throw 'Native unit tests failed.' }
$tag = 'FileToPDF-modern-' + [Guid]::NewGuid().ToString('N')
$work = Join-Path $root "artifacts\tests\$tag"
[void][IO.Directory]::CreateDirectory($work)
$exeDirectory = Join-Path $work 'EXE with spaces'
[void][IO.Directory]::CreateDirectory($exeDirectory)
$testExe = Join-Path $exeDirectory 'FileToPDF.exe'
$probe = Join-Path $exeDirectory 'ArgumentProbe.exe'
Copy-Item -LiteralPath $exe -Destination $testExe
Copy-Item -LiteralPath $runner -Destination $probe
$extensions = @('.doc', '.docx', '.ppt', '.pptx', '.jpg', '.jpeg', '.png')
$fixtures = @('report.doc', 'report.docx', 'slides.ppt', 'slides.pptx', 'photo.jpg', 'photo.jpg', ([string][char]0x900F + [char]0x660E + ' image.png'))
$selectedPaths = @()
$outputs = @()
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
for ($i=0; $i -lt $extensions.Count; $i++) {
    $name = $tag + "-$i " + [char]0x6E2C + [char]0x8A66 + ' & (source) %1' + $extensions[$i]
    $source = Join-Path $work $name
    Copy-Item -LiteralPath (Join-Path $root "artifacts\tests\$($fixtures[$i])") -Destination $source
    $selectedPaths += $source
    $outputs += Join-Path $desktop ([IO.Path]::GetFileNameWithoutExtension($name) + '.pdf')
}
function Invoke-Native([string]$Action, [string]$Registration, [string[]]$Paths) {
    $result = & $runner $Action $Registration @Paths
    if ($LASTEXITCODE -ne 0) { throw "Native $Action failed: $result" }
    return $result
}
function Set-TestTarget([string]$Path) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:SettingsPath, $true)
    try { $key.SetValue('ExePath', $Path) } finally { $key.Dispose() }
}
function Wait-File([string]$Path) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (!(Test-Path -LiteralPath $Path) -and $timer.Elapsed.TotalSeconds -lt 210) { Start-Sleep -Milliseconds 250 }
    Assert-True (Test-Path -LiteralPath $Path) "output exists: $Path"
}
$sentinelPath = "Software\Classes\SystemFileAssociations\.png\shell\$tag"
try {
    # Regression for $PSScriptRoot: no parameters, including when launched from another cwd.
    Push-Location $env:TEMP
    try { & "$PSScriptRoot\Install-ContextMenu.ps1" } finally { Pop-Location }
    Assert-True ((Get-MenuSettings)['ExePath'] -ceq $exe) 'default executable path'
    & "$PSScriptRoot\Install-ContextMenu.ps1" -ExePath $testExe
    Assert-True ((Get-MenuSettings)['ExePath'] -ceq $testExe) 'custom executable path'
    Assert-True (@(Get-OwnedMenuPackages).Count -eq 1) 'one registered sparse identity package'
    $reject = $false
    try { & "$PSScriptRoot\Install-ContextMenu.ps1" -ExePath (Join-Path $work 'missing.exe') } catch { $reject = $true }
    Assert-True $reject 'missing EXE rejected before installation'
    Assert-True ((Get-MenuSettings)['ExePath'] -ceq $testExe) 'failed install preserves configuration'
    Invoke-Native '--unit' 'registered' @()
    foreach ($selectedPath in $selectedPaths) { Assert-True ((Invoke-Native '--state' 'registered' @($selectedPath)) -contains 'ENABLED') "supported: $selectedPath" }
    foreach ($name in @('unsupported.pdf','unsupported.exe','unsupported.txt')) {
        $unsupported = Join-Path $work $name
        [IO.File]::WriteAllText($unsupported, 'test')
        Assert-True ((Invoke-Native '--state' 'registered' @($unsupported)) -contains 'HIDDEN') "hidden: $name"
        Assert-True ((Invoke-Native '--state' 'registered' @($selectedPaths[0],$unsupported)) -contains 'HIDDEN') 'mixed unsupported selection hidden'
    }
    $directory = Join-Path $work 'folder.png'
    [void][IO.Directory]::CreateDirectory($directory)
    Assert-True ((Invoke-Native '--state' 'registered' @($directory)) -contains 'HIDDEN') 'folder with supported suffix hidden'
    Set-TestTarget $probe
    Invoke-Native '--invoke' 'registered' $selectedPaths
    $capture = Join-Path $exeDirectory 'arguments.bin'
    Wait-File $capture
    Start-Sleep -Milliseconds 500
    $reader = New-Object IO.BinaryReader([IO.File]::OpenRead($capture), [Text.Encoding]::Unicode)
    try {
        Assert-True ($reader.ReadInt32() -eq $selectedPaths.Count + 1) 'all selected files passed in one argv'
        foreach ($selectedPath in $selectedPaths) { $length = $reader.ReadInt32(); Assert-True ((-join $reader.ReadChars($length)) -ceq $selectedPath) 'exact Unicode/special-character argv' }
    } finally { $reader.Dispose() }
    Assert-True (@(Get-Content (Join-Path $exeDirectory 'invocations.txt')).Count -eq 1) 'exactly one process for multi-select'
    Set-TestTarget $testExe
    Invoke-Native '--invoke' 'registered' $selectedPaths
    foreach ($output in $outputs) {
        Wait-File $output
        $stream = [IO.File]::OpenRead($output)
        try { $header = New-Object byte[] 5; [void]$stream.Read($header,0,5); Assert-True ([Text.Encoding]::ASCII.GetString($header) -ceq '%PDF-') 'native selection produced PDF' }
        finally { $stream.Dispose() }
    }
    Write-Output 'PASS: packaged COM activation; seven formats; unsupported selections hidden; exact multi-select argv; real Desktop PDFs'
    # Exercise the Win10 registration on this OS without pretending this tests Win10 Explorer UI.
    & "$PSScriptRoot\Install-ContextMenu.ps1" -ExePath $testExe -Mode Legacy
    Assert-True (@(Get-OwnedMenuPackages).Count -eq 0) 'legacy installation has no Appx registration'
    Invoke-Native '--unit' 'registered-legacy' @()
    foreach ($extension in $extensions) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Classes\SystemFileAssociations\$extension\shell\FileToPDF.ConvertToPdf")
        try { Assert-True ($key.GetValue('ExplorerCommandHandler') -eq $script:MenuClsid) 'legacy COM handler'; Assert-True ($key.GetValue('MultiSelectModel') -eq 'Player') 'legacy multi-select model' }
        finally { $key.Dispose() }
    }
    $sentinel = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($sentinelPath)
    try { $sentinel.SetValue('', 'unrelated') } finally { $sentinel.Dispose() }
    & "$PSScriptRoot\Uninstall-ContextMenu.ps1"
    & "$PSScriptRoot\Uninstall-ContextMenu.ps1"
    Assert-True (@(Get-OwnedMenuPackages).Count -eq 0) 'package removed'
    Assert-True ((Get-MenuSettings).Count -eq 0) 'configuration removed'
    Assert-True (!(Test-Path -LiteralPath $script:PayloadRoot)) 'all owned installed payloads removed'
    foreach ($extension in $extensions) {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Classes\SystemFileAssociations\$extension\shell\FileToPDF.ConvertToPdf")
        try { Assert-True ($null -eq $key) 'owned verb removed' } finally { if ($key) { $key.Dispose() } }
    }
    $sentinel = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($sentinelPath)
    try { Assert-True ($sentinel.GetValue('') -ceq 'unrelated') 'other menu unchanged' } finally { $sentinel.Dispose() }
    Write-Output 'PASS: Win10 registry mechanism, idempotent uninstall, package/registry/payload cleanup, unrelated menu preserved'
} finally {
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($sentinelPath, $false)
    foreach ($output in $outputs) { if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output } }
    if ($previous['ExePath']) {
        & "$PSScriptRoot\Install-ContextMenu.ps1" -ExePath $previous['ExePath'] -Mode $previous['Mode']
    } else { & "$PSScriptRoot\Uninstall-ContextMenu.ps1" }
}
