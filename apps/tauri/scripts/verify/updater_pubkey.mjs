#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

function fail(message) {
  console.error(`[verify:updater-pubkey] ${message}`);
  process.exit(1);
}

function assert(condition, message) {
  if (!condition) {
    fail(message);
  }
}

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..', '..');
const tauriConfigPath = path.join(repoRoot, 'app', 'src-tauri', 'tauri.conf.json');

const tauriConfig = JSON.parse(fs.readFileSync(tauriConfigPath, 'utf8'));
const pubkey = tauriConfig?.plugins?.updater?.pubkey;

assert(typeof pubkey === 'string', 'plugins.updater.pubkey must be a string');
const trimmed = pubkey.trim();
assert(trimmed.length > 0, 'plugins.updater.pubkey must not be empty');
assert(!/replace|todo|changeme/i.test(trimmed), 'plugins.updater.pubkey must not be a placeholder value');
assert(/^[A-Za-z0-9+/=]+$/.test(trimmed), 'plugins.updater.pubkey must be base64-like');

let decoded = '';
try {
  decoded = Buffer.from(trimmed, 'base64').toString('utf8');
} catch {
  fail('plugins.updater.pubkey is not valid base64');
}
assert(
  decoded.includes('untrusted comment: minisign public key'),
  'plugins.updater.pubkey must decode to a minisign public key payload',
);

console.log('[verify:updater-pubkey] updater pubkey checks passed.');
