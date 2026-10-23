#!/usr/bin/env node
'use strict';

// The installer reads only public app resources; it does not read profiles or credentials.
// The HTML bootstrap uses the app's normal local endpoint to save only the selected locale.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const META = '.zh-ui-helper';
const MUTATIONS = [
  'resources/ion-dist/index.html',
  'resources/zh-Hans.json',
  'resources/ion-dist/i18n/zh-Hans.json',
  'resources/ion-dist/i18n/dynamic/zh-Hans.json',
];
const REQUIRED_SOURCE_FILES = ['claude.exe', 'resources/app.asar', 'resources/en-US.json', 'resources/ion-dist/index.html', 'resources/ion-dist/i18n/en-US.json'];
const OPTIONAL_SOURCE_FILES = ['resources/zh-Hans.json', 'resources/ion-dist/i18n/zh-Hans.json', 'resources/ion-dist/i18n/dynamic/en-US.json', 'resources/ion-dist/i18n/dynamic/zh-Hans.json'];
const SOURCE_FILES = [...REQUIRED_SOURCE_FILES, ...OPTIONAL_SOURCE_FILES];
const HASH_PATTERN = /^[0-9a-f]{64}$/;
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const fileHash = file => sha(fs.readFileSync(file));
const keyPath = file => path.resolve(file).toLowerCase();
const at = (root, relative) => path.join(root, ...relative.split('/'));
const fail = message => { throw new Error(message); };
const within = (file, root) => keyPath(file) === keyPath(root) || keyPath(file).startsWith(keyPath(root) + path.sep);
const jsonBytes = obj => Buffer.from(JSON.stringify(obj, null, 2) + '\n', 'utf8');

function assertNoLinks(file) {
  let current = path.resolve(file);
  while (true) {
    try {
      if (fs.lstatSync(current).isSymbolicLink()) fail(`不支持符号链接或目录联接：${current}`);
    } catch (error) {
      if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') throw error;
    }
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
}

// MSIX filesystem virtualization can expose an ordinary logical path whose native
// realpath is elsewhere. This does not authorize following links: both names and
// all their existing ancestors must pass the no-link check.
function physicalPath(file, realpathNative = fs.realpathSync.native) {
  const logical = path.resolve(file);
  assertNoLinks(logical);
  let existing = logical;
  const tail = [];
  while (!fs.existsSync(existing)) {
    const parent = path.dirname(existing);
    if (parent === existing) fail(`无法解析实际目录：${logical}`);
    tail.unshift(path.basename(existing));
    existing = parent;
  }
  const root = path.resolve(realpathNative(existing), ...tail);
  assertNoLinks(root);
  return root;
}

function assertDestination(destination, source, realpathNative = fs.realpathSync.native) {
  const logical = path.resolve(destination);
  const root = physicalPath(logical, realpathNative);
  for (const candidate of [logical, root]) {
    if (candidate === path.parse(candidate).root || /(?:^|[\\/])windowsapps(?:[\\/]|$)/i.test(candidate)) fail('副本目标不能是磁盘根目录或 WindowsApps 目录。');
    if (source && (within(candidate, source) || within(source, candidate))) fail('原应用与副本目标不得相同或互相嵌套。');
  }
  return root;
}

function loadFlat(file) {
  const value = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  if (!value || Array.isArray(value) || typeof value !== 'object' || Object.values(value).some(v => typeof v !== 'string')) fail(`词库必须是扁平字符串对象：${file}`);
  return value;
}

function optionalChinese(file) {
  if (!fs.existsSync(file)) return {};
  assertNoLinks(file);
  const value = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  if (!value || Array.isArray(value) || typeof value !== 'object') fail(`现有中文词库必须是对象：${file}`);
  return Object.fromEntries(Object.entries(value).filter(([, message]) => typeof message === 'string'));
}

function assertHash(file, expected) {
  assertNoLinks(file);
  if (!fs.existsSync(file) || !fs.statSync(file).isFile() || fileHash(file) !== expected) fail(`文件与支持的原版不符，拒绝继续：${file}`);
}

function catalogMetadata(html) {
  if (!/<head(?:\s[^>]*)?>/i.test(html)) fail('不兼容的本地界面结构：HTML 缺少 head。');
  if (/data-zh-ui-locale\b/.test(html)) fail('源 HTML 已含本工具启动标记，请选择官方原版。');
  const tags = [...html.matchAll(/<meta\b[^>]*>/gi)].map(match => match[0]).filter(tag => /\sname\s*=\s*(?:"i18n-catalogs"|'i18n-catalogs'|i18n-catalogs(?=\s|\/?>))/i.test(tag));
  if (tags.length > 1) fail('不兼容的本地界面结构：多个 i18n-catalogs 元数据。');
  if (!tags.length) return { tag: null, entries: [] };
  const tag = tags[0];
  const cut = tag.match(/\sdata-i18n-cut\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/i);
  if (cut && (cut[1] ?? cut[2] ?? cut[3]) !== '') fail('不兼容的本地界面结构：暂不支持非空 data-i18n-cut 路径。');
  const data = tag.match(/\sdata-i18n-catalogs\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/i);
  if (!data) fail('不兼容的本地界面结构：缺少可识别的 data-i18n-catalogs。');
  const value = data[1] ?? data[2] ?? data[3];
  const entries = value ? value.split(',') : [];
  if (entries.some(entry => !/^([\w-]+):([\w-]+)\.([\w-]+)$/.test(entry))) fail('不兼容的本地界面结构：未知 catalog 元数据格式。');
  return { tag, entries, dataAttribute: data[0] };
}

function detectLoader(root) {
  const ion = at(root, 'resources/ion-dist');
  let catalogs = false;
  let dynamic = false;
  const evidence = {};
  function scan(directory) {
    for (const item of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      const file = path.join(directory, item.name);
      if (item.isSymbolicLink()) fail(`应用目录含链接，拒绝读取：${file}`);
      if (item.isDirectory()) scan(file);
      else if (item.isFile() && /\.m?js$/i.test(item.name)) {
        const bytes = fs.readFileSync(file);
        const code = bytes.toString('utf8');
        const hasCatalogs = code.includes('i18n-catalogs');
        const hasDynamic = code.includes('i18n/dynamic/');
        if (hasCatalogs || hasDynamic) evidence[path.relative(root, file).split(path.sep).join('/')] = sha(bytes);
        catalogs ||= hasCatalogs;
        dynamic ||= hasDynamic;
      }
      if (catalogs && dynamic) return;
    }
  }
  scan(ion);
  if (!catalogs || !dynamic) fail('不兼容的本地界面结构：未找到 i18n-catalogs / i18n/dynamic 扩展点。');
  return evidence;
}

function snapshotFingerprint(files) {
  return sha(Buffer.from(JSON.stringify(Object.fromEntries(Object.entries(files).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)))));
}

function detectVersion(root) {
  if (process.platform !== 'win32') return null;
  try {
    const script = "[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); [Diagnostics.FileVersionInfo]::GetVersionInfo($env:ZH_UI_SOURCE_EXE).ProductVersion";
    const version = cp.execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { encoding: 'utf8', windowsHide: true, env: { ...process.env, ZH_UI_SOURCE_EXE: path.join(root, 'claude.exe') } }).trim();
    return /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/.test(version) ? version : null;
  } catch { return null; }
}

function localScriptEntries(html, root) {
  const ion = at(root, 'resources/ion-dist');
  const files = {};
  for (const match of html.matchAll(/<script\b[^>]*>/gi)) {
    const attribute = match[0].match(/\ssrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/i);
    const src = attribute && (attribute[1] ?? attribute[2] ?? attribute[3]).trim();
    if (!src || src.includes('\\')) continue;
    let filename;
    try {
      const url = new URL(src, 'app://localhost/');
      if (url.protocol !== 'app:' || url.hostname !== 'localhost' || url.username || url.password || url.port) continue;
      const pathname = decodeURIComponent(url.pathname);
      if (pathname.includes('\0') || !/\.m?js$/i.test(pathname)) continue;
      filename = path.resolve(ion, '.' + pathname);
    } catch { continue; }
    if (!within(filename, ion)) continue;
    assertNoLinks(filename);
    if (fs.existsSync(filename) && fs.statSync(filename).isFile() && fs.statSync(filename).size) files[path.relative(root, filename).split(path.sep).join('/')] = fileHash(filename);
  }
  return files;
}

function validateOriginal(root, build) {
  assertNoLinks(root);
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) fail(`找不到应用目录：${root}`);
  if (fs.existsSync(path.join(root, META))) fail('源目录是本工具制作的副本，请选择官方原版。');
  const files = {};
  for (const relative of SOURCE_FILES) {
    const file = at(root, relative);
    assertNoLinks(file);
    if (!fs.existsSync(file)) {
      if (REQUIRED_SOURCE_FILES.includes(relative)) fail(`不兼容的本地界面结构：缺少 ${relative}`);
      files[relative] = null;
    } else {
      if (!fs.statSync(file).isFile() || !fs.statSync(file).size) fail(`本地资源不是有效文件：${relative}`);
      files[relative] = fileHash(file);
    }
  }
  loadFlat(at(root, 'resources/en-US.json'));
  loadFlat(at(root, 'resources/ion-dist/i18n/en-US.json'));
  if (files['resources/ion-dist/i18n/dynamic/en-US.json']) loadFlat(at(root, 'resources/ion-dist/i18n/dynamic/en-US.json'));
  const html = fs.readFileSync(at(root, MUTATIONS[0]), 'utf8');
  catalogMetadata(html);
  const entryFiles = localScriptEntries(html, root);
  if (!Object.keys(entryFiles).length) fail('不兼容的本地界面结构：缺少可用的本地外部 JavaScript 入口脚本。');
  Object.assign(files, entryFiles);
  Object.assign(files, detectLoader(root));
  const fingerprint = snapshotFingerprint(files);
  const version = build?.version || detectVersion(root) || `build-${fingerprint.slice(0, 12)}`;
  return { version, files, fingerprint };
}

function makeHtml(original, baseBytes, dynamicBytes) {
  let html = original.toString('utf8');
  const metadata = catalogMetadata(html);
  const token = `zh-Hans:${sha(baseBytes).slice(0, 16)}.${sha(dynamicBytes).slice(0, 16)}`;
  const bootstrap = '(()=>{try{if(location.protocol!=="app:"||location.hostname!=="localhost")return;const k="zh-ui-helper:locale-setup:v1";if(localStorage.getItem(k)==="done")return;const s=()=>{localStorage.setItem("spa:locale","zh-Hans");localStorage.setItem("spa:locale-source","user_choice");document.documentElement.lang="zh-Hans"};s();return fetch("/api/account_profile",{method:"PUT",credentials:"same-origin",headers:{"Content-Type":"application/json"},body:JSON.stringify({locale:"zh-Hans"})}).then(r=>{if(!r.ok)throw Error("locale setup failed");return r.json()}).then(p=>{if(!p||p.locale!=="zh-Hans")throw Error("locale not confirmed");s();localStorage.setItem(k,"done");location.reload()}).catch(()=>{try{s()}catch{}})}catch{}})();';
  const entries = metadata.entries.filter(entry => !/^zh-hans:/i.test(entry));
  entries.push(token);
  let tag = `<meta name="i18n-catalogs" data-i18n-catalogs="${entries.join(',')}">`;
  if (metadata.tag) {
    tag = metadata.tag.replace(metadata.dataAttribute, ` data-i18n-catalogs="${entries.join(',')}"`);
    html = html.replace(metadata.tag, '');
  }
  const addition = `\n${tag}\n<script data-zh-ui-locale>${bootstrap}</script>\n`;
  return Buffer.from(html.replace(/<head(?:\s[^>]*)?>/i, match => match + addition));
}

function prepareResources(source, packageRoot) {
  const base = loadFlat(path.join(packageRoot, 'locales', 'frontend-zh-Hans.json'));
  const dynamic = loadFlat(path.join(packageRoot, 'locales', 'dynamic-zh-Hans.json'));
  const additions = loadFlat(path.join(packageRoot, 'locales', 'native-additions-zh-Hans.json'));
  const fingerprints = JSON.parse(fs.readFileSync(path.join(packageRoot, 'locales', 'source-fingerprints.json'), 'utf8').replace(/^\uFEFF/, ''));
  if (fingerprints.schema !== 1 || fingerprints.algorithm !== 'sha256' || !fingerprints.catalogs || ['frontend', 'dynamic', 'native'].some(name => !fingerprints.catalogs[name] || typeof fingerprints.catalogs[name] !== 'object' || Array.isArray(fingerprints.catalogs[name]) || Object.values(fingerprints.catalogs[name]).some(value => typeof value !== 'string' || !HASH_PATTERN.test(value)))) fail('源文案指纹文件无效。');
  const nativeEnglish = loadFlat(at(source, 'resources/en-US.json'));
  const dynamicEnglishFile = at(source, 'resources/ion-dist/i18n/dynamic/en-US.json');
  const coverage = {};
  function merge(name, english, patch, existing) {
    const stats = { total: 0, existing: 0, translated: 0, fallback: 0 };
    const output = Object.fromEntries(Object.entries(english).map(([key, message]) => {
      stats.total++;
      if (Object.hasOwn(existing, key)) { stats.existing++; return [key, existing[key]]; }
      if (Object.hasOwn(patch, key) && fingerprints.catalogs[name][key] === sha(Buffer.from(message, 'utf8'))) { stats.translated++; return [key, patch[key]]; }
      stats.fallback++;
      return [key, message];
    }));
    coverage[name] = stats;
    return output;
  }
  const mergedBase = merge('frontend', loadFlat(at(source, 'resources/ion-dist/i18n/en-US.json')), base, optionalChinese(at(source, MUTATIONS[2])));
  const mergedDynamic = merge('dynamic', fs.existsSync(dynamicEnglishFile) ? loadFlat(dynamicEnglishFile) : {}, dynamic, optionalChinese(at(source, MUTATIONS[3])));
  const mergedNative = merge('native', nativeEnglish, additions, optionalChinese(at(source, MUTATIONS[1])));
  const baseBytes = jsonBytes(mergedBase);
  const dynamicBytes = jsonBytes(mergedDynamic);
  const resources = new Map([
    [MUTATIONS[0], makeHtml(fs.readFileSync(at(source, MUTATIONS[0])), baseBytes, dynamicBytes)],
    [MUTATIONS[1], jsonBytes(mergedNative)],
    [MUTATIONS[2], baseBytes],
    [MUTATIONS[3], dynamicBytes],
  ]);
  resources.coverage = coverage;
  return resources;
}

// Resource preparation only. No installation, copying, shortcut or restore entry point.
module.exports = { prepareResources, validateOriginal, physicalPath, assertDestination, makeHtml, snapshotFingerprint, fileHash, MUTATIONS };
