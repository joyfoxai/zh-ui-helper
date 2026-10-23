#requires -Version 5.1
# These tests parse source and replace operating-system operations with in-memory mocks.
# They never create certificates, change trust, sign/install packages, or save shortcuts.
[CmdletBinding()]
param([string]$BuildDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:passed = 0
function Assert-Test([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Action) {
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-Test $threw 'Expected the unsafe input to be rejected.'
}
function Test-Case([string]$Name, [scriptblock]$Body) {
    $module = Import-Module (Join-Path $root 'Lifecycle.psm1') -Force -PassThru
    try { & $Body $module; $script:passed++; Write-Host ('PASS ' + $Name) } catch { throw ($Name + ': ' + $_.Exception.Message) }
}

Test-Case 'Both entry points support ShouldProcess and all three files parse' {
    foreach ($name in @('Install.ps1','Restore.ps1','Lifecycle.psm1')) {
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name), [ref]$tokens, [ref]$errors)
        Assert-Test (@($errors).Count -eq 0) ('Parser errors in ' + $name)
        if ($name -ne 'Lifecycle.psm1') {
            $binding = @($ast.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' })[0]
            $supports = @($binding.NamedArguments | Where-Object { $_.ArgumentName -eq 'SupportsShouldProcess' })[0]
            Assert-Test ($supports.Argument.SafeGetValue() -eq $true) 'Missing SupportsShouldProcess.'
        }
        $text = Get-Content -LiteralPath (Join-Path $root $name) -Raw
        Assert-Test ($text -notmatch '(?i)Set-ExecutionPolicy|Export-PfxCertificate|Stop-Process|taskkill|takeown|icacls|ExecutionPolicy\s+Bypass|Cert:\\LocalMachine\\Root') 'A forbidden system/security operation appeared.'
    }
}

foreach ($scenario in @('Exact','WrongFullName','WrongPublisher','WrongVersion','WrongPayload','MissingFullName','Absent')) {
    Test-Case ('Modifier ownership: ' + $scenario) {
        param($module)
        & $module {
            param($scenario)
            $script:scenario = $scenario
            $script:filter = $null
            function script:Get-AppxPackage {
                [CmdletBinding()]param($Name, $PackageTypeFilter)
                $script:filter = @($PackageTypeFilter)
                if ($script:scenario -eq 'Absent') { return }
                $full = 'ZhUiHelper.ClaudeZh.Local_0.3.0.1_x64__test'
                $publisher = 'CN=ZhUiHelper.ClaudeZh.Local'; $version = '0.3.0.1'
                if ($script:scenario -eq 'WrongFullName') { $full += '-other' }
                if ($script:scenario -eq 'WrongPublisher') { $publisher = 'CN=Other' }
                if ($script:scenario -eq 'WrongVersion') { $version = '0.3.0.2' }
                [pscustomobject]@{ Name = 'ZhUiHelper.ClaudeZh.Local'; Publisher = $publisher; PackageFullName = $full; Version = $version; InstallLocation = 'C:\fixture\modifier' }
            }
            function script:Get-ZhUiHash([string]$Path) { if ($script:scenario -eq 'WrongPayload') { return ('b' * 64) }; return ('a' * 64) }
            $audit = [pscustomobject]@{ package = [pscustomobject]@{ fullName = 'ZhUiHelper.ClaudeZh.Local_0.3.0.1_x64__test'; version = '0.3.0.1' } }
            if ($scenario -eq 'MissingFullName') { $audit.package.fullName = $null }
            $build = [pscustomobject]@{ files = [pscustomobject]@{ 'AppxManifest.xml' = ('a' * 64) } }
            if ($scenario -in @('Exact','Absent')) {
                $result = Get-ZhUiAuditedModifier $audit $build
                if ($scenario -eq 'Exact' -and $null -eq $result) { throw 'Exact modifier was not returned.' }
                if ($scenario -eq 'Absent' -and $null -ne $result) { throw 'An absent modifier was unexpectedly returned.' }
            } else {
                $threw = $false; try { Get-ZhUiAuditedModifier $audit $build | Out-Null } catch { $threw = $true }
                if (-not $threw) { throw 'Unsafe modifier was accepted.' }
            }
            if ($script:filter -notcontains 'Optional') { throw 'Optional package enumeration was omitted.' }
        } $scenario
    }
}

Test-Case 'Pre-existing certificates never request cleanup privileges' {
    param($module)
    & $module {
        function script:Assert-ZhUiAdministrator { throw 'Unexpected elevation request.' }
        function script:Get-AppxPackage { throw 'Unexpected package query for an unowned certificate.' }
        Assert-ZhUiCertificateCleanup ([pscustomobject]@{ certificate = [pscustomobject]@{ createdByTool = $false; importedByTool = $false; publicFile = $null } })
    }
}

Test-Case 'Other-user registration of the same modifier blocks certificate removal' {
    param($module)
    & $module {
        function script:Assert-ZhUiAdministrator { }
        function script:Get-AppxPackage {
            [CmdletBinding()]param([switch]$AllUsers, $PackageTypeFilter)
            if (-not $AllUsers -or @('Main','Framework','Resource','Optional','Bundle' | Where-Object { $_ -notin $PackageTypeFilter }).Count -gt 0) { throw 'Incomplete cross-user dependency query.' }
            [pscustomobject]@{ Publisher = 'CN=ZhUiHelper.ClaudeZh.Local'; PackageFullName = 'own-full-name' }
        }
        $audit = [pscustomobject]@{ package = [pscustomobject]@{ fullName = 'own-full-name' }; certificate = [pscustomobject]@{ createdByTool = $true; importedByTool = $false } }
        $message = $null; try { Assert-ZhUiCertificateCleanup $audit } catch { $message = $_.Exception.Message }
        if ($message -cne 'Another installed package uses the dedicated publisher. The certificate will be retained.') { throw 'Another-user registration was ignored or the dependency query failed unexpectedly.' }
    }
}

foreach ($scenario in @('Exact','Moved','ChangedBuildHash','ChangedCandidate','ChangedBase','ChangedVersion')) {
    Test-Case ('Lifecycle/build binding: ' + $scenario) {
        param($module)
        & $module {
            param($scenario)
            $script:lifecycle = [pscustomobject]@{
                schema = 1; toolId = 'zh-ui-helper-msix'; candidateId = '1667c3f9-2269-40ea-93ce-d9aee0669279'; installId = '11111111-2222-3333-4444-555555555555'
                auditPath = 'C:\fixture\lifecycle-audit.json'; buildAuditSha256 = ('a' * 64); certificate = $null
                package = [pscustomobject]@{ name = 'ZhUiHelper.ClaudeZh.Local'; publisher = 'CN=ZhUiHelper.ClaudeZh.Local'; version = '0.3.0.1'; architecture = 'x64'; unsignedSha256 = ('b' * 64) }
                base = [pscustomobject]@{ name = 'Claude'; version = '1.0.0.0' }
            }
            $script:build = [pscustomobject]@{ schema = 1; toolId = 'zh-ui-helper-msix'; noOriginalWrites = $true; candidateId = $script:lifecycle.candidateId; buildDirectory = 'C:\fixture'; packageSha256 = ('b' * 64); package = ($script:lifecycle.package | ConvertTo-Json | ConvertFrom-Json); base = ($script:lifecycle.base | ConvertTo-Json | ConvertFrom-Json) }
            $script:scenario = $scenario
            if ($scenario -eq 'Moved') { $script:lifecycle.auditPath = 'C:\elsewhere\lifecycle-audit.json' }
            if ($scenario -eq 'ChangedCandidate') { $script:build.candidateId = '99999999-2222-3333-4444-555555555555' }
            if ($scenario -eq 'ChangedBase') { $script:lifecycle.base.version = '2.0.0.0' }
            if ($scenario -eq 'ChangedVersion') { $script:lifecycle.package.version = '0.3.0.2' }
            function script:Assert-ZhUiPlainPath([string]$Path) { return $Path }
            function script:Resolve-Path { [CmdletBinding()]param($LiteralPath); [pscustomobject]@{ ProviderPath = $LiteralPath } }
            function script:Get-ZhUiHash([string]$Path) { if ($script:scenario -eq 'ChangedBuildHash') { return ('c' * 64) }; return ('a' * 64) }
            function script:Read-ZhUiJson([string]$Path) { if ([IO.Path]::GetFileName($Path) -eq 'build-audit.json') { return $script:build }; return $script:lifecycle }
            $threw = $false; try { Read-ZhUiLifecycle 'C:\fixture\lifecycle-audit.json' | Out-Null } catch { $threw = $true }
            if (($scenario -eq 'Exact') -eq $threw) { throw ('Wrong binding result for ' + $scenario) }
        } $scenario
    }
}

if (-not [string]::IsNullOrWhiteSpace($BuildDirectory)) {
    Test-Case 'Real unsigned candidate and official public resources pass read-only preflight' {
        $build = Read-ZhUiBuild $BuildDirectory
        Assert-Test ($build.Audit.files.PSObject.Properties.Name.Count -eq 6) 'Unexpected payload count.'
        $tampered = $build.Audit | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $first = @($tampered.files.PSObject.Properties.Name)[0]
        $tampered.files.$first = ('0' * 64)
        Assert-Throws { Assert-ZhUiArchive $build.Archive $tampered }
    }
}
Write-Host ($script:passed.ToString() + ' lifecycle checks passed; no OS mutations were executed.')
