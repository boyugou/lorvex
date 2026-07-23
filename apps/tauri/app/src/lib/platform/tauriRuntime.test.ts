import { afterEach, describe, expect, it } from 'vitest';

import { isTauriRuntimeAvailable } from './tauriRuntime';

interface MutableTauriRuntimeGlobal {
  __TAURI_INTERNALS__?: unknown;
}

const runtime = globalThis as MutableTauriRuntimeGlobal;

describe('isTauriRuntimeAvailable', () => {
  afterEach(() => {
    delete runtime.__TAURI_INTERNALS__;
  });

  it('returns false in a plain browser or test runtime', () => {
    delete runtime.__TAURI_INTERNALS__;

    expect(isTauriRuntimeAvailable()).toBe(false);
  });

  it('requires both the invoke bridge and runtime metadata', () => {
    runtime.__TAURI_INTERNALS__ = { invoke: () => undefined };
    expect(isTauriRuntimeAvailable()).toBe(false);

    runtime.__TAURI_INTERNALS__ = { metadata: { currentWindow: { label: 'main' } } };
    expect(isTauriRuntimeAvailable()).toBe(false);
  });

  it('returns true when the Tauri internals are present', () => {
    runtime.__TAURI_INTERNALS__ = {
      invoke: () => undefined,
      metadata: { currentWindow: { label: 'main' } },
    };

    expect(isTauriRuntimeAvailable()).toBe(true);
  });
});
