#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ExistingCertificate')]
param(
    [Parameter(Mandatory = $true)][string]$BuildDirectory,
    [Parameter(Mandatory = $true, ParameterSetName = 'CreateCertificate')][switch]$CreateTestCertificate,
    [Parameter(Mandatory = $true, ParameterSetName = 'ExistingCertificate')][string]$CertificateThumbprint,
    [switch]$TrustCertificate,
    [switch]$CreateShortcut
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Lifecycle.psm1') -Force
$constants = Get-ZhUiConstants
$build = Read-ZhUiBuild $BuildDirectory
$existing = @(Get-AppxPackage -Name $constants.PackageName -PackageTypeFilter Optional -ErrorAction Stop)
if ($existing.Count -gt 0) { throw 'A package with the dedicated modifier name is already installed. Restore its recorded installation before installing another build.' }
$certificate = $null
if ($CreateTestCertificate) {
    if (@(Get-ChildItem -LiteralPath 'Cert:\CurrentUser\My' | Where-Object { $_.Subject -ceq $constants.Publisher }).Count -gt 0) { throw 'A certificate with the dedicated subject already exists. Select it explicitly with -CertificateThumbprint instead of creating another.' }
} else { $certificate = Get-ZhUiCertificate $CertificateThumbprint }
if ($TrustCertificate -and -not $WhatIfPreference) { Assert-ZhUiAdministrator }
$shortcutPath = Get-ZhUiShortcutPath
if ($CreateShortcut) { $null = Assert-ZhUiPlainPath $shortcutPath }
if ($CreateShortcut -and (Test-Path -LiteralPath $shortcutPath)) { throw 'The dedicated shortcut path already exists and will not be overwritten.' }
$auditPath = Join-Path $build.Directory 'lifecycle-audit.json'
if ($WhatIfPreference) {
    [void]$PSCmdlet.ShouldProcess($auditPath, 'Create an exact lifecycle audit')
    if ($CreateTestCertificate) { [void]$PSCmdlet.ShouldProcess('Cert:\CurrentUser\My (' + $constants.Publisher + ')', 'Create a non-exportable, one-year code-signing test certificate') }
    [void]$PSCmdlet.ShouldProcess($build.Archive, 'Sign only this audited modifier package using CurrentUser\My')
    if ($TrustCertificate) { [void]$PSCmdlet.ShouldProcess('Cert:\LocalMachine\TrustedPeople', 'Export only the public certificate and import this exact dedicated certificate if absent') }
    [void]$PSCmdlet.ShouldProcess($build.Audit.base.aumid, 'Wait for the official Claude app to exit normally')
    [void]$PSCmdlet.ShouldProcess($constants.PackageName + ' ' + $build.Audit.package.version, 'Install the signed modification package for the current user')
    if ($CreateShortcut) { [void]$PSCmdlet.ShouldProcess($shortcutPath, 'Create a marked shortcut to the official Claude AUMID') }
    return
}
if (-not $PSCmdlet.ShouldProcess($auditPath, 'Create the installation lifecycle audit')) { return }
$audit = [ordered]@{
    schema = 1; toolId = $constants.ToolId; candidateId = $build.Audit.candidateId; installId = [guid]::NewGuid().ToString(); state = 'InProgress'
    createdAtUtc = [DateTime]::UtcNow.ToString('o'); updatedAtUtc = $null; auditPath = $auditPath; buildAuditSha256 = Get-ZhUiHash $build.AuditPath
    base = $build.Audit.base; package = [ordered]@{ name = $constants.PackageName; publisher = $constants.Publisher; version = $build.Audit.package.version; architecture = $build.Audit.package.architecture; fullName = $null; unsignedSha256 = $build.Audit.packageSha256; signedSha256 = $null }
    certificate = $null; shortcut = $null; operations = @(); failure = $null
}
Write-ZhUiLifecycle $auditPath $audit
try {
    if ($CreateTestCertificate) {
        if (-not $PSCmdlet.ShouldProcess('Cert:\CurrentUser\My', 'Create the dedicated non-exportable test certificate')) { throw 'Certificate creation was declined.' }
        Add-ZhUiOperation $audit 'CreateCertificate' $constants.Publisher 'Intent'
        Write-ZhUiLifecycle $auditPath $audit
        $certificate = New-SelfSignedCertificate -Type Custom -Subject $constants.Publisher -FriendlyName 'ZhUiHelper Claude localization (test only)' -KeyAlgorithm RSA -KeyLength 3072 -KeySpec Signature -KeyUsage DigitalSignature -KeyExportPolicy NonExportable -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}CA=false') -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(1)
        $audit.certificate = Get-ZhUiCertificateRecord $certificate $true
        Add-ZhUiOperation $audit 'CreateCertificate' $certificate.Thumbprint 'Succeeded'
        Write-ZhUiLifecycle $auditPath $audit
        $certificate = Get-ZhUiCertificate $certificate.Thumbprint
    } else { $audit.certificate = Get-ZhUiCertificateRecord $certificate $false }
    Write-ZhUiLifecycle $auditPath $audit
    Write-Host ('Signing certificate subject: ' + $certificate.Subject)
    Write-Host ('Signing certificate thumbprint: ' + $certificate.Thumbprint)
    if ($TrustCertificate) { Write-Host 'Requested trust store: LocalMachine\TrustedPeople (only this dedicated public certificate).' }
    if (-not $PSCmdlet.ShouldProcess($build.Archive, 'Sign this audited modifier package')) { throw 'Package signing was declined.' }
    Add-ZhUiOperation $audit 'SignPackage' $build.Archive 'Intent'
    Write-ZhUiLifecycle $auditPath $audit
    Invoke-ZhUiSign $build.SignTool $build.Archive $certificate.Thumbprint
    $audit.package.signedSha256 = Get-ZhUiHash $build.Archive
    Add-ZhUiOperation $audit 'SignPackage' $build.Archive 'Succeeded'
    Write-ZhUiLifecycle $auditPath $audit
    if ($TrustCertificate) {
        $trustPath = 'Cert:\LocalMachine\TrustedPeople\' + $certificate.Thumbprint
        $trusted = Get-Item -LiteralPath $trustPath -ErrorAction SilentlyContinue
        if ($null -eq $trusted) {
            if (-not $PSCmdlet.ShouldProcess($trustPath, 'Import only the dedicated public certificate into LocalMachine TrustedPeople')) { throw 'Explicit certificate trust was declined.' }
            $publicPath = Join-Path $build.Directory ('zh-ui-helper-public-' + $certificate.Thumbprint + '.cer')
            $null = Assert-ZhUiPlainPath $publicPath
            if (Test-Path -LiteralPath $publicPath) { throw 'The public certificate output path already exists.' }
            Add-ZhUiOperation $audit 'ExportPublicCertificate' $publicPath 'Intent'
            Write-ZhUiLifecycle $auditPath $audit
            Export-Certificate -Cert $certificate -FilePath $publicPath -Type CERT | Out-Null
            $null = Assert-ZhUiPlainPath $publicPath
            $audit.certificate.publicFile = $publicPath
            $audit.certificate.publicFileSha256 = Get-ZhUiHash $publicPath
            Add-ZhUiOperation $audit 'ExportPublicCertificate' $publicPath 'Succeeded'
            Add-ZhUiOperation $audit 'ImportTrust' $trustPath 'Intent'
            Write-ZhUiLifecycle $auditPath $audit
            $null = Assert-ZhUiPlainPath $publicPath
            if ((Get-ZhUiHash $publicPath) -cne $audit.certificate.publicFileSha256) { throw 'The exported public certificate changed before trust import.' }
            $imported = Import-Certificate -FilePath $publicPath -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople'
            if ($imported.Thumbprint -ine $certificate.Thumbprint) { throw 'Imported certificate does not match the signing certificate.' }
            $audit.certificate.importedByTool = $true
            Add-ZhUiOperation $audit 'ImportTrust' $trustPath 'Succeeded'
            Write-ZhUiLifecycle $auditPath $audit
        } elseif ((Get-ZhUiBytesHash $trusted.RawData) -cne $audit.certificate.publicSha256) { throw 'The existing TrustedPeople certificate does not match.' }
    }
    Assert-ZhUiTrustedSignature $build.SignTool $build.Archive $certificate.Thumbprint
    Wait-ZhUiOfficialExit $build.Audit.base.appDir
    $null = Assert-ZhUiBase $build.Audit
    if ((Get-ZhUiHash $build.Archive) -cne $audit.package.signedSha256) { throw 'The signed candidate changed before deployment.' }
    if (@(Get-AppxPackage -Name $constants.PackageName -PackageTypeFilter Optional -ErrorAction Stop).Count -gt 0) { throw 'A modifier appeared during preparation. This installation will not take it over.' }
    if (-not $PSCmdlet.ShouldProcess($constants.PackageName + ' ' + $audit.package.version, 'Install the exact signed modification package for the current user')) { throw 'Package installation was declined.' }
    Add-ZhUiOperation $audit 'InstallModifier' $build.Archive 'Intent'
    Write-ZhUiLifecycle $auditPath $audit
    try { Add-AppxPackage -Path $build.Archive -ErrorAction Stop } finally {
        $installed = @(Get-AppxPackage -Name $constants.PackageName -PackageTypeFilter Optional -ErrorAction SilentlyContinue | Where-Object { $_.Name -ceq $constants.PackageName -and $_.Publisher -ceq $constants.Publisher -and [string]$_.Version -ceq $audit.package.version })
        if ($installed.Count -eq 1) { $audit.package.fullName = $installed[0].PackageFullName; Write-ZhUiLifecycle $auditPath $audit }
    }
    if ([string]::IsNullOrWhiteSpace($audit.package.fullName)) { throw 'Deployment did not yield exactly one matching registered modifier.' }
    Add-ZhUiOperation $audit 'InstallModifier' $audit.package.fullName 'Succeeded'
    Write-ZhUiLifecycle $auditPath $audit
    if ($CreateShortcut) {
        if (-not $PSCmdlet.ShouldProcess($shortcutPath, 'Create the marked official Claude AUMID shortcut')) { throw 'Shortcut creation was declined.' }
        Add-ZhUiOperation $audit 'CreateShortcut' $shortcutPath 'Intent'
        Write-ZhUiLifecycle $auditPath $audit
        New-ZhUiShortcut $shortcutPath $build.Audit.base.aumid
        $audit.shortcut = [ordered]@{ path = $shortcutPath; aumid = $build.Audit.base.aumid; description = $constants.ShortcutDescription; createdByTool = $true; sha256 = Get-ZhUiHash $shortcutPath }
        Add-ZhUiOperation $audit 'CreateShortcut' $shortcutPath 'Succeeded'
    }
    $audit.state = 'Installed'
    Write-ZhUiLifecycle $auditPath $audit
    Write-Host ('Installed only the localization modifier. Open Claude normally. Recovery audit: ' + $auditPath)
} catch {
    $audit.state = 'Failed'; $audit.failure = $_.Exception.Message
    Write-ZhUiLifecycle $auditPath $audit
    throw
}
