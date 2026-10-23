#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)][string]$AuditPath,
    [switch]$RemoveTestCertificate
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Lifecycle.psm1') -Force
$record = Read-ZhUiLifecycle $AuditPath
$audit = $record.Audit
$audit.auditPath = $record.Path
$modifier = Get-ZhUiAuditedModifier $audit $record.BuildAudit
if ($null -ne $audit.shortcut -and $audit.shortcut.createdByTool -eq $true -and (Test-Path -LiteralPath $audit.shortcut.path)) { Assert-ZhUiShortcut $audit.shortcut }
if ($RemoveTestCertificate) { Assert-ZhUiCertificateCleanup $audit -BeforeRemoval }
if ($WhatIfPreference) {
    if ($null -ne $modifier) { [void]$PSCmdlet.ShouldProcess($modifier.PackageFullName, 'Wait for Claude to exit normally, then remove only this exact modifier package') }
    if ($null -ne $audit.shortcut -and $audit.shortcut.createdByTool -eq $true -and (Test-Path -LiteralPath $audit.shortcut.path)) { [void]$PSCmdlet.ShouldProcess($audit.shortcut.path, 'Remove the unchanged tool-created shortcut') }
    if ($RemoveTestCertificate -and $null -ne $audit.certificate) {
        if ($audit.certificate.importedByTool -eq $true) { [void]$PSCmdlet.ShouldProcess('Cert:\LocalMachine\TrustedPeople\' + $audit.certificate.thumbprint, 'Remove only the audited tool-imported trust certificate after checking other package dependencies') }
        if ($audit.certificate.createdByTool -eq $true) { [void]$PSCmdlet.ShouldProcess('Cert:\CurrentUser\My\' + $audit.certificate.thumbprint, 'Remove only the audited tool-created signing certificate after checking other package dependencies') }
        if ($null -ne $audit.certificate.publicFile) { [void]$PSCmdlet.ShouldProcess($audit.certificate.publicFile, 'Remove only the unchanged tool-exported public certificate file') }
    }
    [void]$PSCmdlet.ShouldProcess($record.Path, 'Record restoration results in the existing lifecycle audit')
    return
}
if (-not $PSCmdlet.ShouldProcess($record.Path, 'Record precise restoration actions in the existing lifecycle audit')) { return }
try {
    if ($null -ne $modifier) {
        Wait-ZhUiOfficialExit $audit.base.appDir
        $modifier = Get-ZhUiAuditedModifier $audit $record.BuildAudit
        if ($null -ne $modifier) {
            if (-not $PSCmdlet.ShouldProcess($modifier.PackageFullName, 'Remove only this exact audited localization modifier')) { throw 'Modifier removal was declined.' }
            Add-ZhUiOperation $audit 'RemoveModifier' $modifier.PackageFullName 'Intent'
            Write-ZhUiLifecycle $record.Path $audit
            Remove-AppxPackage -Package $modifier.PackageFullName -ErrorAction Stop
            if ($null -ne (Get-ZhUiAuditedModifier $audit $record.BuildAudit)) { throw 'The audited modifier is still registered.' }
            Add-ZhUiOperation $audit 'RemoveModifier' $modifier.PackageFullName 'Succeeded'
            Write-ZhUiLifecycle $record.Path $audit
        }
    }
    if ($null -ne $audit.shortcut -and $audit.shortcut.createdByTool -eq $true -and (Test-Path -LiteralPath $audit.shortcut.path)) {
        Assert-ZhUiShortcut $audit.shortcut
        if (-not $PSCmdlet.ShouldProcess($audit.shortcut.path, 'Remove the unchanged tool-created shortcut')) { throw 'Shortcut removal was declined.' }
        Remove-Item -LiteralPath $audit.shortcut.path -Force
        Add-ZhUiOperation $audit 'RemoveShortcut' $audit.shortcut.path 'Succeeded'
        Write-ZhUiLifecycle $record.Path $audit
    }
    if ($RemoveTestCertificate -and $null -ne $audit.certificate) {
        Assert-ZhUiCertificateCleanup $audit
        foreach ($store in @('LocalMachine\TrustedPeople', 'CurrentUser\My')) {
            $owned = ($store -ceq 'CurrentUser\My' -and $audit.certificate.createdByTool -eq $true) -or ($store -ceq 'LocalMachine\TrustedPeople' -and $audit.certificate.importedByTool -eq $true)
            $path = 'Cert:\' + $store + '\' + $audit.certificate.thumbprint
            if ($owned -and (Test-Path -LiteralPath $path)) {
                if (-not $PSCmdlet.ShouldProcess($path, 'Remove only the exact certificate newly created/imported by this installation')) { throw 'Certificate cleanup was declined.' }
                Add-ZhUiOperation $audit 'RemoveCertificate' $path 'Intent'
                Write-ZhUiLifecycle $record.Path $audit
                Remove-Item -LiteralPath $path -Force
                Add-ZhUiOperation $audit 'RemoveCertificate' $path 'Succeeded'
                Write-ZhUiLifecycle $record.Path $audit
            }
        }
        if ($null -ne $audit.certificate.publicFile -and (Test-Path -LiteralPath $audit.certificate.publicFile)) {
            if (-not $PSCmdlet.ShouldProcess($audit.certificate.publicFile, 'Remove only the unchanged tool-exported public certificate')) { throw 'Public certificate cleanup was declined.' }
            Remove-Item -LiteralPath $audit.certificate.publicFile -Force
            Add-ZhUiOperation $audit 'RemovePublicCertificate' $audit.certificate.publicFile 'Succeeded'
        }
    }
    $audit.state = 'Restored'; $audit.failure = $null
    Write-ZhUiLifecycle $record.Path $audit
    Write-Host 'Removed the recorded localization modifier and its recorded shortcut. Official Claude and its user data were not modified.'
} catch {
    $audit.state = 'RestoreFailed'; $audit.failure = $_.Exception.Message
    Write-ZhUiLifecycle $record.Path $audit
    throw
}
