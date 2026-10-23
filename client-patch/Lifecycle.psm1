Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ToolId = 'zh-ui-helper-msix'
$script:PackageName = 'ZhUiHelper.ClaudeZh.Local'
$script:Publisher = 'CN=ZhUiHelper.ClaudeZh.Local'
$script:ShortcutDescription = 'ZhUiHelper Claude Chinese entry - launches the official Claude application'
$script:ResourceFiles = @('resources/ion-dist/index.html', 'resources/zh-Hans.json', 'resources/ion-dist/i18n/zh-Hans.json', 'resources/ion-dist/i18n/dynamic/zh-Hans.json')
$script:SourceFiles = @('claude.exe', 'resources/app.asar', 'resources/en-US.json', 'resources/zh-Hans.json', 'resources/ion-dist/index.html', 'resources/ion-dist/i18n/en-US.json', 'resources/ion-dist/i18n/dynamic/en-US.json')

function Get-ZhUiConstants {
    [pscustomobject]@{ ToolId = $script:ToolId; PackageName = $script:PackageName; Publisher = $script:Publisher; ShortcutDescription = $script:ShortcutDescription }
}

function Get-ZhUiHash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

function Get-ZhUiBytesHash([byte[]]$Bytes) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() } finally { $hash.Dispose() }
}

function Get-ZhUiProperty($Object, [string]$Name, $Default = $null) {
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function Assert-ZhUiHash([string]$Value, [string]$Label) {
    if ($Value -cnotmatch '^[a-fA-F0-9]{64}$') { throw "$Label is not a SHA256 digest." }
}

function Get-ZhUiFullPath([string]$Path) { [IO.Path]::GetFullPath($Path).TrimEnd('\', '/') }

function Assert-ZhUiPlainPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if ($root -notmatch '^[A-Za-z]:\\$' -or $full.Substring($root.Length).Contains(':')) { throw 'Only a local filesystem path without alternate streams is allowed.' }
    $current = $full
    while (-not [string]::IsNullOrEmpty($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse points and junctions are not allowed in lifecycle paths: $current" }
        }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { break }
        $current = $parent.FullName
    }
    return $full
}

function Assert-ZhUiSamePath([string]$Actual, [string]$Expected, [string]$Label) {
    if ((Get-ZhUiFullPath $Actual) -ine (Get-ZhUiFullPath $Expected)) { throw "$Label does not match the audited path." }
}

function Read-ZhUiJson([string]$Path) {
    $null = Assert-ZhUiPlainPath $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing audit file: $Path" }
    if ((Get-Item -LiteralPath $Path).Length -gt 8388608) { throw 'Audit file exceeds the size limit.' }
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function ConvertTo-ZhUiXml([string]$Text) {
    $settings = New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create((New-Object IO.StringReader($Text)), $settings)
    try {
        $document = New-Object Xml.XmlDocument
        $document.XmlResolver = $null
        $document.Load($reader)
        return ,$document
    } finally { $reader.Dispose() }
}

function Assert-ZhUiAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This explicit certificate trust/cleanup action requires an elevated PowerShell window.'
    }
}

function Get-ZhUiSdkTool([string]$Path, [string]$FileName) {
    if (-not [IO.Path]::IsPathRooted($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing existing Windows SDK tool: $FileName" }
    $full = (Resolve-Path -LiteralPath $Path).ProviderPath
    $sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (-not $full.StartsWith((Get-ZhUiFullPath $sdkRoot) + '\', [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -ine $FileName) {
        throw "The audited $FileName must be an existing Windows SDK binary."
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $full
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)') {
        throw "The Windows SDK binary does not have a valid Microsoft signature: $FileName"
    }
    return $full
}

function Assert-ZhUiNode {
    $command = Get-Command node.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $versionText = & $command.Source --version
    if ($LASTEXITCODE -ne 0 -or "$versionText" -notmatch '^v(\d+)\.\d+\.\d+') { throw 'Unable to read the installed Node.js version.' }
    if ([int]$Matches[1] -lt 20) { throw 'Node.js 20 or newer must already be installed. No runtime is downloaded.' }
}

function Read-ZhUiBuild([string]$BuildDirectory) {
    $null = Assert-ZhUiPlainPath $BuildDirectory
    $directory = (Resolve-Path -LiteralPath $BuildDirectory -ErrorAction Stop).ProviderPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw 'BuildDirectory must be an existing directory.' }
    $auditPath = Join-Path $directory 'build-audit.json'
    $audit = Read-ZhUiJson $auditPath
    if ($audit.schema -ne 1 -or $audit.toolId -cne $script:ToolId -or $audit.noOriginalWrites -ne $true) { throw 'Unsupported or unsafe build audit.' }
    Assert-ZhUiSamePath $audit.buildDirectory $directory 'Build audit directory'
    $candidateId = [guid]::Empty
    if (-not [guid]::TryParse([string]$audit.candidateId, [ref]$candidateId)) { throw 'Invalid build candidate ID.' }
    if ($audit.package.name -cne $script:PackageName -or $audit.package.publisher -cne $script:Publisher) { throw 'Only the dedicated ZhUiHelper modifier identity is allowed.' }
    $version = $null
    if (-not [version]::TryParse([string]$audit.package.version, [ref]$version) -or $version.Revision -lt 0) { throw 'Invalid four-part candidate version.' }
    if ($audit.package.architecture -cne 'x64') { throw 'This installer currently supports only the reviewed x64 VFS mapping.' }
    $archive = Join-Path $directory 'candidate.msix'
    $null = Assert-ZhUiPlainPath $archive
    Assert-ZhUiHash $audit.packageSha256 'Candidate hash'
    if ((Get-ZhUiHash $archive) -cne $audit.packageSha256.ToLowerInvariant()) { throw 'The unsigned candidate differs from build-audit.json. Use a fresh build directory.' }
    if (Test-Path -LiteralPath (Join-Path $directory 'lifecycle-audit.json')) { throw 'This directory already contains a lifecycle audit. Restore that installation or use a fresh build directory.' }
    Assert-ZhUiNode
    $makeappx = Get-ZhUiSdkTool $audit.tools.makeappx 'makeappx.exe'
    $signtool = Get-ZhUiSdkTool $audit.tools.signtool 'signtool.exe'
    Assert-ZhUiSamePath ([IO.Path]::GetDirectoryName($makeappx)) ([IO.Path]::GetDirectoryName($signtool)) 'Windows SDK tools directory'
    $base = Assert-ZhUiBase $audit
    Assert-ZhUiArchive $archive $audit
    [pscustomobject]@{ Directory = $directory; AuditPath = $auditPath; Audit = $audit; Archive = $archive; Base = $base; SignTool = $signtool }
}

function Assert-ZhUiBase($Audit) {
    if ($Audit.base.name -cne 'Claude' -or $Audit.base.packageFamilyName -cne 'Claude_pzs8sxrjxfjjc') { throw 'The main package must have the official Claude package identity.' }
    $packages = @(Get-AppxPackage -Name $Audit.base.name -PackageTypeFilter Main -ErrorAction Stop | Where-Object { $_.Name -ceq $Audit.base.name -and $_.Publisher -ceq $Audit.base.publisher })
    if ($packages.Count -ne 1) { throw 'Exactly one matching official Claude package must be registered for the current user.' }
    $package = $packages[0]
    if ($package.PackageFullName -cne $Audit.base.packageFullName -or $package.PackageFamilyName -cne $Audit.base.packageFamilyName -or [string]$package.Version -cne $Audit.base.version) { throw 'Claude changed since this build. Rebuild against the currently installed app.' }
    Assert-ZhUiSamePath $package.InstallLocation $Audit.base.installLocation 'Official package location'
    Assert-ZhUiSamePath (Join-Path $package.InstallLocation 'app') $Audit.base.appDir 'Official application directory'
    $manifestPath = Join-Path $package.InstallLocation 'AppxManifest.xml'
    Assert-ZhUiHash $Audit.base.manifestSha256 'Official manifest hash'
    if ((Get-ZhUiHash $manifestPath) -cne $Audit.base.manifestSha256.ToLowerInvariant()) { throw 'The official package manifest changed after the build.' }
    $manifest = ConvertTo-ZhUiXml (Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8)
    $identity = $manifest.SelectSingleNode('/*[local-name()="Package"]/*[local-name()="Identity"]')
    if ($null -eq $identity -or $identity.GetAttribute('Name') -cne $package.Name -or $identity.GetAttribute('Publisher') -cne $package.Publisher -or $identity.GetAttribute('Version') -cne [string]$package.Version) { throw 'Official manifest identity does not match the registered package.' }
    $apps = @($manifest.SelectNodes('/*[local-name()="Package"]/*[local-name()="Applications"]/*[local-name()="Application"]') | Where-Object { $_.GetAttribute('Id') -ceq $Audit.base.appId })
    if ($apps.Count -ne 1 -or $apps[0].GetAttribute('Executable').Replace('/', '\') -ine 'app\Claude.exe' -or $Audit.base.aumid -cne ($package.PackageFamilyName + '!' + $Audit.base.appId)) { throw 'The official application ID or executable does not match the build.' }
    $source = $Audit.base.sourceSnapshot.files
    $names = @($source.PSObject.Properties.Name)
    if ($names.Count -lt $script:SourceFiles.Count -or $names.Count -gt 64 -or @($script:SourceFiles | Where-Object { $_ -cnotin $names }).Count -gt 0) { throw 'Incomplete source snapshot file list.' }
    foreach ($relative in $names) {
        $optionalLocale = $relative -cin @('resources/ion-dist/i18n/zh-Hans.json', 'resources/ion-dist/i18n/dynamic/zh-Hans.json')
        $segments = @($relative.Split('/'))
        $publicAsset = $relative -cmatch '^resources/ion-dist/(?:[A-Za-z0-9._@+~-]+/)*[A-Za-z0-9._@+~-]+\.m?js$' -and @($segments | Where-Object { $_ -cin @('.', '..') }).Count -eq 0
        if ($relative -cnotin $script:SourceFiles -and -not $optionalLocale -and -not $publicAsset) { throw 'Unexpected source snapshot path outside the known public app resources.' }
        $path = Join-Path $Audit.base.appDir $relative
        $expected = $source.$relative
        if ($null -eq $expected) {
            if ($relative -cnotin @('resources/zh-Hans.json','resources/ion-dist/i18n/zh-Hans.json','resources/ion-dist/i18n/dynamic/en-US.json','resources/ion-dist/i18n/dynamic/zh-Hans.json')) { throw "A required source file cannot have a null snapshot hash: $relative" }
            if (Test-Path -LiteralPath $path) { throw "A previously absent source file now exists: $relative" }
        } else {
            Assert-ZhUiHash $expected "Source $relative"
            if ((Get-ZhUiHash $path) -cne $expected.ToLowerInvariant()) { throw "The official source file changed: $relative" }
        }
    }
    $programFiles = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    $location = Get-ZhUiFullPath $package.InstallLocation
    $programFiles = Get-ZhUiFullPath $programFiles
    if (-not $location.StartsWith($programFiles + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'This build supports only official packages under the Program Files known folder.' }
    $relativeBase = $location.Substring($programFiles.Length + 1).Replace('\', '/')
    if ($Audit.mapping.knownFolder -cne 'FOLDERID_ProgramFilesX64' -or $Audit.mapping.vfsFolder -cne 'ProgramFilesX64' -or $Audit.mapping.relativeBase -cne $relativeBase) { throw 'The VFS mapping does not match the current official package location.' }
    return $package
}

function Assert-ZhUiArchive([string]$Archive, $Audit) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $expected = @('AppxManifest.xml', 'candidate-logo.png')
        $prefix = 'VFS/' + $Audit.mapping.vfsFolder + '/' + $Audit.mapping.relativeBase + '/app/'
        $expected += @($script:ResourceFiles | ForEach-Object { $prefix + $_ })
        $fileNames = @($Audit.files.PSObject.Properties.Name)
        if ($fileNames.Count -ne 6 -or @($fileNames | Where-Object { $_ -cnotin $expected }).Count -gt 0) { throw 'The build audit must enumerate exactly four VFS resources, the manifest and the custom logo.' }
        $allowed = $expected + @('AppxBlockMap.xml', '[Content_Types].xml')
        $entries = @($zip.Entries)
        if ($entries.Count -ne 8 -or @($entries | Where-Object { $_.FullName -cnotin $allowed }).Count -gt 0 -or @($entries.FullName | Select-Object -Unique).Count -ne 8) { throw 'Unexpected archive entry. Executables, services and additional payload are prohibited.' }
        foreach ($name in $expected) {
            $entry = $zip.GetEntry($name)
            if ($null -eq $entry -or $entry.Length -gt 67108864) { throw "Missing or oversized candidate resource: $name" }
            $stream = $entry.Open()
            $memory = New-Object IO.MemoryStream
            try { $stream.CopyTo($memory); $bytes = $memory.ToArray() } finally { $stream.Dispose(); $memory.Dispose() }
            Assert-ZhUiHash $Audit.files.$name "Payload $name"
            if ((Get-ZhUiBytesHash $bytes) -cne $Audit.files.$name.ToLowerInvariant()) { throw "Candidate payload hash mismatch: $name" }
            if ($name -ceq 'AppxManifest.xml') { $manifest = ConvertTo-ZhUiXml ([Text.Encoding]::UTF8.GetString($bytes)) }
        }
        $identity = $manifest.SelectSingleNode('/*[local-name()="Package"]/*[local-name()="Identity"]')
        foreach ($pair in @(@('Name','name'), @('Publisher','publisher'), @('Version','version'), @('ProcessorArchitecture','architecture'))) {
            if ($identity.GetAttribute($pair[0]) -cne $Audit.package.($pair[1])) { throw 'Candidate manifest identity does not match its audit.' }
        }
        $modification = $manifest.SelectSingleNode('/*[local-name()="Package"]/*[local-name()="Properties"]/*[local-name()="ModificationPackage"]')
        if ($null -eq $modification -or $modification.InnerText -cne 'true') { throw 'The candidate must be an MSIX modification package.' }
        $dependencies = @($manifest.SelectNodes('/*[local-name()="Package"]/*[local-name()="Dependencies"]/*[local-name()="MainPackageDependency"]'))
        if ($dependencies.Count -ne 1 -or $dependencies[0].GetAttribute('Name') -cne $Audit.base.name -or $dependencies[0].GetAttribute('Publisher') -cne $Audit.base.publisher) { throw 'Candidate dependency does not match the official package.' }
        if ($null -ne $manifest.SelectSingleNode('/*[local-name()="Package"]/*[local-name()="Applications" or local-name()="Capabilities" or local-name()="Extensions"]')) { throw 'Executable, service and capability declarations are not allowed.' }
    } finally { $zip.Dispose() }
}

function Get-ZhUiCertificate([string]$Thumbprint) {
    $normalized = $Thumbprint.Replace(' ', '').ToUpperInvariant()
    if ($normalized -cnotmatch '^[A-F0-9]{40}$') { throw 'CertificateThumbprint must be an exact SHA1 certificate thumbprint.' }
    $certificate = Get-Item -LiteralPath ('Cert:\CurrentUser\My\' + $normalized) -ErrorAction Stop
    if ($certificate.Subject -cne $script:Publisher -or -not $certificate.HasPrivateKey) { throw 'The signing certificate must have the dedicated tool subject and a private key in CurrentUser\My.' }
    if ($certificate.NotBefore -gt (Get-Date) -or $certificate.NotAfter -le (Get-Date)) { throw 'The signing certificate is outside its validity period.' }
    $allowsCodeSigning = $false
    foreach ($extension in $certificate.Extensions) {
        if ($extension -is [Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) {
            foreach ($usage in $extension.EnhancedKeyUsages) {
                if ($usage.Value -ceq '1.3.6.1.5.5.7.3.3') { $allowsCodeSigning = $true }
            }
        }
    }
    if (-not $allowsCodeSigning) { throw 'The selected certificate must explicitly allow code signing.' }
    return $certificate
}

function Get-ZhUiCertificateRecord($Certificate, [bool]$Created) {
    [ordered]@{ subject = $script:Publisher; thumbprint = $Certificate.Thumbprint; publicSha256 = Get-ZhUiBytesHash $Certificate.RawData; privateStore = 'CurrentUser\My'; createdByTool = $Created; trustStore = 'LocalMachine\TrustedPeople'; importedByTool = $false; publicFile = $null; publicFileSha256 = $null }
}

function Write-ZhUiLifecycle([string]$Path, $Audit) {
    $null = Assert-ZhUiPlainPath $Path
    $Audit.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $temporary = $Path + '.tmp-' + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporary, ($Audit | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
        $null = Assert-ZhUiPlainPath $temporary
        Move-Item -LiteralPath $temporary -Destination $Path -Force
        $null = Assert-ZhUiPlainPath $Path
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}

function Add-ZhUiOperation($Audit, [string]$Action, [string]$Target, [string]$Outcome) {
    $Audit.operations = @($Audit.operations) + @([ordered]@{ atUtc = [DateTime]::UtcNow.ToString('o'); action = $Action; target = $Target; outcome = $Outcome })
}

function Wait-ZhUiOfficialExit([string]$AppDirectory) {
    $running = @(Get-Process -Name Claude -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        Write-Host 'Waiting for every Claude.exe process to exit normally. Close all Claude windows, tray icons and older copied instances to continue.'
        $running | Wait-Process -ErrorAction SilentlyContinue
    }
}

function Invoke-ZhUiSign([string]$SignTool, [string]$Archive, [string]$Thumbprint) {
    $null = Assert-ZhUiPlainPath $Archive
    & $SignTool sign /fd SHA256 /sha1 $Thumbprint /s My $Archive | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "SignTool signing failed with exit code $LASTEXITCODE." }
    $null = Assert-ZhUiPlainPath $Archive
    $signature = Get-AuthenticodeSignature -LiteralPath $Archive
    if ($null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ine $Thumbprint -or $signature.Status -in @('NotSigned','HashMismatch','NotSupportedFileFormat','Incompatible')) { throw 'Authenticode did not confirm the exact signing certificate.' }
}

function Assert-ZhUiTrustedSignature([string]$SignTool, [string]$Archive, [string]$Thumbprint) {
    $signature = Get-AuthenticodeSignature -LiteralPath $Archive
    if ($null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ine $Thumbprint) { throw 'The signed package certificate changed.' }
    & $SignTool verify /pa /all $Archive | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'The package signature is not trusted. For a tool-created test certificate, explicitly use -TrustCertificate in an elevated PowerShell window.' }
}

function Get-ZhUiShortcutPath {
    $name = 'Claude ' + [char]0x4e2d + [char]0x6587 + ' (ZhUiHelper).lnk'
    Join-Path ([Environment]::GetFolderPath('Desktop')) $name
}

function New-ZhUiShortcut([string]$Path, [string]$Aumid) {
    $null = Assert-ZhUiPlainPath $Path
    if (Test-Path -LiteralPath $Path) { throw 'A shortcut already exists at the dedicated path. It will not be overwritten.' }
    $shell = New-Object -ComObject WScript.Shell
    try {
        $shortcut = $shell.CreateShortcut($Path)
        $shortcut.TargetPath = Join-Path $env:SystemRoot 'explorer.exe'
        $shortcut.Arguments = 'shell:AppsFolder\' + $Aumid
        $shortcut.Description = $script:ShortcutDescription
        $shortcut.Save()
        $null = Assert-ZhUiPlainPath $Path
    } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
}

function Assert-ZhUiShortcut($Record) {
    $null = Assert-ZhUiPlainPath $Record.path
    Assert-ZhUiSamePath $Record.path (Get-ZhUiShortcutPath) 'Shortcut path'
    Assert-ZhUiHash $Record.sha256 'Shortcut hash'
    if ((Get-ZhUiHash $Record.path) -cne $Record.sha256) { throw 'The shortcut was changed after installation and will not be removed.' }
    $shell = New-Object -ComObject WScript.Shell
    try {
        $shortcut = $shell.CreateShortcut($Record.path)
        if ($shortcut.Description -cne $script:ShortcutDescription -or $shortcut.Arguments -cne ('shell:AppsFolder\' + $Record.aumid)) { throw 'The shortcut no longer has the tool-owned marker and target.' }
        Assert-ZhUiSamePath $shortcut.TargetPath (Join-Path $env:SystemRoot 'explorer.exe') 'Shortcut executable'
    } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
}

function Read-ZhUiLifecycle([string]$Path) {
    $null = Assert-ZhUiPlainPath $Path
    $full = (Resolve-Path -LiteralPath $Path).ProviderPath
    $audit = Read-ZhUiJson $full
    if ($audit.schema -ne 1 -or $audit.toolId -cne $script:ToolId -or $audit.package.name -cne $script:PackageName -or $audit.package.publisher -cne $script:Publisher) { throw 'This is not a lifecycle audit for the dedicated ZhUiHelper modifier.' }
    foreach ($id in @('candidateId','installId')) {
        $parsed = [guid]::Empty
        if (-not [guid]::TryParse([string]$audit.$id, [ref]$parsed)) { throw "Invalid lifecycle $id." }
    }
    Assert-ZhUiSamePath $audit.auditPath $full 'Lifecycle audit location'
    $buildPath = Join-Path ([IO.Path]::GetDirectoryName($full)) 'build-audit.json'
    Assert-ZhUiHash $audit.buildAuditSha256 'Original build audit hash'
    if ((Get-ZhUiHash $buildPath) -cne $audit.buildAuditSha256) { throw 'The neighboring build audit changed or this lifecycle audit was moved.' }
    $buildAudit = Read-ZhUiJson $buildPath
    if ($buildAudit.schema -ne 1 -or $buildAudit.toolId -cne $script:ToolId -or $buildAudit.noOriginalWrites -ne $true -or $buildAudit.candidateId -cne $audit.candidateId) { throw 'Lifecycle and build audits are not bound to the same candidate.' }
    Assert-ZhUiSamePath $buildAudit.buildDirectory ([IO.Path]::GetDirectoryName($full)) 'Original build directory'
    foreach ($field in @('name','publisher','version','architecture')) {
        if ($audit.package.$field -cne $buildAudit.package.$field) { throw 'Lifecycle package identity differs from its original build audit.' }
    }
    if ($audit.package.unsignedSha256 -cne $buildAudit.packageSha256 -or ($audit.base | ConvertTo-Json -Compress -Depth 20) -cne ($buildAudit.base | ConvertTo-Json -Compress -Depth 20)) { throw 'Lifecycle base identity or unsigned package differs from its original build audit.' }
    if ($null -ne $audit.certificate) {
        if ($audit.certificate.subject -cne $script:Publisher -or $audit.certificate.privateStore -cne 'CurrentUser\My' -or $audit.certificate.trustStore -cne 'LocalMachine\TrustedPeople' -or $audit.certificate.thumbprint -cnotmatch '^[A-Fa-f0-9]{40}$') { throw 'Lifecycle certificate identity or store is outside the tool scope.' }
        Assert-ZhUiHash $audit.certificate.publicSha256 'Audited certificate hash'
    }
    [pscustomobject]@{ Path = $full; Audit = $audit; BuildAudit = $buildAudit }
}

function Get-ZhUiAuditedModifier($Audit, $BuildAudit) {
    $packages = @(Get-AppxPackage -Name $script:PackageName -PackageTypeFilter Optional -ErrorAction Stop)
    if ($packages.Count -eq 0) { return $null }
    if ([string]::IsNullOrWhiteSpace([string]$Audit.package.fullName)) { throw 'The audit has no exact installed package full name. No package will be removed automatically.' }
    if ($packages.Count -ne 1 -or $packages[0].Name -cne $script:PackageName -or $packages[0].Publisher -cne $script:Publisher -or $packages[0].PackageFullName -cne $Audit.package.fullName -or [string]$packages[0].Version -cne $Audit.package.version) { throw 'The installed modifier differs from the audited package. No package will be removed.' }
    if ($null -eq $BuildAudit) { throw 'The bound build audit is required to verify the installed modifier resources.' }
    foreach ($file in $BuildAudit.files.PSObject.Properties) {
        if ([IO.Path]::IsPathRooted($file.Name) -or $file.Name.Contains(':') -or @($file.Name.Replace('\','/').Split('/') | Where-Object { $_ -cin @('.','..','') }).Count -gt 0) { throw 'Unsafe installed modifier payload path in the build audit.' }
        Assert-ZhUiHash $file.Value 'Installed modifier payload hash'
        $path = Join-Path $packages[0].InstallLocation $file.Name
        if ((Get-ZhUiHash $path) -cne $file.Value) { throw 'The installed modifier payload differs from the exact audited build. No package will be removed.' }
    }
    return $packages[0]
}

function Assert-ZhUiCertificateCleanup($Audit, [switch]$BeforeRemoval) {
    if ($null -eq $Audit.certificate) { return }
    $hasOwnedCertificate = $Audit.certificate.createdByTool -eq $true -or $Audit.certificate.importedByTool -eq $true
    if ($hasOwnedCertificate) {
        Assert-ZhUiAdministrator
        $others = @(Get-AppxPackage -AllUsers -PackageTypeFilter Main,Framework,Resource,Optional,Bundle -ErrorAction Stop | Where-Object {
            $_.Publisher -ceq $script:Publisher -and (-not $BeforeRemoval -or $_.PackageFullName -cne $Audit.package.fullName)
        })
        if ($others.Count -gt 0) { throw 'Another installed package uses the dedicated publisher. The certificate will be retained.' }
        foreach ($store in @('CurrentUser\My', 'LocalMachine\TrustedPeople')) {
            $owned = ($store -ceq 'CurrentUser\My' -and $Audit.certificate.createdByTool -eq $true) -or ($store -ceq 'LocalMachine\TrustedPeople' -and $Audit.certificate.importedByTool -eq $true)
            if (-not $owned) { continue }
            $certificate = Get-Item -LiteralPath ('Cert:\' + $store + '\' + $Audit.certificate.thumbprint) -ErrorAction SilentlyContinue
            if ($null -ne $certificate -and ($certificate.Subject -cne $script:Publisher -or (Get-ZhUiBytesHash $certificate.RawData) -cne $Audit.certificate.publicSha256)) { throw 'The certificate no longer matches the exact audited public certificate.' }
        }
    }
    if ($null -ne $Audit.certificate.publicFile -and (Test-Path -LiteralPath $Audit.certificate.publicFile)) {
        $null = Assert-ZhUiPlainPath $Audit.certificate.publicFile
        $expected = Join-Path ([IO.Path]::GetDirectoryName($Audit.auditPath)) ('zh-ui-helper-public-' + $Audit.certificate.thumbprint + '.cer')
        Assert-ZhUiSamePath $Audit.certificate.publicFile $expected 'Exported public certificate'
        Assert-ZhUiHash $Audit.certificate.publicFileSha256 'Exported public certificate hash'
        if ((Get-ZhUiHash $Audit.certificate.publicFile) -cne $Audit.certificate.publicFileSha256) { throw 'The exported public certificate changed and will not be removed.' }
    }
}

Export-ModuleMember -Function *-ZhUi*
