import { invoke } from '@tauri-apps/api/core';

import { reportClientError } from '@/lib/errors/errorLogging';

export type SafeWriteToClipboardResult =
  | { ok: true }
  | { ok: false; error: Error; recoveryHint?: string };

const CLIPBOARD_UNAVAILABLE_MESSAGE = 'Clipboard API is unavailable';

/*
 * When both the web Clipboard API and the Tauri bridge fail,
 * the user is dead in the water unless they know they can fall back to
 * a manual `Cmd+C` / `Ctrl+C`. The recovery hint is a generic, locale-
 * agnostic string that callers can surface alongside the error toast.
 *
 * Detection heuristic: any failure that mentions permission, denial,
 * security/sandbox restrictions, or the unavailable-API marker is a
 * candidate — these are the cases where retrying via the same API
 * won't help, and the user must select+copy by hand.
 */
const PERMISSION_HINT_PATTERN =
  /not\s*allowed|notallowederror|permission|denied|sandbox|secure\s*context|unavailable/i;

const MANUAL_COPY_RECOVERY_HINT =
  'Select the text and press Cmd+C / Ctrl+C manually.';

function recoveryHintFor(primary: Error, fallback: Error): string | undefined {
  const message = `${primary.name} ${primary.message} ${fallback.message}`;
  if (PERMISSION_HINT_PATTERN.test(message)) {
    return MANUAL_COPY_RECOVERY_HINT;
  }
  return undefined;
}

async function tryWebClipboard(text: string): Promise<void> {
  const clipboard =
    typeof navigator !== 'undefined' ? navigator.clipboard : undefined;
  if (!clipboard || typeof clipboard.writeText !== 'function') {
    throw new Error(CLIPBOARD_UNAVAILABLE_MESSAGE);
  }
  await clipboard.writeText.call(clipboard, text);
}

async function tryTauriClipboardBridge(text: string): Promise<void> {
  // Tauri's clipboard-manager plugin exposes the bridge command
  // `plugin:clipboard-manager|write_text` taking a single `text`
  // argument. `invoke` rejects with a string error if the plugin
  // is not registered, which we surface as a normal Error.
  await invoke('plugin:clipboard-manager|write_text', { text });
}

export async function safeWriteToClipboard(
  text: string,
  source: string,
): Promise<SafeWriteToClipboardResult> {
  let primaryError: Error | null = null;
  try {
    await tryWebClipboard(text);
    return { ok: true };
  } catch (caught) {
    primaryError = caught instanceof Error ? caught : new Error(String(caught));
  }

  // Web path failed — try the Tauri bridge.
  try {
    await tryTauriClipboardBridge(text);
    // Don't report the primary error in this case: the user got a
    // working clipboard write via the fallback. Diagnostics noise
    // from a transient web-Clipboard rejection isn't worth the
    // false-alarm rate.
    return { ok: true };
  } catch (fallbackCaught) {
    const fallbackError =
      fallbackCaught instanceof Error
        ? fallbackCaught
        : new Error(String(fallbackCaught));
    // Both paths failed — report the *primary* failure (more useful
    // than the bridge's "not registered" error in most cases) but
    // attach the fallback in diagnostics context.
    reportClientError(
      source,
      'Clipboard write failed (web + Tauri bridge)',
      primaryError,
      `tauriBridgeError: ${fallbackError.message}`,
      'warn',
    );
    const recoveryHint = recoveryHintFor(primaryError, fallbackError);
    return recoveryHint
      ? { ok: false, error: primaryError, recoveryHint }
      : { ok: false, error: primaryError };
  }
}
