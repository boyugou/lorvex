import {
  createBrowserAnchoredPopupDismissRuntimeDeps,
  installAnchoredPopupDismissRuntime,
  resolveAnchoredPopupPosition,
  shouldDismissAnchoredPopupFromTarget,
} from './portalDropdown.runtime';

interface TagFilterPillsPanelPosition {
  top: number;
  left: number;
}

interface TagFilterPillsTriggerRect {
  left: number;
  bottom: number;
}

interface TagFilterPillsDismissRuntimeDeps {
  addDocumentMouseDownListener:
    | ((listener: (event: MouseEvent) => void) => () => void)
    | null;
  addDocumentScrollListener:
    | ((listener: (event: Event) => void) => () => void)
    | null;
  isInsideTarget: (target: EventTarget | null) => boolean;
  onDismiss: () => void;
}

type TagFilterPillsDocumentTarget = Pick<Document, 'addEventListener' | 'removeEventListener'>;

interface BrowserTagFilterPillsDismissRuntimeDeps {
  documentTarget?: TagFilterPillsDocumentTarget | undefined;
  getTrigger: () => HTMLElement | null;
  getPanel: () => HTMLElement | null;
  nodeConstructor?: typeof Node | undefined;
  onDismiss: () => void;
}

export interface TagFilterPillsTypeAheadState {
  timer: unknown | null;
  buffer: string;
}

export interface TagFilterPillsTypeAheadTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

const DEFAULT_PANEL_WIDTH_PX = 256;
const DEFAULT_VIEWPORT_PADDING_PX = 8;
const DEFAULT_GAP_PX = 4;
const TYPE_AHEAD_RESET_DELAY_MS = 500;

export function createBrowserTagFilterPillsTypeAheadTimerHost(): TagFilterPillsTypeAheadTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function resolveTagFilterPillsPanelPosition(
  rect: TagFilterPillsTriggerRect,
  viewportWidth: number,
  panelWidth = DEFAULT_PANEL_WIDTH_PX,
  viewportPadding = DEFAULT_VIEWPORT_PADDING_PX,
  gap = DEFAULT_GAP_PX,
): TagFilterPillsPanelPosition {
  return resolveAnchoredPopupPosition({
    rect,
    viewportWidth,
    popupWidth: panelWidth,
    viewportPadding,
    gap,
  });
}

export function shouldDismissTagFilterPillsFromTarget(
  target: EventTarget | null,
  isInsideTarget: (target: EventTarget | null) => boolean,
): boolean {
  return shouldDismissAnchoredPopupFromTarget(target, isInsideTarget);
}

export function installTagFilterPillsDismissRuntime({
  addDocumentMouseDownListener,
  addDocumentScrollListener,
  isInsideTarget,
  onDismiss,
}: TagFilterPillsDismissRuntimeDeps): () => void {
  return installAnchoredPopupDismissRuntime({
    addDocumentMouseDownListener,
    addDocumentScrollListener,
    isInsideTarget,
    onPointerDismiss: onDismiss,
    onScrollDismiss: onDismiss,
  });
}

export function createBrowserTagFilterPillsDismissRuntimeDeps({
  documentTarget = typeof document === 'undefined' ? undefined : document,
  getTrigger,
  getPanel,
  nodeConstructor = typeof Node === 'undefined' ? undefined : Node,
  onDismiss,
}: BrowserTagFilterPillsDismissRuntimeDeps): TagFilterPillsDismissRuntimeDeps {
  const anchoredDeps = createBrowserAnchoredPopupDismissRuntimeDeps({
    documentTarget,
    getTrigger,
    getPanel,
    nodeConstructor,
    onPointerDismiss: onDismiss,
    onScrollDismiss: onDismiss,
    listenForScroll: true,
  });
  return {
    addDocumentMouseDownListener: anchoredDeps.addDocumentMouseDownListener,
    addDocumentScrollListener: anchoredDeps.addDocumentScrollListener ?? null,
    isInsideTarget: anchoredDeps.isInsideTarget,
    onDismiss,
  };
}

export function findTagFilterPillsTypeAheadMatch(
  tags: readonly string[],
  focusedIndex: number,
  buffer: string,
): number | null {
  if (tags.length === 0 || buffer.length === 0) return null;

  const normalizedBuffer = buffer.toLowerCase();
  const startIndex = (Math.max(focusedIndex, -1) + 1) % tags.length;
  for (let offset = 0; offset < tags.length; offset += 1) {
    const index = (startIndex + offset) % tags.length;
    const tag = tags[index];
    if (tag?.toLowerCase().startsWith(normalizedBuffer)) {
      return index;
    }
  }

  return null;
}

export function advanceTagFilterPillsTypeAhead({
  state,
  typedChar,
  tags,
  focusedIndex,
  timerHost,
  resetDelayMs = TYPE_AHEAD_RESET_DELAY_MS,
}: {
  state: TagFilterPillsTypeAheadState;
  typedChar: string;
  tags: readonly string[];
  focusedIndex: number;
  timerHost: TagFilterPillsTypeAheadTimerHost;
  resetDelayMs?: number;
}): number | null {
  if (state.timer !== null) {
    timerHost.clearTimeout(state.timer);
  }

  state.buffer += typedChar.toLowerCase();
  state.timer = timerHost.setTimeout(() => {
    state.buffer = '';
    state.timer = null;
  }, resetDelayMs);

  return findTagFilterPillsTypeAheadMatch(tags, focusedIndex, state.buffer);
}

export function clearTagFilterPillsTypeAhead(
  state: TagFilterPillsTypeAheadState,
  clearTimeout: (handle: unknown) => void,
): void {
  if (state.timer !== null) {
    clearTimeout(state.timer);
  }
  state.timer = null;
  state.buffer = '';
}

export function resolveSelectedTagFilterPillLabels(
  availableTags: readonly string[],
  selectedTags: ReadonlySet<string>,
): string[] {
  if (selectedTags.size === 0) return [];
  const availableSelected = availableTags.filter((tag) => selectedTags.has(tag));
  const availableSelectedSet = new Set(availableSelected);
  const missingSelected = [...selectedTags]
    .filter((tag) => !availableSelectedSet.has(tag))
    .sort();
  return [...availableSelected, ...missingSelected];
}
