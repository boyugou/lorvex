import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

class InMemoryStorage {
  private readonly entries = new Map<string, string>();

  clear(): void {
    this.entries.clear();
  }

  getItem(key: string): string | null {
    return this.entries.get(key) ?? null;
  }

  setItem(key: string, value: string): void {
    this.entries.set(key, value);
  }

  removeItem(key: string): void {
    this.entries.delete(key);
  }
}

const storage = new InMemoryStorage();
(globalThis as unknown as { localStorage: InMemoryStorage }).localStorage = storage;

import {
  getUIStateBoolean,
  getUIStateString,
  setUIState,
  setUIStateBoolean,
} from '../../../app/src/lib/storage/uiState';
import { createBrowserUIStateStorageHost } from '../../../app/src/lib/storage/uiState.runtime';

test.beforeEach(() => {
  storage.clear();
});

test('ui state booleans: setUIStateBoolean round-trips through getUIStateBoolean', () => {
  setUIStateBoolean('allTasks.showCompleted', true);
  assert.equal(getUIStateBoolean('allTasks.showCompleted', false), true);

  setUIStateBoolean('allTasks.showCompleted', false);
  assert.equal(getUIStateBoolean('allTasks.showCompleted', true), false);
});

test('ui state booleans: string payloads fail closed to fallback', () => {
  setUIState('allTasks.showCancelled', 'true');
  assert.equal(
    getUIStateBoolean('allTasks.showCancelled', false),
    false,
    'quoted JSON string "true" is not a canonical boolean',
  );

  setUIState('allTasks.showCancelled', 'false');
  assert.equal(
    getUIStateBoolean('allTasks.showCancelled', true),
    true,
    'quoted JSON string "false" is not a canonical boolean',
  );
});

test('ui state booleans: malformed payload falls back instead of poisoning state', () => {
  storage.setItem('lorvex:allTasks.showCompleted', '{"not":"a boolean"}');
  assert.equal(getUIStateBoolean('allTasks.showCompleted', true), true);
  assert.equal(getUIStateBoolean('allTasks.showCompleted', false), false);
});

test('ui state strings: setUIState payload preserves exact string values', () => {
  setUIState('allTasks.groupBy', 'status');
  assert.equal(getUIStateString('allTasks.groupBy', ''), 'status');
});

test('ui state strings: raw strings fail closed when JSON parsing fails', () => {
  storage.setItem('lorvex:allTasks.groupBy', 'status');
  assert.equal(getUIStateString('allTasks.groupBy', 'fallback'), 'fallback');
});

test('ui state strings: structured JSON payloads fail closed to fallback', () => {
  storage.setItem('lorvex:allTasks.groupBy', '{"kind":"status"}');
  assert.equal(getUIStateString('allTasks.groupBy', 'fallback'), 'fallback');

  storage.setItem('lorvex:allTasks.groupBy', '["status"]');
  assert.equal(getUIStateString('allTasks.groupBy', 'fallback'), 'fallback');
});

test('ui state browser storage host fails closed when localStorage access throws', () => {
  const originalLocalStorage = Object.getOwnPropertyDescriptor(globalThis, 'localStorage');
  Object.defineProperty(globalThis, 'localStorage', {
    configurable: true,
    get: () => {
      throw new Error('storage unavailable');
    },
  });

  try {
    assert.equal(createBrowserUIStateStorageHost().getStorage(), null);
  } finally {
    if (originalLocalStorage) {
      Object.defineProperty(globalThis, 'localStorage', originalLocalStorage);
    } else {
      Reflect.deleteProperty(globalThis, 'localStorage');
    }
  }
});

test('ui state browser storage host reuses the central safeLocalStorage helper', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/storage/uiState.runtime.ts'),
    'utf8',
  );

  assert.match(source, /import \{ safeLocalStorage \} from '\.\/index';/);
  assert.match(source, /getStorage: \(\) => safeLocalStorage\(\),/);
  assert.doesNotMatch(source, /globalThis\.localStorage/);
});

test('ui state module delegates localStorage access to the runtime host', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/storage/uiState.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{ createBrowserUIStateStorageHost \} from '\.\/uiState\.runtime';/,
  );
  assert.match(source, /import \{ tryParseJson \} from '\.\.\/security\/jsonParse';/);
  assert.match(source, /const uiStateStorageHost = createBrowserUIStateStorageHost\(\);/);
  assert.doesNotMatch(source, /globalThis\.localStorage/);
  assert.doesNotMatch(source, /JSON\.parse\(/);
});

test('ui state generic reader requires a runtime validator instead of unchecked casts', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/storage/uiState.ts'),
    'utf8',
  );

  assert.match(
    source,
    /validator: \(value: unknown\) => value is T,/,
    'generic UI state reads must require a validator at the public boundary',
  );
  assert.doesNotMatch(
    source,
    /validator\?:/,
    'generic UI state reads must not allow unvalidated payload reads',
  );
  assert.doesNotMatch(
    source,
    /parsed as T/,
    'validated reads should rely on the type guard instead of an unchecked cast',
  );
});

test('ui state boolean reader parses canonical boolean storage without JSON parsing', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/storage/uiState.ts'),
    'utf8',
  );
  const booleanParser = source.match(/function parseStoredBoolean[\s\S]*?\n}\n/);
  assert.ok(booleanParser, 'parseStoredBoolean must remain a local parser');
  assert.doesNotMatch(booleanParser[0], /JSON\.parse/);
});
