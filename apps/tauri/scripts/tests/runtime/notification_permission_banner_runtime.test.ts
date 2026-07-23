import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
  persistNotificationPermissionBannerDismissed,
  readNotificationPermissionBannerDismissed,
} from '../../../app/src/components/ui/NotificationPermissionBanner.runtime';

const bannerSource = readFileSync(
  new URL('../../../app/src/components/ui/NotificationPermissionBanner.tsx', import.meta.url),
  'utf8',
);

test('notification permission banner delegates session dismissal storage to a runtime seam', () => {
  assert.doesNotMatch(bannerSource, /\bsessionStorage\b/);
});

test('notification permission banner does not clear session dismissal during ordinary unmount', () => {
  assert.doesNotMatch(bannerSource, /removeItem\(\s*DISMISS_SESSION_KEY\s*\)/);
});

test('notification permission banner runtime reads and persists session dismissal', () => {
  const values = new Map<string, string>();
  const storage = {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => {
      values.set(key, value);
    },
  };

  assert.equal(readNotificationPermissionBannerDismissed(storage), false);
  persistNotificationPermissionBannerDismissed(storage);
  assert.equal(readNotificationPermissionBannerDismissed(storage), true);
});

test('notification permission banner runtime fails closed on storage errors', () => {
  const throwingStorage = {
    getItem: () => {
      throw new Error('blocked');
    },
    setItem: () => {
      throw new Error('quota');
    },
  };

  assert.equal(readNotificationPermissionBannerDismissed(throwingStorage), false);
  assert.doesNotThrow(() => persistNotificationPermissionBannerDismissed(throwingStorage));
  assert.equal(readNotificationPermissionBannerDismissed(null), false);
  assert.doesNotThrow(() => persistNotificationPermissionBannerDismissed(null));
});
