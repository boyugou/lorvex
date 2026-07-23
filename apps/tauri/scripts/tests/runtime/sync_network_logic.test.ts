import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  getNavigatorConnection,
  readNetworkCadenceHints,
  type NavigatorConnectionLike,
} from '../../../app/src/lib/sync/network';
import { readBrowserNavigatorConnection } from '../../../app/src/lib/sync/network.runtime';

function installNavigator(value: Navigator | undefined): () => void {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
  if (value === undefined) {
    Reflect.deleteProperty(globalThis, 'navigator');
  } else {
    Object.defineProperty(globalThis, 'navigator', {
      configurable: true,
      writable: true,
      value,
    });
  }
  return () => {
    if (descriptor) {
      Object.defineProperty(globalThis, 'navigator', descriptor);
      return;
    }
    Reflect.deleteProperty(globalThis, 'navigator');
  };
}

function navigatorWithConnection(connection?: NavigatorConnectionLike): Navigator {
  return { connection } as Navigator & { connection?: NavigatorConnectionLike };
}

test('getNavigatorConnection fails closed without navigator and returns the connection when present', () => {
  const restoreMissing = installNavigator(undefined);
  try {
    assert.equal(getNavigatorConnection(), null);
  } finally {
    restoreMissing();
  }

  const connection: NavigatorConnectionLike = { effectiveType: '2g', saveData: true };
  const restorePresent = installNavigator(navigatorWithConnection(connection));
  try {
    assert.equal(getNavigatorConnection(), connection);
  } finally {
    restorePresent();
  }
});

test('browser navigator connection runtime owns guarded host reads', () => {
  const restoreMissing = installNavigator(undefined);
  try {
    assert.equal(readBrowserNavigatorConnection(), null);
  } finally {
    restoreMissing();
  }

  const connection: NavigatorConnectionLike = { effectiveType: 'slow-2g', saveData: true };
  const restorePresent = installNavigator(navigatorWithConnection(connection));
  try {
    assert.equal(readBrowserNavigatorConnection(), connection);
  } finally {
    restorePresent();
  }
});

test('readNetworkCadenceHints only treats 2g and slow-2g as low bandwidth', () => {
  const restore = installNavigator(navigatorWithConnection({ effectiveType: 'SLOW-2G', saveData: true }));
  try {
    assert.deepEqual(readNetworkCadenceHints(), {
      lowBandwidth: true,
      saveData: true,
    });
  } finally {
    restore();
  }

  const restoreFast = installNavigator(navigatorWithConnection({ effectiveType: '3g', saveData: false }));
  try {
    assert.deepEqual(readNetworkCadenceHints(), {
      lowBandwidth: false,
      saveData: false,
    });
  } finally {
    restoreFast();
  }
});

test('readNetworkCadenceHints fails closed when the connection is missing or malformed', () => {
  const restoreMissing = installNavigator(navigatorWithConnection());
  try {
    assert.deepEqual(readNetworkCadenceHints(), {
      lowBandwidth: false,
      saveData: false,
    });
  } finally {
    restoreMissing();
  }

  const restoreMalformed = installNavigator(navigatorWithConnection({ effectiveType: 42 as unknown as string, saveData: 'false' as unknown as boolean }));
  try {
    assert.deepEqual(readNetworkCadenceHints(), {
      lowBandwidth: false,
      saveData: false,
    });
  } finally {
    restoreMalformed();
  }
});

test('sync network facade delegates browser host access to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/sync/network.ts'),
    'utf8',
  );

  assert.match(source, /readBrowserNavigatorConnection/);
  assert.doesNotMatch(source, /\bnavigator\b/);
  assert.doesNotMatch(source, /\bglobalThis\b/);
});
