import {
  createBrowserAnchoredPopupDismissRuntimeDeps,
  installAnchoredPopupDismissRuntime,
  resolveAnchoredPopupPosition,
  shouldDismissAnchoredPopupFromKeyEvent,
  shouldDismissAnchoredPopupFromTarget,
} from './portalDropdown.runtime';

interface SavedQueriesMenuPosition {
  top: number;
  left: number;
}

interface SavedQueriesMenuRect {
  left: number;
  bottom: number;
}

interface SavedQueriesMenuDismissRuntimeDeps {
  addDocumentMouseDownListener:
    | ((listener: (event: MouseEvent) => void) => () => void)
    | null;
  addDocumentKeydownListener:
    | ((listener: (event: KeyboardEvent) => void) => () => void)
    | null;
  isInsideTarget: (target: EventTarget | null) => boolean;
  onDismiss: () => void;
}

type SavedQueriesMenuFocusable = Pick<HTMLElement, 'focus'>;

interface SavedQueriesMenuInitialFocusArgs {
  panel: SavedQueriesMenuFocusable | null;
  activeElement: unknown;
  isActiveElementInPanel: (activeElement: unknown) => boolean;
  isLoading: boolean;
  savedQueryCount: number;
  firstItem: SavedQueriesMenuFocusable | null;
  nameInput: SavedQueriesMenuFocusable | null;
}

type SavedQueriesMenuInitialFocusTarget =
  | 'none'
  | 'active-element'
  | 'panel'
  | 'first-item'
  | 'name-input';

type SavedQueriesMenuDocumentTarget = Pick<Document, 'addEventListener' | 'removeEventListener'>;

interface BrowserSavedQueriesMenuDismissRuntimeDeps {
  documentTarget?: SavedQueriesMenuDocumentTarget | undefined;
  getTrigger: () => HTMLElement | null;
  getPanel: () => HTMLElement | null;
  nodeConstructor?: typeof Node | undefined;
  onDismiss: () => void;
}

const DEFAULT_MENU_WIDTH_PX = 260;
const DEFAULT_VIEWPORT_PADDING_PX = 8;
const DEFAULT_GAP_PX = 4;

export function resolveSavedQueriesMenuPosition(
  rect: SavedQueriesMenuRect,
  viewportWidth: number,
  menuWidth = DEFAULT_MENU_WIDTH_PX,
  viewportPadding = DEFAULT_VIEWPORT_PADDING_PX,
  gap = DEFAULT_GAP_PX,
): SavedQueriesMenuPosition {
  return resolveAnchoredPopupPosition({
    rect,
    viewportWidth,
    popupWidth: menuWidth,
    viewportPadding,
    gap,
  });
}

export function focusSavedQueriesMenuInitialTarget({
  panel,
  activeElement,
  isActiveElementInPanel,
  isLoading,
  savedQueryCount,
  firstItem,
  nameInput,
}: SavedQueriesMenuInitialFocusArgs): SavedQueriesMenuInitialFocusTarget {
  if (!panel) return 'none';
  if (isActiveElementInPanel(activeElement)) return 'active-element';
  if (isLoading) {
    panel.focus();
    return 'panel';
  }
  if (savedQueryCount > 0) {
    if (!firstItem) {
      panel.focus();
      return 'panel';
    }
    firstItem.focus();
    return 'first-item';
  }
  if (!nameInput) {
    panel.focus();
    return 'panel';
  }
  nameInput.focus();
  return 'name-input';
}

export function shouldDismissSavedQueriesMenuFromPointerTarget(
  target: EventTarget | null,
  isInsideTarget: (target: EventTarget | null) => boolean,
): boolean {
  return shouldDismissAnchoredPopupFromTarget(target, isInsideTarget);
}

export function shouldDismissSavedQueriesMenuFromKeyEvent(
  event: Pick<KeyboardEvent, 'isComposing' | 'key'>,
): boolean {
  return shouldDismissAnchoredPopupFromKeyEvent(event);
}

export function installSavedQueriesMenuDismissRuntime({
  addDocumentMouseDownListener,
  addDocumentKeydownListener,
  isInsideTarget,
  onDismiss,
}: SavedQueriesMenuDismissRuntimeDeps): () => void {
  return installAnchoredPopupDismissRuntime({
    addDocumentMouseDownListener,
    addDocumentKeydownListener,
    isInsideTarget,
    onPointerDismiss: onDismiss,
    onEscapeDismiss: onDismiss,
  });
}

export function createBrowserSavedQueriesMenuDismissRuntimeDeps({
  documentTarget = typeof document === 'undefined' ? undefined : document,
  getTrigger,
  getPanel,
  nodeConstructor = typeof Node === 'undefined' ? undefined : Node,
  onDismiss,
}: BrowserSavedQueriesMenuDismissRuntimeDeps): SavedQueriesMenuDismissRuntimeDeps {
  const anchoredDeps = createBrowserAnchoredPopupDismissRuntimeDeps({
    documentTarget,
    getTrigger,
    getPanel,
    nodeConstructor,
    onPointerDismiss: onDismiss,
    onEscapeDismiss: onDismiss,
    listenForEscape: true,
  });
  return {
    addDocumentMouseDownListener: anchoredDeps.addDocumentMouseDownListener,
    addDocumentKeydownListener: anchoredDeps.addDocumentKeydownListener ?? null,
    isInsideTarget: anchoredDeps.isInsideTarget,
    onDismiss,
  };
}
