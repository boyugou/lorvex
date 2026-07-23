import type { ContextMenuPosition } from './ContextMenu';

interface ContextMenuRect {
  width: number;
  height: number;
}

interface ContextMenuViewport {
  width: number;
  height: number;
}

type ContextMenuFocusRestoreCandidate = HTMLElement | null | undefined;

interface ContextSubmenuParentRect {
  left: number;
  width: number;
  right: number;
  top: number;
}

interface ContextSubmenuPosition {
  left: number;
  top: number;
}

export type ContextMenuKeyAction =
  | 'close'
  | 'highlight-next'
  | 'highlight-previous'
  | 'select-highlighted'
  | 'trap-focus'
  // keyboard support for nested submenus. Mirrors the
  // WAI-ARIA `menu` pattern: ArrowRight / Enter on a submenu-bearing
  // row opens it and shifts the highlight onto the first child;
  // ArrowLeft / Escape closes the submenu and returns the highlight
  // to the parent row.
  | 'open-submenu'
  | 'close-submenu'
  | 'submenu-next'
  | 'submenu-previous'
  | 'submenu-select';

interface ContextMenuKeyEventLike {
  key: string;
  isComposing?: boolean | undefined;
  /**
   * legacy IME composition signal. Modern browsers
   * set `isComposing` while a CJK / Hangul / etc. composition is in
   * flight, but older Safari and Edge versions instead emit
   * `keyCode === 229` for every keystroke routed to the IME — with
   * `isComposing === false`. Both signals must be checked together
   * so a capture-phase `keydown` listener does not pre-empt the
   * IME and silently drop a character mid-composition.
   */
  keyCode?: number | undefined;
  preventDefault: () => void;
  stopPropagation: () => void;
  stopImmediatePropagation?: (() => void) | undefined;
}

interface ContextMenuSelectableItem {
  hasSubmenu: boolean;
  onSelect?: (() => void) | undefined;
}

interface ContextMenuKeyboardRuntimeDeps {
  addWindowKeydownListener:
    | ((listener: (event: KeyboardEvent) => void) => () => void)
    | null;
  getActionableItemCount: () => number;
  getHighlightIndex?: (() => number) | undefined;
  getHighlightedItem: () => ContextMenuSelectableItem | undefined;
  setHighlightIndex: (updater: (previousIndex: number) => number) => void;
  focusItemAtIndex?: ((index: number) => void) | undefined;
  onClose: () => void;
  /**
   * optional submenu state plumbing. Components that
   * support nested submenus thread these in; the keyboard runtime
   * routes ArrowRight / ArrowLeft / Enter to the active submenu when
   * one is open, or treats them as open/close affordances on a
   * submenu-bearing parent row when no submenu is open.
   */
  isSubmenuOpen?: () => boolean;
  getSubmenuItemCount?: () => number;
  getSubmenuHighlightIndex?: (() => number) | undefined;
  getSubmenuHighlightedItem?: () => ContextMenuSelectableItem | undefined;
  setSubmenuHighlightIndex?: (updater: (previousIndex: number) => number) => void;
  focusSubmenuItemAtIndex?: ((index: number) => void) | undefined;
  openHighlightedSubmenu?: () => void;
  closeSubmenu?: () => void;
  textDirection?: (() => ContextMenuTextDirection) | undefined;
}

type ContextMenuHighlightDirection = 'next' | 'previous';
type ContextMenuTextDirection = 'ltr' | 'rtl';

const MENU_PADDING = 8;
const SUBMENU_OVERLAP_PX = 2;

function isConnectedContextMenuFocusTarget(
  candidate: ContextMenuFocusRestoreCandidate,
): candidate is HTMLElement {
  return candidate?.isConnected === true;
}

export function resolveContextMenuFocusRestoreTarget(
  launcherElement: ContextMenuFocusRestoreCandidate,
  fallbackElement: ContextMenuFocusRestoreCandidate,
): HTMLElement | null {
  if (isConnectedContextMenuFocusTarget(launcherElement)) return launcherElement;
  if (isConnectedContextMenuFocusTarget(fallbackElement)) return fallbackElement;
  return null;
}

export function restoreContextMenuFocus(
  launcherElement: ContextMenuFocusRestoreCandidate,
  fallbackElement: ContextMenuFocusRestoreCandidate,
): boolean {
  const target = resolveContextMenuFocusRestoreTarget(launcherElement, fallbackElement);
  if (!target) return false;
  target.focus();
  return true;
}

export function resolveContextMenuPosition(
  position: ContextMenuPosition,
  rect: ContextMenuRect,
  viewport: ContextMenuViewport,
  padding = MENU_PADDING,
): ContextMenuPosition {
  const maxX = Math.max(padding, viewport.width - rect.width - padding);
  const maxY = Math.max(padding, viewport.height - rect.height - padding);

  return {
    x: Math.min(Math.max(padding, position.x), maxX),
    y: Math.min(Math.max(padding, position.y), maxY),
  };
}

export function resolveContextSubmenuPosition(
  parentRect: ContextSubmenuParentRect,
  submenuRect: ContextMenuRect,
  viewport: ContextMenuViewport,
  textDirection: ContextMenuTextDirection = 'ltr',
  padding = MENU_PADDING,
): ContextSubmenuPosition {
  const opensInlineEnd = textDirection === 'rtl'
    ? parentRect.left - submenuRect.width >= padding
    : parentRect.right + submenuRect.width + padding <= viewport.width;
  const left = textDirection === 'rtl'
    ? opensInlineEnd
      ? -submenuRect.width + SUBMENU_OVERLAP_PX
      : parentRect.width - SUBMENU_OVERLAP_PX
    : opensInlineEnd
      ? parentRect.width - SUBMENU_OVERLAP_PX
      : -submenuRect.width + SUBMENU_OVERLAP_PX;

  const overflowTop = viewport.height - parentRect.top - submenuRect.height - padding;
  const minTop = padding - parentRect.top;
  const top = Math.min(0, Math.max(minTop, overflowTop));

  return { left, top };
}

interface ContextMenuKeyActionContext {
  isSubmenuOpen: boolean;
  highlightedHasSubmenu: boolean;
  textDirection?: ContextMenuTextDirection;
}

export function resolveContextMenuKeyAction(
  event: Pick<ContextMenuKeyEventLike, 'key' | 'isComposing' | 'keyCode'>,
  context: ContextMenuKeyActionContext = { isSubmenuOpen: false, highlightedHasSubmenu: false },
): ContextMenuKeyAction | null {
  // bail on both the modern `isComposing` signal AND
  // the legacy `keyCode === 229` IME marker so the capture-phase
  // listener never pre-empts a composition on older browsers that
  // omit `isComposing`.
  if (event.isComposing) return null;
  if (event.keyCode === 229) return null;
  const textDirection = context.textDirection ?? 'ltr';
  const openSubmenuKey = textDirection === 'rtl' ? 'ArrowLeft' : 'ArrowRight';
  const closeSubmenuKey = textDirection === 'rtl' ? 'ArrowRight' : 'ArrowLeft';

  // Submenu-open routing: navigation keys steer the SUBmenu first.
  if (context.isSubmenuOpen) {
    if (event.key === 'Escape' || event.key === closeSubmenuKey) return 'close-submenu';
    if (event.key === 'ArrowDown' || event.key === 'j') return 'submenu-next';
    if (event.key === 'ArrowUp' || event.key === 'k') return 'submenu-previous';
    if (event.key === 'Enter') return 'submenu-select';
    if (event.key === 'Tab') return 'trap-focus';
    return null;
  }

  if (event.key === 'Escape') return 'close';
  if (event.key === 'ArrowDown' || event.key === 'j') return 'highlight-next';
  if (event.key === 'ArrowUp' || event.key === 'k') return 'highlight-previous';
  // ArrowRight / Enter on a parent row that has a
  // submenu opens the submenu and shifts the highlight inside.
  // Enter on a leaf row keeps its previous "select" behavior.
  if (event.key === openSubmenuKey && context.highlightedHasSubmenu) return 'open-submenu';
  if (event.key === 'Enter') return context.highlightedHasSubmenu ? 'open-submenu' : 'select-highlighted';
  if (event.key === 'Tab') return 'trap-focus';

  return null;
}

export function resolveNextContextMenuHighlightIndex(
  previousIndex: number,
  actionableItemCount: number,
  direction: ContextMenuHighlightDirection,
): number {
  if (actionableItemCount <= 0) return -1;

  if (direction === 'next') {
    const next = previousIndex + 1;
    return next >= actionableItemCount ? 0 : next;
  }

  const next = previousIndex - 1;
  return next < 0 ? actionableItemCount - 1 : next;
}

export function runContextMenuKeyAction(
  action: ContextMenuKeyAction,
  event: ContextMenuKeyEventLike,
  deps: Pick<
    ContextMenuKeyboardRuntimeDeps,
    'getActionableItemCount'
    | 'getHighlightIndex'
    | 'getHighlightedItem'
    | 'setHighlightIndex'
    | 'focusItemAtIndex'
    | 'onClose'
    | 'getSubmenuItemCount'
    | 'getSubmenuHighlightIndex'
    | 'getSubmenuHighlightedItem'
    | 'setSubmenuHighlightIndex'
    | 'focusSubmenuItemAtIndex'
    | 'openHighlightedSubmenu'
    | 'closeSubmenu'
  >,
): void {
  if (action === 'trap-focus') {
    deps.onClose();
    return;
  }

  event.preventDefault();
  event.stopPropagation();

  if (action === 'close') {
    event.stopImmediatePropagation?.();
    deps.onClose();
    return;
  }

  if (action === 'highlight-next') {
    if (deps.getHighlightIndex) {
      const nextIndex = resolveNextContextMenuHighlightIndex(
        deps.getHighlightIndex(),
        deps.getActionableItemCount(),
        'next',
      );
      deps.setHighlightIndex(() => nextIndex);
      if (nextIndex >= 0) deps.focusItemAtIndex?.(nextIndex);
      return;
    }
    deps.setHighlightIndex((previousIndex) => (
      resolveNextContextMenuHighlightIndex(previousIndex, deps.getActionableItemCount(), 'next')
    ));
    return;
  }

  if (action === 'highlight-previous') {
    if (deps.getHighlightIndex) {
      const nextIndex = resolveNextContextMenuHighlightIndex(
        deps.getHighlightIndex(),
        deps.getActionableItemCount(),
        'previous',
      );
      deps.setHighlightIndex(() => nextIndex);
      if (nextIndex >= 0) deps.focusItemAtIndex?.(nextIndex);
      return;
    }
    deps.setHighlightIndex((previousIndex) => (
      resolveNextContextMenuHighlightIndex(previousIndex, deps.getActionableItemCount(), 'previous')
    ));
    return;
  }

  if (action === 'select-highlighted') {
    const item = deps.getHighlightedItem();
    if (!item || item.hasSubmenu) return;

    item.onSelect?.();
    deps.onClose();
    return;
  }

  if (action === 'open-submenu') {
    deps.openHighlightedSubmenu?.();
    const initialIndex = (deps.getSubmenuItemCount?.() ?? 0) > 0 ? 0 : -1;
    deps.setSubmenuHighlightIndex?.(() => initialIndex);
    if (initialIndex >= 0) deps.focusSubmenuItemAtIndex?.(initialIndex);
    return;
  }

  if (action === 'close-submenu') {
    deps.closeSubmenu?.();
    const parentIndex = deps.getHighlightIndex?.() ?? -1;
    if (parentIndex >= 0) deps.focusItemAtIndex?.(parentIndex);
    return;
  }

  if (action === 'submenu-next') {
    if (deps.getSubmenuHighlightIndex) {
      const nextIndex = resolveNextContextMenuHighlightIndex(
        deps.getSubmenuHighlightIndex(),
        deps.getSubmenuItemCount?.() ?? 0,
        'next',
      );
      deps.setSubmenuHighlightIndex?.(() => nextIndex);
      if (nextIndex >= 0) deps.focusSubmenuItemAtIndex?.(nextIndex);
      return;
    }
    deps.setSubmenuHighlightIndex?.((previousIndex) => (
      resolveNextContextMenuHighlightIndex(previousIndex, deps.getSubmenuItemCount?.() ?? 0, 'next')
    ));
    return;
  }

  if (action === 'submenu-previous') {
    if (deps.getSubmenuHighlightIndex) {
      const nextIndex = resolveNextContextMenuHighlightIndex(
        deps.getSubmenuHighlightIndex(),
        deps.getSubmenuItemCount?.() ?? 0,
        'previous',
      );
      deps.setSubmenuHighlightIndex?.(() => nextIndex);
      if (nextIndex >= 0) deps.focusSubmenuItemAtIndex?.(nextIndex);
      return;
    }
    deps.setSubmenuHighlightIndex?.((previousIndex) => (
      resolveNextContextMenuHighlightIndex(previousIndex, deps.getSubmenuItemCount?.() ?? 0, 'previous')
    ));
    return;
  }

  if (action === 'submenu-select') {
    const item = deps.getSubmenuHighlightedItem?.();
    if (!item || item.hasSubmenu) return;

    item.onSelect?.();
    deps.onClose();
  }
}

export function installContextMenuKeyboardRuntime(deps: ContextMenuKeyboardRuntimeDeps): () => void {
  if (!deps.addWindowKeydownListener) {
    return () => {};
  }

  return deps.addWindowKeydownListener((event) => {
    const submenuOpen = deps.isSubmenuOpen?.() ?? false;
    const highlighted = deps.getHighlightedItem();
    const action = resolveContextMenuKeyAction(event, {
      isSubmenuOpen: submenuOpen,
      highlightedHasSubmenu: Boolean(highlighted?.hasSubmenu),
      textDirection: deps.textDirection?.() ?? 'ltr',
    });
    if (!action) return;

    runContextMenuKeyAction(action, event, deps);
  });
}
