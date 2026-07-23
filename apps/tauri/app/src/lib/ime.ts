import type React from 'react';

type ImeLikeKeyboardEvent = {
  isComposing?: boolean;
  keyCode?: number;
  which?: number;
} | null | undefined;

/**
 * Low-level probe over a structurally typed keyboard-event shape. Treats
 * `keyCode === 229` / `which === 229` as composing because some browsers
 * (notably older Chromium on Windows) clear `isComposing` before the
 * Enter/Escape keydown that ends a composition while still stamping the
 * legacy 229 code.
 */
export function isImeComposingEvent(event: ImeLikeKeyboardEvent): boolean {
  if (!event) return false;
  return Boolean(event.isComposing) || event.keyCode === 229 || event.which === 229;
}

/**
 * Canonical IME-composing guard for keyboard handlers. Accepts either
 * a React synthetic event (unwrapped via `nativeEvent`) or a raw DOM
 * `KeyboardEvent`, and returns `true` while an IME composition is in
 * progress — the universal signal to let a Return/Escape keystroke
 * pass through to the IME instead of triggering submit/cancel logic.
 *
 * Use this at the top of every form-input `onKeyDown` that interprets
 * Enter / Escape:
 *
 * ```ts
 * if (isImeComposing(e)) return;
 * ```
 */
export function isImeComposing(
  event: React.KeyboardEvent | KeyboardEvent | null | undefined,
): boolean {
  if (!event) return false;
  const native = (event as React.KeyboardEvent).nativeEvent as KeyboardEvent | undefined;
  const probe = native ?? (event as KeyboardEvent);
  return isImeComposingEvent(probe as ImeLikeKeyboardEvent);
}
