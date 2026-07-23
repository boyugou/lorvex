import type { ClipboardCopyHost } from './useCopyToClipboard.logic';

type ClipboardWriter = Pick<ClipboardCopyHost, 'writeText'>;

interface ClipboardNavigatorLike {
  clipboard?: {
    writeText?: (text: string) => Promise<void>;
  };
}

export function createBrowserClipboardWriter(
  navigatorLike: ClipboardNavigatorLike | undefined = typeof navigator === 'undefined' ? undefined : navigator,
): ClipboardWriter {
  return {
    writeText: async (text) => {
      const clipboard = navigatorLike?.clipboard;
      if (!clipboard || typeof clipboard.writeText !== 'function') {
        throw new Error('Clipboard API is unavailable');
      }
      await clipboard.writeText.call(clipboard, text);
    },
  };
}
