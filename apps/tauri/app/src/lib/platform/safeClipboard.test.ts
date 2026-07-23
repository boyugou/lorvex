import { invoke } from '@tauri-apps/api/core';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { safeWriteToClipboard } from '@/lib/platform/safeClipboard';
import { reportClientError } from '@/lib/errors/errorLogging';

vi.mock('@tauri-apps/api/core', () => ({
  invoke: vi.fn(),
}));

vi.mock('@/lib/errors/errorLogging', () => ({
  reportClientError: vi.fn(),
}));

const invokeMock = vi.mocked(invoke);
const reportClientErrorMock = vi.mocked(reportClientError);

function installNavigatorClipboard(writeText?: (text: string) => Promise<void>) {
  Object.defineProperty(globalThis, 'navigator', {
    configurable: true,
    value: writeText ? { clipboard: { writeText } } : {},
  });
}

describe('safeWriteToClipboard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    installNavigatorClipboard();
  });

  it('falls back to the Tauri clipboard bridge when web clipboard rejects', async () => {
    const webWriteText = vi
      .fn<(text: string) => Promise<void>>()
      .mockRejectedValue(new DOMException('Gesture expired', 'NotAllowedError'));
    invokeMock.mockResolvedValue(undefined);
    installNavigatorClipboard(webWriteText);

    const result = await safeWriteToClipboard('copy me', 'test.clipboard');

    expect(result).toEqual({ ok: true });
    expect(webWriteText).toHaveBeenCalledWith('copy me');
    expect(invokeMock).toHaveBeenCalledWith(
      'plugin:clipboard-manager|write_text',
      { text: 'copy me' },
    );
    expect(reportClientErrorMock).not.toHaveBeenCalled();
  });

  it('returns a recovery hint when both clipboard paths fail due to permissions', async () => {
    installNavigatorClipboard(undefined);
    invokeMock.mockRejectedValue(new Error('plugin command not allowed'));

    const result = await safeWriteToClipboard('copy me', 'test.clipboard');

    expect(result.ok).toBe(false);
    expect(result).toMatchObject({
      recoveryHint: 'Select the text and press Cmd+C / Ctrl+C manually.',
    });
    expect(reportClientErrorMock).toHaveBeenCalledWith(
      'test.clipboard',
      'Clipboard write failed (web + Tauri bridge)',
      expect.any(Error),
      'tauriBridgeError: plugin command not allowed',
      'warn',
    );
  });
});
