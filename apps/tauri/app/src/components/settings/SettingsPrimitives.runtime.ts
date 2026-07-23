import {
  createBrowserAnchoredPopupDismissRuntimeDeps,
  installAnchoredPopupDismissRuntime,
  resolveAnchoredPopupPosition,
  shouldDismissAnchoredPopupFromKeyEvent,
  shouldDismissAnchoredPopupFromTarget,
  type BrowserAnchoredPopupDismissRuntimeDeps,
} from '../ui/portalDropdown.runtime';

interface TimeInputDropdownDismissRuntimeDeps {
  addDocumentKeydownListener:
    | ((listener: (event: KeyboardEvent) => void) => () => void)
    | null;
  addDocumentMouseDownListener:
    | ((listener: (event: MouseEvent) => void) => () => void)
    | null;
  addDocumentScrollListener:
    | ((listener: (event: Event) => void) => () => void)
    | null;
  addWindowResizeListener:
    | ((listener: (event: Event) => void) => () => void)
    | null;
  isInsideTarget: (target: EventTarget | null) => boolean;
  onEscapeDismiss: () => void;
  onPointerDismiss: () => void;
  onScrollDismiss: () => void;
  onResizeDismiss: () => void;
}

interface TimeInputDropdownPosition {
  top: number;
  left: number;
}

interface TimeInputTriggerRect {
  top: number;
  left: number;
  bottom: number;
}

interface TimeInputDropdownPositionOptions {
  viewportWidth: number;
  viewportHeight: number;
  dropdownWidth?: number | undefined;
  dropdownHeight?: number | undefined;
  gap?: number | undefined;
}

type BrowserTimeInputDropdownDismissRuntimeDeps = Omit<
  BrowserAnchoredPopupDismissRuntimeDeps,
  | 'listenForEscape'
  | 'listenForScroll'
  | 'listenForResize'
  | 'onEscapeDismiss'
  | 'onPointerDismiss'
  | 'onScrollDismiss'
  | 'onResizeDismiss'
> & {
  onEscapeDismiss: () => void;
  onPointerDismiss: () => void;
  onScrollDismiss: () => void;
  onResizeDismiss: () => void;
};

const DEFAULT_TIME_INPUT_DROPDOWN_HEIGHT_PX = 240;
// Mirrors the TimeInput listbox Tailwind `w-44` width.
const DEFAULT_TIME_INPUT_DROPDOWN_WIDTH_PX = 176;
const DEFAULT_TIME_INPUT_GAP_PX = 4;
const DEFAULT_TIME_INPUT_FALLBACK_VALUE = '09:00';

export function getTimeInputInitialFocusIndex(
  value: string,
  slots: readonly string[],
  fallbackValue = DEFAULT_TIME_INPUT_FALLBACK_VALUE,
): number {
  const selectedIndex = slots.indexOf(value);
  if (selectedIndex !== -1) return selectedIndex;
  const fallbackIndex = slots.indexOf(fallbackValue);
  if (fallbackIndex !== -1) return fallbackIndex;
  return slots.length > 0 ? 0 : -1;
}

export function getNextTimeInputFocusIndex(
  key: string,
  currentIndex: number,
  optionCount: number,
): number {
  if (optionCount <= 0) return -1;

  const lastIndex = optionCount - 1;
  const clampedCurrent = currentIndex < 0
    ? -1
    : Math.min(currentIndex, lastIndex);

  if (key === 'ArrowDown') return Math.min(clampedCurrent + 1, lastIndex);
  if (key === 'ArrowUp') return Math.max(clampedCurrent - 1, 0);
  if (key === 'Home') return 0;
  if (key === 'End') return lastIndex;
  return clampedCurrent;
}

export function shouldDismissTimeInputDropdownFromKeyEvent(
  event: Pick<KeyboardEvent, 'isComposing' | 'key'>,
): boolean {
  return shouldDismissAnchoredPopupFromKeyEvent(event);
}

export function shouldDismissTimeInputDropdownFromPointerTarget(
  target: EventTarget | null,
  isInsideTarget: (target: EventTarget | null) => boolean,
): boolean {
  return shouldDismissAnchoredPopupFromTarget(target, isInsideTarget);
}

export function resolveTimeInputDropdownPosition(
  rect: TimeInputTriggerRect,
  {
    viewportWidth,
    viewportHeight,
    dropdownWidth = DEFAULT_TIME_INPUT_DROPDOWN_WIDTH_PX,
    dropdownHeight = DEFAULT_TIME_INPUT_DROPDOWN_HEIGHT_PX,
    gap = DEFAULT_TIME_INPUT_GAP_PX,
  }: TimeInputDropdownPositionOptions,
): TimeInputDropdownPosition {
  return resolveAnchoredPopupPosition({
    rect,
    viewportWidth,
    viewportHeight,
    popupWidth: dropdownWidth,
    popupHeight: dropdownHeight,
    gap,
    flipVertically: true,
  });
}

export function installTimeInputDropdownDismissRuntime({
  addDocumentKeydownListener,
  addDocumentMouseDownListener,
  addDocumentScrollListener,
  addWindowResizeListener,
  isInsideTarget,
  onEscapeDismiss,
  onPointerDismiss,
  onScrollDismiss,
  onResizeDismiss,
}: TimeInputDropdownDismissRuntimeDeps): () => void {
  return installAnchoredPopupDismissRuntime({
    addDocumentKeydownListener,
    addDocumentMouseDownListener,
    addDocumentScrollListener,
    addWindowResizeListener,
    isInsideTarget,
    onEscapeDismiss,
    onPointerDismiss,
    onScrollDismiss,
    onResizeDismiss,
  });
}

export function createBrowserTimeInputDropdownDismissRuntimeDeps({
  onEscapeDismiss,
  onPointerDismiss,
  onScrollDismiss,
  onResizeDismiss,
  ...deps
}: BrowserTimeInputDropdownDismissRuntimeDeps): TimeInputDropdownDismissRuntimeDeps {
  const anchoredDeps = createBrowserAnchoredPopupDismissRuntimeDeps({
    ...deps,
    listenForEscape: true,
    listenForScroll: true,
    listenForResize: true,
    keydownCapture: true,
    onEscapeDismiss,
    onPointerDismiss,
    onScrollDismiss,
    onResizeDismiss,
  });
  return {
    addDocumentKeydownListener: anchoredDeps.addDocumentKeydownListener ?? null,
    addDocumentMouseDownListener: anchoredDeps.addDocumentMouseDownListener,
    addDocumentScrollListener: anchoredDeps.addDocumentScrollListener ?? null,
    addWindowResizeListener: anchoredDeps.addWindowResizeListener ?? null,
    isInsideTarget: anchoredDeps.isInsideTarget,
    onEscapeDismiss,
    onPointerDismiss,
    onScrollDismiss,
    onResizeDismiss,
  };
}
