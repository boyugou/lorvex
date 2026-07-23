import { isEditableTarget } from './editableTarget';

interface ClosestTargetLike {
  closest?: (selector: string) => unknown;
  parentElement?: ClosestTargetLike | null;
}

function isClosestTargetLike(target: EventTarget | ClosestTargetLike | null): target is ClosestTargetLike {
  return typeof target === 'object' && target !== null;
}

function closestElementTarget(target: EventTarget | null): Element | null {
  if (typeof Element !== 'undefined' && target instanceof Element) return target;
  if (typeof Node !== 'undefined' && target instanceof Node) return target.parentElement;
  const rawTarget = isClosestTargetLike(target) ? target : null;
  if (rawTarget && typeof rawTarget.closest === 'function') {
    return rawTarget as Element;
  }
  const parentElement = rawTarget?.parentElement ?? null;
  if (isClosestTargetLike(parentElement) && typeof parentElement.closest === 'function') {
    return parentElement as Element;
  }
  return null;
}

/** Returns true if the keyboard event target is an input-like element or inside a modal overlay where character shortcuts should not fire.
 *
 * expanded the interactive-role allowlist to cover
 * role=switch / role=menu / role=menuitem / role=dialog. Toggle
 * switches and popover menus that capture their own key events need
 * shortcut suppression just as much as role=option / role=combobox
 * already did. Milkdown's contenteditable blocks are already covered
 * by the explicit \`isContentEditable\` check.
 */
export function shouldIgnoreShortcut(target: EventTarget | null): boolean {
  if (isEditableTarget(target)) return true;
  const element = closestElementTarget(target);
  if (!element) return false;
  return Boolean(
    element.closest(
      '[role="combobox"],[role="listbox"],[role="option"],[role="menu"],[role="menuitem"],[role="switch"],[role="dialog"],[aria-modal="true"],button[aria-haspopup="listbox"],button[aria-haspopup="menu"]',
    ),
  );
}

/**
 * a stricter sibling of `shouldIgnoreShortcut` for use
 * by global modifier-key (chord) handlers — e.g. ⌘Z / ⌘⇧Z / ⌘Y, ⌘K.
 *
 * `shouldIgnoreShortcut` blocks any keystroke whose target is inside a
 * `[role="dialog"]`, `[aria-modal="true"]`, popover menu, etc. That is
 * the right behaviour for bare-key shortcuts (`j` / `k` / `?`): while a
 * confirm dialog is open the user is reading the prompt, not driving
 * the task list. But it also silently swallowed chord shortcuts — so
 * the user could not press ⌘Z to undo from inside a confirm dialog and
 * could not press ⌘K to switch from a confirm to the command palette.
 *
 * This variant only suppresses the shortcut when the target is itself
 * editable (input / textarea / contenteditable). Modifier-key chords
 * still fire from inside dialogs and other interactive overlays, which
 * matches every native OS convention (TextEdit, Finder, etc. all let
 * ⌘Z through dialog-style sheets).
 */
export function shouldIgnoreChordShortcut(target: EventTarget | null): boolean {
  return isEditableTarget(target);
}
