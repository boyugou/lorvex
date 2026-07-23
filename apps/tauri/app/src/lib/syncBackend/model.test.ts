import { describe, expect, test } from 'vitest';

import { SYNC_BACKEND_FILESYSTEM_BRIDGE } from './kinds';
import { getSyncBackendSupportContext } from './model';

describe('getSyncBackendSupportContext', () => {
  test('returns a stable support context for the same backend kind list', () => {
    const runtimeProfile = {
      supportedSyncBackendKinds: [SYNC_BACKEND_FILESYSTEM_BRIDGE],
    } as const;

    expect(getSyncBackendSupportContext(runtimeProfile)).toBe(
      getSyncBackendSupportContext(runtimeProfile),
    );
  });
});
