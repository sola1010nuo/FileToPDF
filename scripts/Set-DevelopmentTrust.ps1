#requires -Version 5.1
# The ONLY elevated component. It never installs an Appx package for an administrator account.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Add','Remove')][string]$Action,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$Thumbprint,
    [string]$CertificatePath
)
$ErrorActionPreference = 'Stop'
try {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator approval is required for machine certificate trust.' }
    $certificateStorePath = "Cert:\LocalMachine\TrustedPeople\$Thumbprint"
    $marker = "HKLM:\SOFTWARE\FileToPDF\DevelopmentTrust\$Thumbprint"
    if ($Action -eq 'Add') {
        $certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
        if ($certificate.Thumbprint -ne $Thumbprint -or $certificate.Subject -ne 'CN=FileToPDF' -or $certificate.Issuer -ne $certificate.Subject) {
            throw 'This helper accepts only the expected FileToPDF self-signed development certificate.'
        }
        if (!(Test-Path -LiteralPath $certificateStorePath)) {
            Import-Certificate -FilePath $CertificatePath -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
            New-Item -Path $marker -Force | Out-Null
            Set-ItemProperty -LiteralPath $marker -Name Publisher -Value $certificate.Subject
        } elseif (!(Test-Path -LiteralPath $marker)) { exit 10 } # Pre-existing trust is not ours to remove.
    } elseif (Test-Path -LiteralPath $marker) {
        $publisher = (Get-ItemProperty -LiteralPath $marker).Publisher
        # A shared certificate must remain trusted while another user/package still needs it.
        $users = @(Get-AppxPackage -AllUsers | Where-Object { $_.Publisher -eq $publisher })
        if ($users.Count -gt 0) { exit 10 }
        if (Test-Path -LiteralPath $certificateStorePath) { Remove-Item -LiteralPath $certificateStorePath }
        Remove-Item -LiteralPath $marker
    }
    exit 0
} catch {
    Write-Error $_
    exit 1
}
