// Contract test: `app/src/lib/preferences/keys.ts` must stay in lockstep with
// `lorvex-domain/src/preference_keys.rs`. Any key present on one side but
// missing on the other silently bypasses the registry when read/written via
// the generic preferences IPC — a drift that causes no-op settings, silent
// onboarding regressions, and broken feature gates.
//
// The only permitted exception is `PREF_FOCUS_BREAK_MINUTES`, which is a
// TS-only preference owned entirely by the focus-mode frontend (Rust never
// reads it). Any new one-sided key should be documented with a matching
// allowlist entry below.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

// Keys that intentionally live on only one side. Keep empty unless there is
// a product reason the other side cannot own the constant.
const TS_ONLY_ALLOWLIST = new Set(['focus_break_minutes']);
const RUST_ONLY_ALLOWLIST = new Set();

function parseRustKeys(source) {
  const keys = new Map();
  const pattern =
    /pub const (PREF_[A-Z0-9_]+|DEV_[A-Z0-9_]+): &str = "([^"]+)";/g;
  let match;
  while ((match = pattern.exec(source)) !== null) {
    keys.set(match[1], match[2]);
  }
  return keys;
}

function parseTsKeys(source) {
  const keys = new Map();
  const pattern =
    /export const (PREF_[A-Z0-9_]+|DEV_[A-Z0-9_]+)\s*=\s*'([^']+)';/g;
  let match;
  while ((match = pattern.exec(source)) !== null) {
    keys.set(match[1], match[2]);
  }
  return keys;
}

function parseRustPreferenceAllowlistNames(source) {
  const allowlist = source.match(/pub const ALL_KNOWN_PREFERENCE_KEYS:\s*&\[&str\]\s*=\s*&\[([\s\S]+?)\];/);
  assert.ok(allowlist, 'Rust preference allowlist should be parseable');
  return new Set(
    Array.from(allowlist[1].matchAll(/\b(PREF_[A-Z0-9_]+)\b/g), (match) => match[1]),
  );
}

function loadKeyRegistries() {
  const rustSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-domain/src/preference_keys/mod.rs'),
    'utf8',
  );
  const tsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/preferences/keys.ts'),
    'utf8',
  );
  return {
    rust: parseRustKeys(rustSource),
    ts: parseTsKeys(tsSource),
  };
}

function parseRustCalendarAiAccessModeValues() {
  const source = fs.readFileSync(
    path.join(repoRoot, 'lorvex-domain/src/naming/calendar.rs'),
    'utf8',
  );
  const parseStrict = source.match(/pub fn parse_strict[\s\S]+?match s\.trim\(\) \{([\s\S]+?)\n        \}/);
  assert.ok(parseStrict, 'CalendarAiAccessMode::parse_strict match body should be parseable');
  const values = [];
  const pattern = /"([^"]+)"\s*=>\s*Some\(Self::[A-Za-z]+\)/g;
  let match;
  while ((match = pattern.exec(parseStrict[1])) !== null) {
    values.push(match[1]);
  }
  return values.sort();
}

function parseTsCalendarAiAccessModeUnion() {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/preferences/values.ts'),
    'utf8',
  );
  const union = source.match(/\[DEV_CALENDAR_AI_ACCESS_MODE\]:\s*([^;]+);/);
  assert.ok(union, 'DeviceStateValueShape should declare DEV_CALENDAR_AI_ACCESS_MODE');
  return Array.from(union[1].matchAll(/'([^']+)'/g), (match) => match[1]).sort();
}

test('preferenceKeys.ts contains every PREF_*/DEV_* constant from lorvex-domain', () => {
  const { rust, ts } = loadKeyRegistries();
  assert.ok(rust.size > 0, 'Rust preference registry should be non-empty');
  assert.ok(ts.size > 0, 'TS preference registry should be non-empty');

  const missing = [];
  for (const [name, value] of rust) {
    const tsValue = ts.get(name);
    if (tsValue === undefined) {
      if (RUST_ONLY_ALLOWLIST.has(value)) continue;
      missing.push(`${name} = '${value}'`);
      continue;
    }
    assert.equal(
      tsValue,
      value,
      `preferenceKeys.ts ${name} (${tsValue}) must match Rust (${value})`,
    );
  }
  assert.deepEqual(
    missing,
    [],
    `preferenceKeys.ts is missing ${missing.length} Rust-side constants: ${missing.join(', ')}`,
  );
});

test('lorvex-domain preference allowlist references every Rust PREF_* constant', () => {
  const rustSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-domain/src/preference_keys/mod.rs'),
    'utf8',
  );
  const rust = parseRustKeys(rustSource);
  const allowlistNames = parseRustPreferenceAllowlistNames(rustSource);

  assert.ok(allowlistNames.size > 0, 'Rust preference allowlist should be non-empty');
  const missing = [];
  for (const [name, value] of rust) {
    if (!name.startsWith('PREF_')) continue;
    if (!allowlistNames.has(name)) {
      missing.push(`${name} = '${value}'`);
    }
  }

  assert.deepEqual(
    missing,
    [],
    `ALL_KNOWN_PREFERENCE_KEYS is missing ${missing.length} Rust-side PREF_* constants: ${missing.join(', ')}`,
  );
});

test('preferenceKeys.ts does not export any constant absent from lorvex-domain', () => {
  const { rust, ts } = loadKeyRegistries();

  const extras = [];
  for (const [name, value] of ts) {
    if (rust.has(name)) continue;
    if (TS_ONLY_ALLOWLIST.has(value)) continue;
    extras.push(`${name} = '${value}'`);
  }
  assert.deepEqual(
    extras,
    [],
    `preferenceKeys.ts exports ${extras.length} constants with no Rust counterpart: ${extras.join(', ')}. Add them to lorvex-domain/src/preference_keys.rs or to TS_ONLY_ALLOWLIST with a justification.`,
  );
});

test('preferenceKeys.ts string values are unique (no accidental collisions)', () => {
  const { ts } = loadKeyRegistries();
  const seen = new Map();
  for (const [name, value] of ts) {
    const previous = seen.get(value);
    if (previous !== undefined) {
      assert.fail(
        `preferenceKeys.ts exports both ${previous} and ${name} with the same string value '${value}'`,
      );
    }
    seen.set(value, name);
  }
});

test('lorvex-domain preference_keys.rs string values are unique', () => {
  const { rust } = loadKeyRegistries();
  const seen = new Map();
  for (const [name, value] of rust) {
    const previous = seen.get(value);
    if (previous !== undefined) {
      assert.fail(
        `preference_keys.rs defines both ${previous} and ${name} with the same string value '${value}'`,
      );
    }
    seen.set(value, name);
  }
});

test('calendar_ai_access_mode TypeScript union matches Rust canonical values', () => {
  assert.deepEqual(
    parseTsCalendarAiAccessModeUnion(),
    parseRustCalendarAiAccessModeValues(),
  );
});
