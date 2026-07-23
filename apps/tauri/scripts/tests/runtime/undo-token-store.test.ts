import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test, { beforeEach } from 'node:test';

import {
  clearUndoTokens,
  consumeUndoToken,
  listRecentUndoTokens,
  makeRecentUndoToken,
  recordUndoToken,
  UNDO_TOKEN_HOLD_MS,
  __TEST_ONLY__,
} from '../../../app/src/lib/undoTokenStore';
import { createBrowserUndoTokenStorageHost } from '../../../app/src/lib/undoTokenStore.runtime';

// Issue #2534 — pin the persistent undo-token store that bridges
// the 5s backend hold across reload / navigation / Focus Mode. The
// backend keeps each token redeemable for 5s after it is issued,
// but previously the token only lived inside the toast `onClick`
// closure. These tests verify the localStorage-backed store:
//
//  - writes survive across calls (`recordUndoToken_persists_to_storage`)
//  - reads prune expired entries so stale tokens never reach the UI
//  - `consumeUndoToken` removes by token after successful redemption
//  - `listRecentUndoTokens` hides expired entries from callers

// Minimal in-memory Storage shim. Node's test runtime has no
// localStorage by default.
class InMemoryStorage {
  private store = new Map<string, string>();
  get length(): number {
    return this.store.size;
  }
  clear(): void {
    this.store.clear();
  }
  getItem(key: string): string | null {
    return this.store.has(key) ? (this.store.get(key) as string) : null;
  }
  setItem(key: string, value: string): void {
    this.store.set(key, value);
  }
  removeItem(key: string): void {
    this.store.delete(key);
  }
  key(index: number): string | null {
    return Array.from(this.store.keys())[index] ?? null;
  }
}

(globalThis as unknown as { localStorage: InMemoryStorage }).localStorage = new InMemoryStorage();

beforeEach(() => {
  clearUndoTokens();
});

test('recordUndoToken_persists_to_storage', () => {
  const issuedAt = 1_700_000_000_000;
  recordUndoToken({
    token: 'tok-a',
    label: 'Completed 3 tasks',
    action: 'complete_batch',
    issuedAt,
    expiresAt: issuedAt + UNDO_TOKEN_HOLD_MS,
  });

  // Read the raw blob directly — the store must round-trip through
  // JSON.stringify, not live in memory-only state.
  const raw = (globalThis as unknown as { localStorage: Storage }).localStorage.getItem(__TEST_ONLY__.STORAGE_KEY);
  assert.ok(raw, 'expected localStorage to contain the serialized entries');
  const parsed = JSON.parse(raw as string);
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].token, 'tok-a');
  assert.equal(parsed[0].action, 'complete_batch');
  assert.equal(parsed[0].issuedAt, issuedAt);
  assert.equal(parsed[0].expiresAt, issuedAt + UNDO_TOKEN_HOLD_MS);
});

test('listRecentUndoTokens_prunes_expired', () => {
  const now = 1_700_000_010_000;
  // Stuff the storage with one live and one stale entry using a
  // fixed "now" so the test is deterministic regardless of wall
  // clock.
  recordUndoToken(makeRecentUndoToken('live', 'Completed 1 task', 'complete', now));
  recordUndoToken(makeRecentUndoToken('stale', 'Cancelled 1 task', 'cancel', now - UNDO_TOKEN_HOLD_MS - 1_000));

  const live = listRecentUndoTokens(now);
  assert.equal(live.length, 1);
  assert.equal(live[0]?.token, 'live');

  // The prune side-effect must also hit storage so the stale row
  // does not leak across future reads that pass a different `now`.
  const raw = (globalThis as unknown as { localStorage: Storage }).localStorage.getItem(__TEST_ONLY__.STORAGE_KEY);
  const parsed = JSON.parse(raw as string);
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].token, 'live');
});

test('consumeUndoToken_removes_by_token', () => {
  const now = 1_700_000_020_000;
  recordUndoToken(makeRecentUndoToken('keep-a', 'Completed task A', 'complete', now));
  recordUndoToken(makeRecentUndoToken('drop-b', 'Completed task B', 'complete', now));
  recordUndoToken(makeRecentUndoToken('keep-c', 'Cancelled task C', 'cancel', now));

  consumeUndoToken('drop-b');

  const remaining = listRecentUndoTokens(now).map((entry) => entry.token).sort();
  assert.deepEqual(remaining, ['keep-a', 'keep-c']);
});

test('list_returns_only_non_expired_tokens', () => {
  const now = 1_700_000_030_000;
  const far_past = now - UNDO_TOKEN_HOLD_MS - 10_000;
  const boundary = now - UNDO_TOKEN_HOLD_MS; // exactly at the cap
  const live = now - 1_000;

  recordUndoToken(makeRecentUndoToken('expired-old', 'X', 'complete', far_past));
  recordUndoToken(makeRecentUndoToken('expired-edge', 'Y', 'complete', boundary));
  recordUndoToken(makeRecentUndoToken('fresh', 'Z', 'complete', live));

  const tokens = listRecentUndoTokens(now).map((entry) => entry.token);
  // Only the live token survives; the two with expiresAt <= now are
  // gone. The boundary case is explicitly excluded (expiresAt strictly
  // greater than now is the contract — at `expiresAt === now` the
  // backend hold is already spent).
  assert.deepEqual(tokens, ['fresh']);
});

test('recordUndoToken_dedupes_by_token', () => {
  // A caller that retries the same write should not produce duplicate
  // palette entries for the same backend token.
  const now = 1_700_000_040_000;
  recordUndoToken(makeRecentUndoToken('tok-1', 'First label', 'complete', now));
  recordUndoToken(makeRecentUndoToken('tok-1', 'Second label', 'complete', now + 100));

  const entries = listRecentUndoTokens(now + 100);
  assert.equal(entries.length, 1);
  assert.equal(entries[0]?.label, 'Second label');
});

test('listRecentUndoTokens_sorts_most_recent_first', () => {
  const now = 1_700_000_050_000;
  recordUndoToken(makeRecentUndoToken('older', 'older', 'complete', now - 2_000));
  recordUndoToken(makeRecentUndoToken('newer', 'newer', 'complete', now - 500));
  recordUndoToken(makeRecentUndoToken('newest', 'newest', 'complete', now));

  const tokens = listRecentUndoTokens(now).map((entry) => entry.token);
  assert.deepEqual(tokens, ['newest', 'newer', 'older']);
});

test('listRecentUndoTokens_rejects_partially_malformed_persisted_arrays', () => {
  const now = 1_700_000_060_000;
  const storage = (globalThis as unknown as { localStorage: Storage }).localStorage;
  storage.setItem(
    __TEST_ONLY__.STORAGE_KEY,
    JSON.stringify([
      makeRecentUndoToken('valid', 'Valid entry', 'complete', now),
      { token: '', label: 'Malformed entry', action: 'complete', issuedAt: now, expiresAt: now + UNDO_TOKEN_HOLD_MS },
    ]),
  );

  assert.deepEqual(listRecentUndoTokens(now), []);
});

test('listRecentUndoTokens_rejects_unknown_persisted_actions', () => {
  const now = 1_700_000_070_000;
  const storage = (globalThis as unknown as { localStorage: Storage }).localStorage;
  storage.setItem(
    __TEST_ONLY__.STORAGE_KEY,
    JSON.stringify([
      { ...makeRecentUndoToken('valid', 'Valid entry', 'complete', now), action: 'archive' },
    ]),
  );

  assert.deepEqual(listRecentUndoTokens(now), []);
});

test('listRecentUndoTokens_rejects_entries_with_unknown_fields', () => {
  const now = 1_700_000_080_000;
  const storage = (globalThis as unknown as { localStorage: Storage }).localStorage;
  storage.setItem(
    __TEST_ONLY__.STORAGE_KEY,
    JSON.stringify([
      { ...makeRecentUndoToken('valid', 'Valid entry', 'complete', now), source: 'toast' },
    ]),
  );

  assert.deepEqual(listRecentUndoTokens(now), []);
});

test('listRecentUndoTokens_rejects_impossible_persisted_timestamps', () => {
  const now = 1_700_000_090_000;
  const storage = (globalThis as unknown as { localStorage: Storage }).localStorage;
  storage.setItem(
    __TEST_ONLY__.STORAGE_KEY,
    JSON.stringify([
      {
        token: 'impossible',
        label: 'Impossible time range',
        action: 'complete',
        issuedAt: now + 1_000,
        expiresAt: now + 500,
      },
    ]),
  );

  assert.deepEqual(listRecentUndoTokens(now), []);
});

test('undo token browser storage host fails closed when localStorage access throws', () => {
  const originalLocalStorage = Object.getOwnPropertyDescriptor(globalThis, 'localStorage');
  Object.defineProperty(globalThis, 'localStorage', {
    configurable: true,
    get: () => {
      throw new Error('storage unavailable');
    },
  });

  try {
    assert.equal(createBrowserUndoTokenStorageHost().getStorage(), null);
  } finally {
    if (originalLocalStorage) {
      Object.defineProperty(globalThis, 'localStorage', originalLocalStorage);
    } else {
      Reflect.deleteProperty(globalThis, 'localStorage');
    }
  }
});

test('undo token browser storage host reuses the central safeLocalStorage helper', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/undoTokenStore.runtime.ts'),
    'utf8',
  );

  assert.match(source, /import \{ safeLocalStorage \} from '\.\/storage';/);
  assert.match(source, /getStorage: \(\) => safeLocalStorage\(\),/);
  assert.doesNotMatch(source, /globalThis\.localStorage/);
});

test('undo token store delegates localStorage access to the runtime host', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/undoTokenStore.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{ createBrowserUndoTokenStorageHost \} from '\.\/undoTokenStore\.runtime';/,
  );
  assert.match(source, /import \{ tryParseJson \} from '\.\/security\/jsonParse';/);
  assert.match(source, /const undoTokenStorageHost = createBrowserUndoTokenStorageHost\(\);/);
  assert.doesNotMatch(source, /\(globalThis as \{ localStorage\?: Storage \}\)\.localStorage/);
  assert.doesNotMatch(source, /JSON\.parse\(/);
});

test('undo token entry validator narrows records before reading fields', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/undoTokenStore.ts'),
    'utf8',
  );

  assert.doesNotMatch(source, /value as Record<string, unknown>/);
});
