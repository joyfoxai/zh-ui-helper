#!/usr/bin/env node
'use strict';
// Build only: no certificates, signing, registration, shortcuts, ACL changes,
// profile reads, app launches, executable copies, or writes to the base package.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const zlib = require('node:zlib');
const core = require('./lib/catalogs.cjs');
const TOOL = 'zh-ui-helper-msix';
const NAME = 'ZhUiHelper.ClaudeZh.Local';
const PUBLISHER = 'CN=ZhUiHelper.ClaudeZh.Local';
const OFFICIAL_FAMILY = 'Claude_pzs8sxrjxfjjc';
const MARKER = 'zh-ui-helper:msix-locale-setup:v1';
const fail = message => { throw new Error(message); };
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const fileHash = file => sha(fs.readFileSync(file));
const at = (root, relative) => path.join(root, ...relative.split('/'));
const key = file => path.resolve(file).toLowerCase();
const within = (file, root) => key(file) === key(root) || key(file).startsWith(key(root) + path.sep);
const xml = text => String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
const jsonBytes = value => Buffer.from(JSON.stringify(value, null, 2) + '\n');

function powershell(script, environment = {}) {
  return cp.execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', "[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); $ErrorActionPreference='Stop'; " + script], {
    encoding: 'utf8', windowsHide: true, env: { ...process.env, ...environment }, maxBuffer: 4 * 1024 * 1024,
  }).trim();
}

function versionParts(version) {
  if (!/^\d+\.\d+\.\d+\.\d+$/.test(version)) fail('MSIX 版本必须是四段数字。');
  const parts = version.split('.').map(Number);
  if (parts.some(part => !Number.isInteger(part) || part < 0 || part > 65535)) fail('MSIX 版本每段必须为 0 至 65535。');
  return parts;
}

function nextVersion(previous) {
  const baseline = [0, 3, 0, 0], prior = versionParts(previous || '0.3.0.0');
  const comparison = prior.findIndex((part, index) => part !== baseline[index]);
  const parts = comparison !== -1 && prior[comparison] < baseline[comparison] ? baseline : prior;
  for (let index = 3; index >= 0; index--) {
    if (parts[index] < 65535) { parts[index]++; return parts.join('.'); }
    parts[index] = 0;
  }
  fail('MSIX 版本号已耗尽。');
}

function discover(appDir) {
  if (process.platform !== 'win32' || process.arch !== 'x64') fail('当前已验证的构建目标为 Windows x64。');
  const script = String.raw`
if(-not [Environment]::Is64BitProcess){throw '64-bit PowerShell is required'}
$items=@(Get-AppxPackage -Name Claude | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage })
if($env:ZH_UI_APP_DIR){$target=[IO.Path]::GetFullPath($env:ZH_UI_APP_DIR).TrimEnd('\');$items=@($items | Where-Object {[IO.Path]::GetFullPath((Join-Path $_.InstallLocation 'app')).TrimEnd('\') -ieq $target})}
if($items.Count -ne 1){throw 'Expected exactly one current-user official Claude main package; specify --app-dir if needed'}
$p=$items[0]; $manifestPath=Join-Path $p.InstallLocation 'AppxManifest.xml'; [xml]$m=Get-Content -LiteralPath $manifestPath -Raw
$apps=@($m.Package.Applications.Application | Where-Object {[IO.Path]::GetFileName([string]$_.Executable) -ieq 'Claude.exe'})
if($apps.Count -ne 1){throw 'Expected one main Claude.exe application'}
$a=$apps[0]
if([string]$m.Package.Identity.Name -cne [string]$p.Name -or [string]$m.Package.Identity.Publisher -cne [string]$p.Publisher -or [version]$m.Package.Identity.Version -ne [version]$p.Version){throw 'Installed package identity and public manifest disagree'}
$patch=@(Get-AppxPackage -Name '${NAME}' -PackageTypeFilter Optional | Where-Object {$_.Publisher -ceq '${PUBLISHER}'} | Sort-Object Version -Descending)
@{name=[string]$p.Name;publisher=[string]$p.Publisher;version=[string]$p.Version;architecture=([string]$m.Package.Identity.ProcessorArchitecture).ToLowerInvariant();packageFullName=[string]$p.PackageFullName;packageFamilyName=[string]$p.PackageFamilyName;installLocation=[string]$p.InstallLocation;appId=[string]$a.Id;executable=[string]$a.Executable;aumid=([string]$p.PackageFamilyName+'!'+[string]$a.Id);knownProgramFilesX64=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles);installedPatchVersion=$(if($patch.Count){[string]$patch[0].Version}else{$null})} | ConvertTo-Json -Compress
`;
  return JSON.parse(powershell(script, { ZH_UI_APP_DIR: appDir || '' }));
}

function validateIdentity(base) {
  if (base.name !== 'Claude' || base.packageFamilyName !== OFFICIAL_FAMILY || !base.publisher || !base.packageFullName || !base.appId) fail('未发现受支持的官方 Claude 主包身份；不接受同名第三方包。');
  versionParts(base.version);
  if (base.architecture !== 'x64') fail('当前已验证的 VFS 资源映射仅支持 x64 主包。');
  if (!/^[A-Za-z0-9._-]+$/.test(base.packageFullName) || !/^[A-Za-z0-9._-]+$/.test(base.packageFamilyName) || !/^[A-Za-z0-9._-]+$/.test(base.appId)) fail('主包身份包含无效字符。');
  if (base.aumid !== `${base.packageFamilyName}!${base.appId}`) fail('主包 AUMID 不一致。');
  const executable = String(base.executable).replace(/\\/g, '/');
  if (executable !== 'app/Claude.exe' && executable !== 'app/claude.exe') fail('暂不支持主包的新入口布局；未写入原包。');
  const installLocation = core.physicalPath(base.installLocation);
  const programFiles = core.physicalPath(base.knownProgramFilesX64);
  const relativeBase = path.relative(programFiles, installLocation).split(path.sep).join('/');
  // This is the real known-folder mapping proven on the official installed app.
  // It does not create a fake WindowsApps executable path or change identity.
  if (relativeBase.toLowerCase() !== `windowsapps/${base.packageFullName}`.toLowerCase()) fail('主包不在已验证的 ProgramFilesX64/WindowsApps 位置；拒绝猜测其它卷的映射。');
  const appDir = core.physicalPath(path.join(installLocation, 'app'));
  return { ...base, executable, installLocation, appDir, mapping: { knownFolder: 'FOLDERID_ProgramFilesX64', vfsFolder: 'ProgramFilesX64', relativeBase } };
}

function findTools() {
  const kits = path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Windows Kits', '10', 'bin');
  if (!fs.existsSync(kits)) fail('未找到 Windows SDK。请先安装包含 MakeAppx 和 SignTool 的官方 Windows SDK；本工具不会下载程序。');
  const versions = fs.readdirSync(kits).filter(name => /^\d+\.\d+\.\d+\.\d+$/.test(name)).sort((a, b) => {
    const left = versionParts(a), right = versionParts(b);
    for (let i = 0; i < 4; i++) if (left[i] !== right[i]) return right[i] - left[i];
    return 0;
  });
  for (const version of versions) {
    const makeappx = path.join(kits, version, 'x64', 'makeappx.exe'), signtool = path.join(kits, version, 'x64', 'signtool.exe');
    if (fs.existsSync(makeappx) && fs.existsSync(signtool)) return { makeappx: core.physicalPath(makeappx), signtool: core.physicalPath(signtool) };
  }
  fail('Windows SDK 中缺少 x64 MakeAppx.exe 或 SignTool.exe；没有下载任何工具。');
}

function manifest(base, version) {
  return `<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10" xmlns:uap4="http://schemas.microsoft.com/appx/manifest/uap/windows10/4" xmlns:rescap6="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities/6" IgnorableNamespaces="uap4 rescap6">
  <Identity Name="${NAME}" Publisher="${PUBLISHER}" Version="${version}" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>Claude 中文界面资源</DisplayName><PublisherDisplayName>ZhUiHelper Local</PublisherDisplayName>
    <Description>Locally built Chinese UI resources; original application executables and services are preserved.</Description>
    <Logo>candidate-logo.png</Logo><rescap6:ModificationPackage>true</rescap6:ModificationPackage>
  </Properties>
  <Resources><Resource Language="zh-Hans" /></Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0" />
    <uap4:MainPackageDependency Name="${xml(base.name)}" Publisher="${xml(base.publisher)}" />
  </Dependencies>
</Package>
`;
}

function pngLogo() {
  const crc32 = bytes => { let crc = 0xffffffff; for (const byte of bytes) { crc ^= byte; for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0); } return (crc ^ 0xffffffff) >>> 0; };
  const chunk = (type, bytes) => { const name = Buffer.from(type), len = Buffer.alloc(4), crc = Buffer.alloc(4); len.writeUInt32BE(bytes.length); crc.writeUInt32BE(crc32(Buffer.concat([name, bytes]))); return Buffer.concat([len, name, bytes, crc]); };
  const header = Buffer.alloc(13); header.writeUInt32BE(44); header.writeUInt32BE(44, 4); header[8] = 8; header[9] = 6;
  const pixels = Buffer.alloc(44 * (1 + 44 * 4));
  for (let y = 0; y < 44; y++) for (let x = 0; x < 44; x++) pixels.set([52, 92, 108, 255], y * (1 + 44 * 4) + 1 + x * 4);
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(pixels)), chunk('IEND', Buffer.alloc(0))]);
}

function preparePayload(base, resources, version) {
  if (!(resources instanceof Map) || resources.size !== 4 || core.MUTATIONS.some(relative => !resources.has(relative))) fail('必须恰有四个界面资源。');
  const files = new Map();
  for (const [relative, originalBytes] of resources) {
    if (!core.MUTATIONS.includes(relative)) fail('拒绝额外载荷。');
    let bytes = Buffer.from(originalBytes);
    if (relative === 'resources/ion-dist/index.html') {
      const original = bytes.toString('utf8'), old = 'zh-ui-helper:locale-setup:v1';
      if (original.split(old).length !== 2 || original.includes(MARKER)) fail('语言初始化脚本结构改变，停止构建。');
      bytes = Buffer.from(original.replace(old, MARKER));
    }
    files.set(`VFS/${base.mapping.vfsFolder}/${base.mapping.relativeBase}/app/${relative}`, bytes);
  }
  files.set('AppxManifest.xml', Buffer.from(manifest(base, version)));
  files.set('candidate-logo.png', pngLogo());
  return files;
}

function build(options, deps = {}) {
  if (Number(process.versions.node.split('.')[0]) < 20) fail('需要 Node.js 20 或更新版本。');
  if (!options.output) fail('--output 必填；请指定新的本地构建目录。');
  if ((options.packageName && options.packageName !== NAME) || (options.publisher && options.publisher !== PUBLISHER)) fail('草案仅允许本工具专用包名和 Publisher。');
  const base = validateIdentity((deps.discover || discover)(options.appDir));
  if (options.appDir && key(core.physicalPath(options.appDir)) !== key(base.appDir)) fail('--app-dir 必须指向当前已安装 Claude 的真实 app 目录。');
  let output = core.assertDestination(options.output, base.installLocation);
  // Releases are self-contained: locales/ and lib/ live beside this script.
  const runtimeRoot = core.physicalPath(deps.runtimeRoot || __dirname);
  const toolRoot = core.physicalPath(__dirname);
  const protectOutput = target => { if (within(target, runtimeRoot) && key(runtimeRoot) !== key(toolRoot) || within(runtimeRoot, target) || key(target) === key(toolRoot)) fail('输出不得覆盖工具或翻译资源。'); };
  protectOutput(output);
  if (fs.existsSync(output) && fs.readdirSync(output).length) fail('构建目录非空；请使用新目录，保留旧安装审计供恢复。');
  const version = options.packageVersion || nextVersion(base.installedPatchVersion);
  versionParts(version);
  const tools = (deps.findTools || findTools)();
  const snapshot = (deps.validateOriginal || core.validateOriginal)(base.appDir);
  const manifestPath = path.join(base.installLocation, 'AppxManifest.xml');
  const manifestSha256 = fileHash(core.physicalPath(manifestPath));
  const resources = (deps.prepareResources || core.prepareResources)(base.appDir, runtimeRoot);
  const files = preparePayload(base, resources, version);
  fs.mkdirSync(output, { recursive: true });
  // Newly created LocalAppData directories can acquire an MSIX physical alias.
  // All later writes and the returned path use its checked native real path.
  output = core.assertDestination(output, base.installLocation);
  protectOutput(output);
  if (fs.readdirSync(output).length) fail('新建输出目录的实际位置非空；停止，避免覆盖其它文件。');
  const payload = path.join(output, 'payload');
  for (const [relative, bytes] of files) { const target = at(payload, relative); fs.mkdirSync(path.dirname(target), { recursive: true }); fs.writeFileSync(target, bytes); }
  const archive = path.join(output, 'candidate.msix');
  const args = ['pack', '/d', payload, '/p', archive, '/o', '/v'];
  const result = (deps.pack || ((tool, argv) => cp.spawnSync(tool, argv, { encoding: 'utf8', windowsHide: true })))(tools.makeappx, args);
  fs.writeFileSync(path.join(output, 'makeappx-validation.log'), (result.stdout || '') + (result.stderr || '') + (result.error ? '\n' + String(result.error) : ''));
  if (result.status !== 0) fail(`MakeAppx 校验失败（${result.status}），没有签名或安装。`);
  const after = (deps.validateOriginal || core.validateOriginal)(base.appDir);
  if (snapshot.fingerprint !== after.fingerprint || manifestSha256 !== fileHash(manifestPath)) fail('构建期间官方主包发生变化，请换新目录重试；没有安装。');
  const audit = {
    schema: 1, toolId: TOOL, candidateId: crypto.randomUUID(), createdAt: new Date().toISOString(), buildDirectory: output,
    package: { name: NAME, publisher: PUBLISHER, version, architecture: 'x64' },
    base: { ...base, manifestSha256, sourceSnapshot: snapshot }, mapping: base.mapping,
    files: Object.fromEntries([...files].map(([relative, bytes]) => [relative, sha(bytes)])),
    packageSha256: fileHash(archive), tools, coverage: resources.coverage || {},
    localeMarker: MARKER, noOriginalWrites: true,
    sideEffects: { onlyBuildDirectoryWritten: true, certificateCreated: false, certificateTrusted: false, packageSigned: false, packageInstalled: false, shortcutCreated: false, applicationLaunched: false, profileReadOrChanged: false },
    compatibility: { minimumWindows: '10.0.19041.0', architecture: 'x64', baseVersionAllowlist: false, mappingUsesActualInstalledPackageFullName: true, onBaseUpgrade: 'Old resources no longer target the new package path; rebuild to translate the new version.', futureLayoutNotGuaranteed: true },
  };
  fs.writeFileSync(path.join(output, 'build-audit.json'), jsonBytes(audit));
  return { status: 'built-not-signed-or-installed', output, package: audit.package, baseAumid: base.aumid, coverage: audit.coverage, packageSha256: audit.packageSha256 };
}

function parseArgs(args) {
  const options = {}, names = { '--output': 'output', '--app-dir': 'appDir', '--package-name': 'packageName', '--publisher': 'publisher', '--package-version': 'packageVersion' };
  for (let i = 0; i < args.length; i += 2) { const name = names[args[i]]; if (!name || !args[i + 1] || Object.hasOwn(options, name)) fail('参数无效。用法：node build.cjs --output DIR [--app-dir DIR] [--package-version A.B.C.D]'); options[name] = args[i + 1]; }
  return options;
}
if (require.main === module) { try { console.log(JSON.stringify(build(parseArgs(process.argv.slice(2))), null, 2)); } catch (error) { console.error(error.message); process.exitCode = 1; } }
module.exports = { build, parseArgs, nextVersion, manifest, preparePayload, validateIdentity, NAME, PUBLISHER, MARKER };
