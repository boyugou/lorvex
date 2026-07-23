#!/usr/bin/env node

// Audit #2988-L1: verify that platform-specific Tauri config overrides
// (`tauri.windows.conf.json`, `tauri.linux.conf.json`,
// `tauri.android.conf.json`) never re-declare
// `app.security` — and in particular `app.security.csp`. Tauri's
// platform overlay merges its `security` block by replacement, not by
// per-key merge, so a stray `"security": {}` in a platform file would
// silently drop the desktop CSP and re-open every directive
// (`script-src`, `style-src`, `connect-src`, ...) we tightened in the
// base config. The audit closure for SEC-L1 was "verify CSP
// inheritance"; this script makes that verification a hard CI gate
// instead of a reviewer's eyeball check.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_TAG = '[verify:platform-csp-inheritance]';

function resolveRepoRoot() {
  const scriptPath = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(scriptPath), '..', '..');
}

function fail(message) {
  throw new Error(`${SCRIPT_TAG} ${message}`);
}

function assert(condition, message) {
  if (!condition) {
    fail(message);
  }
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

export function verifyPlatformCspInheritance({ repoRoot = resolveRepoRoot() } = {}) {
  const tauriDir = path.join(repoRoot, 'app', 'src-tauri');
  const baseConfigPath = path.join(tauriDir, 'tauri.conf.json');
  assert(fs.existsSync(baseConfigPath), 'missing app/src-tauri/tauri.conf.json');

  const baseConfig = readJson(baseConfigPath);
  const baseCsp = baseConfig?.app?.security?.csp;
  assert(typeof baseCsp === 'string' && baseCsp.length > 0,
    'base tauri.conf.json must declare app.security.csp');
  // Spot-check a handful of directives the desktop CSP relies on so a
  // future "unsafe-eval" / "*" relaxation cannot pass review unnoticed.
  assert(/default-src\s+'self'/.test(baseCsp),
    "base CSP must keep default-src 'self'");
  assert(/script-src\s+'self'/.test(baseCsp),
    "base CSP must keep script-src 'self'");
  assert(!/script-src[^;]*'unsafe-eval'/.test(baseCsp),
    "base CSP must not relax script-src to 'unsafe-eval'");
  assert(!/script-src[^;]*\bhttps?:\b/.test(baseCsp),
    'base CSP must not allow remote http(s): script sources');
  // Audit #3005 L9: defense-in-depth directives that the WebView's CSP
  // engine honours but Tauri's webview process does not synthesize a
  // default for. `frame-ancestors 'none'` blocks any embedding into
  // an `<iframe>` should a future bug expose the bundle to a hostile
  // surface; `base-uri 'self'` defeats `<base href="…">` injection
  // tricks that would otherwise reanchor relative URLs to an
  // attacker-controlled origin; `form-action 'none'` neutralises any
  // accidentally-introduced HTML form's POST destination, since the
  // app talks exclusively over IPC and no surface should ever submit
  // a form. All three are no-cost in legitimate operation and trip
  // the moment a regression introduces the underlying primitive.
  assert(/frame-ancestors\s+'none'/.test(baseCsp),
    "base CSP must declare frame-ancestors 'none' (audit #3005 L9)");
  assert(/base-uri\s+'self'/.test(baseCsp),
    "base CSP must declare base-uri 'self' (audit #3005 L9)");
  assert(/form-action\s+'none'/.test(baseCsp),
    "base CSP must declare form-action 'none' (audit #3005 L9)");

  const platformOverrides = [
    'tauri.windows.conf.json',
    'tauri.linux.conf.json',
    'tauri.android.conf.json',
  ];

  for (const fileName of platformOverrides) {
    const fullPath = path.join(tauriDir, fileName);
    if (!fs.existsSync(fullPath)) continue;
    const overlay = readJson(fullPath);

    // For per-OS desktop/mobile overlays, the security block must be
    // absent entirely — Tauri's overlay merge replaces, not deep-merges,
    // so any partial security block silently drops the base CSP. The
    // overlay should only carry window chrome / icon / bundle deltas.
    const security = overlay?.app?.security;
    assert(security === undefined,
      `${fileName} must not declare app.security (would shadow the base CSP); `
        + 'put platform-specific window/bundle deltas instead');
  }

  return { ok: true };
}

function runCli() {
  try {
    verifyPlatformCspInheritance();
    console.log(`${SCRIPT_TAG} Platform CSP inheritance checks passed.`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.startsWith(SCRIPT_TAG) ? message : `${SCRIPT_TAG} ${message}`);
    process.exit(1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli();
}
