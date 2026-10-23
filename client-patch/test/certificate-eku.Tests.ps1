#requires -Version 5.1
# Only in-memory certificate fixtures and real .NET EKU extensions are used.
# Get-Item is mocked inside the module; no certificate store or key is accessed.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Lifecycle.psm1') -Force -PassThru
try {
    & $module {
        $script:ekuFixture = $null
        $script:ekuFixtureReads = 0
        function script:Get-Item {
            [CmdletBinding()]
            param([string]$LiteralPath)
            if ($LiteralPath -cne ('Cert:\CurrentUser\My\' + ('A' * 40))) { throw 'Unexpected fixture lookup.' }
            $script:ekuFixtureReads++
            return $script:ekuFixture
        }
        $cases = @(
            @{ Name = 'CodeSigning'; Oids = @('1.3.6.1.5.5.7.3.3'); Accepted = $true },
            @{ Name = 'ClientAuthentication'; Oids = @('1.3.6.1.5.5.7.3.2'); Accepted = $false },
            @{ Name = 'MissingEku'; Oids = @(); Accepted = $false },
            @{ Name = 'MixedEku'; Oids = @('1.3.6.1.5.5.7.3.3', '1.3.6.1.5.5.7.3.2'); Accepted = $true }
        )
        $passed = 0
        foreach ($case in $cases) {
            $oids = [Security.Cryptography.OidCollection]::new()
            foreach ($oid in $case.Oids) { [void]$oids.Add([Security.Cryptography.Oid]::new($oid)) }
            $extensions = @()
            if ($case.Oids.Count -gt 0) {
                $extensions = @([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids, $false))
            }
            $script:ekuFixture = [pscustomobject]@{
                Subject = 'CN=ZhUiHelper.ClaudeZh.Local'; HasPrivateKey = $true
                NotBefore = (Get-Date).AddDays(-1); NotAfter = (Get-Date).AddDays(1)
                Extensions = $extensions
            }
            $accepted = $true
            try { $null = Get-ZhUiCertificate ('A' * 40) } catch { $accepted = $false }
            if ($accepted -ne $case.Accepted) { throw ('Unexpected EKU decision: ' + $case.Name) }
            $passed++
            Write-Host ('PASS ' + $case.Name)
        }
        if ($script:ekuFixtureReads -ne 4) { throw 'Certificate lookup did not stay within the four mocked fixtures.' }
        Write-Host ($passed.ToString() + ' EKU checks passed; no certificate store or private key was accessed.')
    }
} finally { Remove-Module -ModuleInfo $module -Force }
