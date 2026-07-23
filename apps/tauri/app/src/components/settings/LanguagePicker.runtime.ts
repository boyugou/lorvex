import {
  createBrowserAnchoredPopupDismissRuntimeDeps,
  installAnchoredPopupDismissRuntime,
  resolveAnchoredPopupPosition,
  shouldDismissAnchoredPopupFromTarget,
  type BrowserAnchoredPopupDismissRuntimeDeps,
} from '../ui/portalDropdown.runtime';

interface LanguagePickerDropdownPosition {
  top: number;
  left: number;
}

interface LanguagePickerTriggerRect {
  top: number;
  left: number;
  bottom: number;
}

interface LanguagePickerDropdownPositionOptions {
  viewportWidth: number;
  viewportHeight: number;
  dropdownWidth?: number | undefined;
  dropdownHeight?: number | undefined;
  verticalMargin?: number | undefined;
  gap?: number | undefined;
}

interface LanguagePickerDismissRuntimeDeps {
  addDocumentMouseDownListener:
    | ((listener: (event: MouseEvent) => void) => () => void)
    | null;
  addDocumentScrollListener:
    | ((listener: (event: Event) => void) => () => void)
    | null;
  isInsideTarget: (target: EventTarget | null) => boolean;
  onDismiss: () => void;
}

type BrowserLanguagePickerDismissRuntimeDeps = Omit<
  BrowserAnchoredPopupDismissRuntimeDeps,
  'listenForEscape' | 'listenForScroll' | 'onEscapeDismiss' | 'onPointerDismiss' | 'onScrollDismiss'
> & {
  onDismiss: () => void;
};

interface LanguagePickerDeferredFocusRuntimeDeps {
  setTimeout: (callback: () => void, delayMs: number) => unknown;
  clearTimeout: (handle: unknown) => void;
  focusSearchInput: () => void;
}

const DEFAULT_DROPDOWN_HEIGHT_PX = 280;
// Mirrors the LanguagePicker panel's Tailwind `w-52` width.
const DEFAULT_DROPDOWN_WIDTH_PX = 208;
const DEFAULT_VERTICAL_MARGIN_PX = 12;
const DEFAULT_GAP_PX = 6;

export function resolveLanguagePickerDropdownPosition(
  rect: LanguagePickerTriggerRect,
  {
    viewportWidth,
    viewportHeight,
    dropdownWidth = DEFAULT_DROPDOWN_WIDTH_PX,
    dropdownHeight = DEFAULT_DROPDOWN_HEIGHT_PX,
    verticalMargin = DEFAULT_VERTICAL_MARGIN_PX,
    gap = DEFAULT_GAP_PX,
  }: LanguagePickerDropdownPositionOptions,
): LanguagePickerDropdownPosition {
  return resolveAnchoredPopupPosition({
    rect,
    viewportWidth,
    viewportHeight,
    popupWidth: dropdownWidth,
    popupHeight: dropdownHeight,
    verticalMargin,
    gap,
    flipVertically: true,
  });
}

export function shouldDismissLanguagePickerFromPointerTarget(
  target: EventTarget | null,
  isInsideTarget: (target: EventTarget | null) => boolean,
): boolean {
  return shouldDismissAnchoredPopupFromTarget(target, isInsideTarget);
}

export function shouldDismissLanguagePickerFromScrollTarget(
  target: EventTarget | null,
  isInsideTarget: (target: EventTarget | null) => boolean,
): boolean {
  return shouldDismissAnchoredPopupFromTarget(target, isInsideTarget);
}

export function installLanguagePickerDismissRuntime({
  addDocumentMouseDownListener,
  addDocumentScrollListener,
  isInsideTarget,
  onDismiss,
}: LanguagePickerDismissRuntimeDeps): () => void {
  return installAnchoredPopupDismissRuntime({
    addDocumentMouseDownListener,
    addDocumentScrollListener,
    isInsideTarget,
    onPointerDismiss: onDismiss,
    onScrollDismiss: onDismiss,
  });
}

export function createBrowserLanguagePickerDismissRuntimeDeps({
  onDismiss,
  ...deps
}: BrowserLanguagePickerDismissRuntimeDeps): LanguagePickerDismissRuntimeDeps {
  const anchoredDeps = createBrowserAnchoredPopupDismissRuntimeDeps({
    ...deps,
    listenForScroll: true,
    onPointerDismiss: onDismiss,
    onScrollDismiss: onDismiss,
  });
  return {
    addDocumentMouseDownListener: anchoredDeps.addDocumentMouseDownListener,
    addDocumentScrollListener: anchoredDeps.addDocumentScrollListener ?? null,
    isInsideTarget: anchoredDeps.isInsideTarget,
    onDismiss,
  };
}

export function createBrowserLanguagePickerDeferredFocusTimerHost(): Pick<
  LanguagePickerDeferredFocusRuntimeDeps,
  'clearTimeout' | 'setTimeout'
> {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function scheduleLanguagePickerSearchFocusRuntime({
  setTimeout,
  clearTimeout,
  focusSearchInput,
}: LanguagePickerDeferredFocusRuntimeDeps): () => void {
  const handle = setTimeout(focusSearchInput, 0);
  return () => clearTimeout(handle);
}

export function getNextLanguagePickerFocusIndex(
  key: string,
  focusedIndex: number,
  optionCount: number,
): number {
  if (optionCount <= 0) return -1;
  if (key === 'ArrowDown') return Math.min(focusedIndex + 1, optionCount - 1);
  if (key === 'ArrowUp') return Math.max(focusedIndex - 1, 0);
  if (key === 'Home') return 0;
  if (key === 'End') return optionCount - 1;
  return focusedIndex;
}

export function getNextLanguagePickerSearchFocusIndex(
  key: string,
  optionCount: number,
): number {
  if (optionCount <= 0) return -1;
  if (key === 'ArrowDown') return 0;
  if (key === 'ArrowUp') return optionCount - 1;
  return -1;
}
