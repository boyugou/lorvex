import { resolveRuntimeId } from '../platform/platform.logic';
import { readRuntimeNavigatorSnapshot } from '../platform/platform.runtime';

export type ShortcutToken = 'Mod' | 'Shift' | 'Alt' | string;
export type ShortcutPlatformStyle = 'apple' | 'nonApple';

function isApplePlatform(): boolean {
  const snapshot = readRuntimeNavigatorSnapshot();
  if (!snapshot) return true;

  const runtimeId = resolveRuntimeId(snapshot);
  return runtimeId === 'macos';
}

/** Check if the platform-primary modifier (Cmd on Mac, Ctrl on Windows/Linux) is held. */
export function isPrimaryModifierPressed(event: KeyboardEvent): boolean {
  return isApplePlatform() ? event.metaKey : event.ctrlKey;
}

export function formatShortcutForPlatform(
  tokens: ShortcutToken[],
  platform: ShortcutPlatformStyle,
): string {
  const apple = platform === 'apple';
  const map: Record<string, string> = {
    Mod: apple ? '⌘' : 'Ctrl',
    Shift: apple ? '⇧' : 'Shift',
    Alt: apple ? '⌥' : 'Alt',
  };
  const parts = tokens.map((token) => map[token] ?? token);
  return apple ? parts.join('') : parts.join('+');
}

/** Format a token array into a readable shortcut string.
 *  e.g. formatShortcut(['Mod','K']) → '⌘K' (Mac) or 'Ctrl+K' (Win/Linux)
 */
export function formatShortcut(tokens: ShortcutToken[]): string {
  return formatShortcutForPlatform(tokens, isApplePlatform() ? 'apple' : 'nonApple');
}

function ariaShortcutToken(token: ShortcutToken): string {
  const map: Record<string, string> = {
    '↵': 'Enter',
    Esc: 'Escape',
    '←': 'ArrowLeft',
    '→': 'ArrowRight',
    '↑': 'ArrowUp',
    '↓': 'ArrowDown',
  };
  return map[token] ?? token;
}

function ariaKeyShortcutChord(tokens: ShortcutToken[], modToken: 'Meta' | 'Control'): string {
  return tokens
    .map((token) => (token === 'Mod' ? modToken : ariaShortcutToken(token)))
    .join('+');
}

export function ariaKeyShortcutsForModChord(tokens: ShortcutToken[]): string {
  if (!tokens.includes('Mod')) {
    return tokens.map(ariaShortcutToken).join('+');
  }
  return [
    ariaKeyShortcutChord(tokens, 'Meta'),
    ariaKeyShortcutChord(tokens, 'Control'),
  ].join(' ');
}
