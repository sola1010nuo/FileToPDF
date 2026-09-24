param([switch]$IncludeFailures)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$exe = (Resolve-Path publish/win-x64/FileToPDF.exe).Path
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
$tag = 'FileToPDF-test-' + [Guid]::NewGuid().ToString('N')
$dir = Join-Path (Resolve-Path artifacts/tests).Path $tag
New-Item -ItemType Directory $dir | Out-Null
$inputs = @()
$expected = @()
$fixtures = @('report.docx', 'report.doc', 'slides.pptx', 'slides.ppt', 'photo.jpg', '透明 image.png')
foreach ($fixture in $fixtures) {
    $name = $tag + '-' + $fixture
    $target = Join-Path $dir $name
    Copy-Item -LiteralPath (Join-Path 'artifacts/tests' $fixture) -Destination $target
    $inputs += $target
    $base = [IO.Path]::GetFileNameWithoutExtension($name)
    $pdf = Join-Path $desktop ($base + '.pdf')
    if ($expected -contains $pdf) { $pdf = Join-Path $desktop ($base + '_1.pdf') }
    $expected += $pdf
}
if ($IncludeFailures) {
    $broken = Join-Path $dir 'broken.docx'
    [IO.File]::WriteAllText($broken, 'not a ZIP document')
    $inputs = @($inputs[0], $broken, (Join-Path $dir 'missing.pptx'), (Resolve-Path artifacts/tests/broken.png).Path) + $inputs[1..5]
}
$arguments = ($inputs | ForEach-Object { '"' + $_ + '"' }) -join ' '
$process = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -WindowStyle Hidden
if (!$process.WaitForExit(240000)) { throw 'Published EXE timed out' }
$process.Refresh()
foreach ($pdf in $expected) {
    if (!(Test-Path -LiteralPath $pdf)) { throw "Missing PDF: $pdf" }
    $stream = [IO.File]::OpenRead($pdf)
    try { $bytes = New-Object byte[] 5; [void]$stream.Read($bytes, 0, 5) }
    finally { $stream.Dispose() }
    if ([Text.Encoding]::ASCII.GetString($bytes) -ne '%PDF-') { throw "Invalid PDF: $pdf" }
}
Write-Output "PASS: published single EXE produced all six Desktop PDFs (failures included: $IncludeFailures)."
# Remove only the exact, uniquely named PDFs created by this test.
foreach ($pdf in $expected) { Remove-Item -LiteralPath $pdf }
