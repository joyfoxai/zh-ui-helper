'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const draft = require('../build.cjs');
const core = require('../lib/catalogs.cjs');
const sha = value => crypto.createHash('sha256').update(value).digest('hex');

function fixture(t) {
  const root = fs.mkdtempSync(path.join(__dirname, '.build-fixture-'));
  t.after(() => { const resolved = path.resolve(root); assert.ok(resolved.startsWith(path.resolve(__dirname) + path.sep)); fs.rmSync(resolved, { recursive: true, force: true }); });
  const known = path.join(root, 'Program Files'), name = 'Claude_9.123.4.0_x64__pzs8sxrjxfjjc';
  const install = path.join(known, 'WindowsApps', name), app = path.join(install, 'app');
  fs.mkdirSync(app, { recursive: true });
  fs.writeFileSync(path.join(install, 'AppxManifest.xml'), '<Package fixture="official public metadata"/>');
  fs.writeFileSync(path.join(app, 'public-source'), 'current source');
  const base = { name: 'Claude', publisher: 'CN="Anthropic, PBC", O=Public & Co', version: '9.123.4.0', architecture: 'x64', packageFullName: name, packageFamilyName: 'Claude_pzs8sxrjxfjjc', appId: 'Claude', aumid: 'Claude_pzs8sxrjxfjjc!Claude', installLocation: install, knownProgramFilesX64: known, executable: 'app\\Claude.exe', installedPatchVersion: '0.3.0.8' };
  const resources = new Map(core.MUTATIONS.map(relative => [relative, Buffer.from(relative.endsWith('index.html') ? '<head><script>const k="zh-ui-helper:locale-setup:v1"</script></head>' : '{"id":"中文"}') ]));
  resources.coverage = { frontend: { total: 1, translated: 1, existing: 0, fallback: 0 } };
  const deps = { discover: () => base, findTools: () => ({ makeappx: 'fixture-sdk-makeappx', signtool: 'fixture-sdk-signtool' }), validateOriginal: () => ({ files: { 'public-source': sha(fs.readFileSync(path.join(app, 'public-source'))) }, fingerprint: sha(fs.readFileSync(path.join(app, 'public-source'))), version: '9.123.4' }), prepareResources: () => resources, pack: (tool, args) => { assert.equal(tool, 'fixture-sdk-makeappx'); assert.equal(args.includes('/nv'), false); fs.writeFileSync(args[4], 'fixture-packaged-container'); return { status: 0, stdout: 'fixture packaging validation passed' }; } };
  return { root, known, install, app, base, resources, deps, output: path.join(root, 'build') };
}

test('actual current package path becomes KnownFolder VFS suffix with no version allowlist', t => {
  const f = fixture(t), base = draft.validateIdentity(f.base);
  assert.equal(base.mapping.relativeBase, 'WindowsApps/Claude_9.123.4.0_x64__pzs8sxrjxfjjc');
  assert.equal(base.appDir, f.app);
  assert.throws(() => draft.validateIdentity({ ...f.base, installLocation: f.root }), /ProgramFilesX64/);
  assert.throws(() => draft.validateIdentity({ ...f.base, aumid: 'Another!App' }), /AUMID/);
  assert.throws(() => draft.validateIdentity({ ...f.base, packageFamilyName: 'Claude_foreign', aumid: 'Claude_foreign!Claude' }), /官方/);
});

test('payload has exactly four resources, XML and self-made PNG; only locale marker changes in HTML', t => {
  const f = fixture(t), base = draft.validateIdentity(f.base), payload = draft.preparePayload(base, f.resources, '0.2.0.9');
  assert.equal(payload.size, 6);
  for (const relative of core.MUTATIONS) {
    const target = `VFS/ProgramFilesX64/${base.mapping.relativeBase}/app/${relative}`;
    assert.ok(payload.has(target));
    if (!relative.endsWith('index.html')) assert.deepEqual(payload.get(target), f.resources.get(relative));
    else assert.equal(payload.get(target).toString(), f.resources.get(relative).toString().replace('zh-ui-helper:locale-setup:v1', draft.MARKER));
  }
  assert.deepEqual([...payload.keys()].filter(name => /\.(?:exe|dll|asar|node|sys)$/i.test(name)), []);
  assert.ok(payload.get('candidate-logo.png').subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])));
  assert.throws(() => draft.preparePayload(base, new Map([...f.resources, ['resources/evil.exe', Buffer.from('no')]]), '0.2.0.9'), /四个/);
});

test('manifest binds actual publisher safely and declares no application, service or capability', t => {
  const f = fixture(t), manifest = draft.manifest(f.base, '0.2.0.9');
  assert.match(manifest, /Publisher="CN=&quot;Anthropic, PBC&quot;, O=Public &amp; Co"/);
  assert.match(manifest, /MainPackageDependency Name="Claude"/);
  assert.match(manifest, /<rescap6:ModificationPackage>true/);
  assert.doesNotMatch(manifest, /<Applications|<Capabilities|windows\.service|OID\.2\.25/);
});

test('build records source and payload hashes without changing or copying source executables', t => {
  const f = fixture(t), before = fs.readFileSync(path.join(f.app, 'public-source'));
  const result = draft.build({ output: f.output }, f.deps), audit = JSON.parse(fs.readFileSync(path.join(f.output, 'build-audit.json')));
  assert.equal(result.status, 'built-not-signed-or-installed');
  assert.equal(audit.package.version, '0.3.0.9');
  assert.equal(audit.toolId, 'zh-ui-helper-msix');
  assert.equal(Object.keys(audit.files).length, 6);
  assert.equal(audit.base.manifestSha256, sha(fs.readFileSync(path.join(f.install, 'AppxManifest.xml'))));
  assert.equal(audit.base.sourceSnapshot.fingerprint, sha(before));
  assert.equal(audit.sideEffects.packageInstalled, false);
  assert.deepEqual(fs.readFileSync(path.join(f.app, 'public-source')), before);
  assert.equal(fs.existsSync(path.join(f.output, 'lifecycle-audit.json')), false);
  assert.throws(() => draft.build({ output: f.output }, f.deps), /非空/);
});

test('no SDK, changed source and failing packaging never produce an installable audit', t => {
  const f = fixture(t);
  assert.throws(() => draft.build({ output: f.output }, { ...f.deps, findTools() { throw Error('SDK unavailable'); } }), /SDK unavailable/);
  assert.equal(fs.existsSync(f.output), false);
  const changed = { ...f.deps, pack(tool,args) { fs.writeFileSync(args[4], 'candidate'); fs.writeFileSync(path.join(f.app, 'public-source'), 'updated during build'); return { status: 0 }; } };
  assert.throws(() => draft.build({ output: f.output }, changed), /构建期间/);
  assert.equal(fs.existsSync(path.join(f.output, 'build-audit.json')), false);
  const failed = path.join(f.root, 'failed');
  assert.throws(() => draft.build({ output: failed }, { ...f.deps, pack() { return { status: 17, stderr: 'schema rejected' }; } }), /MakeAppx.*17/);
  assert.equal(fs.existsSync(path.join(failed, 'build-audit.json')), false);
});

test('output protection refuses WindowsApps, source ancestry, foreign identity and unsafe arguments', t => {
  const f = fixture(t);
  assert.throws(() => draft.build({ output: path.join(f.install, 'output') }, f.deps), /WindowsApps/);
  assert.throws(() => draft.build({ output: f.known }, f.deps), /嵌套/);
  assert.throws(() => draft.build({ output: f.output, publisher: 'CN=Another' }, f.deps), /专用/);
  assert.throws(() => draft.parseArgs(['--output', f.output, '--output', f.output]), /参数无效/);
  assert.equal(draft.nextVersion('0.2.0.65535'), '0.3.0.1');
  assert.equal(draft.nextVersion('0.3.0.65535'), '0.3.1.0');
  assert.throws(() => draft.nextVersion('0.2.0.999999'), /65535/);
});
