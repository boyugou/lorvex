interface PortalDropdownPanelPosition {
  top: number;
  left: number;
}

interface PortalDropdownListboxPosition extends PortalDropdownPanelPosition {
  width: number;
  openUpward: boolean;
}

interface PortalDropdownRect {
  top: number;
  left: number;
  right: number;
  bottom: number;
  width: number;
}

interface AnchoredPopupPosition {
  top: number;
  left: number;
}

interface AnchoredPopupTriggerRect {
  top?: number | undefined;
  left: number;
  right?: number | undefined;
  bottom: number;
}

type AnchoredPopupHorizontalAlign = 'start' | 'end';

interface ResolveAnchoredPopupPositionArgs {
  rect: AnchoredPopupTriggerRect;
  viewportWidth?: number | undefined;
  popupWidth?: number | undefined;
  viewportHeight?: number | undefined;
  popupHeight?: number | undefined;
  viewportPadding?: number | undefined;
  verticalMargin?: number | undefined;
  gap?: number | undefined;
  flipVertically?: boolean | undefined;
  horizontalAlign?: AnchoredPopupHorizontalAlign | undefined;
}

const DEFAULT_VIEWPORT_PADDING_PX = 8;
const DEFAULT_GAP_PX = 4;
const DEFAULT_VERTICAL_MARGIN_PX = 8;
const DEFAULT_MAX_LISTBOX_HEIGHT_PX = 256;
const DEFAULT_MIN_LISTBOX_WIDTH_PX = 120;

export function clampPortalDropdownLeft(
  left: number,
  panelWidth: number,
  viewportWidth: number,
  viewportPaddingPx = DEFAULT_VIEWPORT_PADDING_PX,
): number {
  const minLeft = viewportPaddingPx;
  const maxLeft = Math.max(minLeft, viewportWidth - panelWidth - viewportPaddingPx);
  return Math.min(Math.max(left, minLeft), maxLeft);
}

function shouldOpenAnchoredPopupAbove({
  rect,
  viewportHeight,
  popupHeight,
  verticalMargin,
  flipVertically,
}: {
  rect: AnchoredPopupTriggerRect;
  viewportHeight: number | undefined;
  popupHeight: number | undefined;
  verticalMargin: number;
  flipVertically: boolean;
}): boolean {
  if (!flipVertically || rect.top === undefined) return false;
  if (viewportHeight === undefined || popupHeight === undefined) return false;
  const spaceBelow = viewportHeight - rect.bottom - verticalMargin;
  return spaceBelow < popupHeight && rect.top > popupHeight;
}

function clampAnchoredPopupTop(
  top: number,
  viewportHeight: number | undefined,
  popupHeight: number | undefined,
  viewportPadding: number,
): number {
  if (viewportHeight === undefined || popupHeight === undefined) return top;
  const minTop = viewportPadding;
  const maxTop = Math.max(minTop, viewportHeight - popupHeight - viewportPadding);
  return Math.min(Math.max(top, minTop), maxTop);
}

export function resolveAnchoredPopupPosition({
  rect,
  viewportWidth,
  popupWidth,
  viewportHeight,
  popupHeight,
  viewportPadding = DEFAULT_VIEWPORT_PADDING_PX,
  verticalMargin = DEFAULT_VERTICAL_MARGIN_PX,
  gap = DEFAULT_GAP_PX,
  flipVertically = false,
  horizontalAlign = 'start',
}: ResolveAnchoredPopupPositionArgs): AnchoredPopupPosition {
  const opensAbove = shouldOpenAnchoredPopupAbove({
    rect,
    viewportHeight,
    popupHeight,
    verticalMargin,
    flipVertically,
  });
  const unclampedTop = opensAbove && rect.top !== undefined
    ? rect.top - (popupHeight ?? 0) - gap
    : rect.bottom + gap;

  return {
    top: clampAnchoredPopupTop(unclampedTop, viewportHeight, popupHeight, viewportPadding),
    left: popupWidth === undefined || viewportWidth === undefined
      ? rect.left
      : clampPortalDropdownLeft(
          horizontalAlign === 'end' && rect.right !== undefined
            ? rect.right - popupWidth
            : rect.left,
          popupWidth,
          viewportWidth,
          viewportPadding,
        ),
  };
}

export function resolveFilterDropdownPanelPosition(
  rect: Pick<PortalDropdownRect, 'bottom' | 'left'>,
  viewportWidth: number,
  panelWidth: number,
): PortalDropdownPanelPosition {
  return {
    top: rect.bottom + DEFAULT_GAP_PX,
    left: clampPortalDropdownLeft(rect.left, panelWidth, viewportWidth),
  };
}

export function resolvePortalDropdownListboxPosition(
  rect: PortalDropdownRect,
  viewportWidth: number,
  viewportHeight: number,
  gapPx = DEFAULT_GAP_PX,
  maxListboxHeightPx = DEFAULT_MAX_LISTBOX_HEIGHT_PX,
  minListboxWidthPx = DEFAULT_MIN_LISTBOX_WIDTH_PX,
  viewportPaddingPx = DEFAULT_VIEWPORT_PADDING_PX,
): PortalDropdownListboxPosition {
  const maxWidth = Math.max(minListboxWidthPx, viewportWidth - viewportPaddingPx * 2);
  const width = Math.min(Math.max(rect.width, minListboxWidthPx), maxWidth);
  const spaceBelow = viewportHeight - rect.bottom - gapPx;
  const spaceAbove = rect.top - gapPx;
  const openUpward = spaceBelow < maxListboxHeightPx && spaceAbove > spaceBelow;

  return {
    top: openUpward ? rect.top - gapPx : rect.bottom + gapPx,
    left: clampPortalDropdownLeft(rect.left, width, viewportWidth, viewportPaddingPx),
    width,
    openUpward,
  };
}

type ListenerTarget = Pick<Document, 'addEventListener' | 'removeEventListener'>;
type ResizeTarget = Pick<Window, 'addEventListener' | 'removeEventListener'>;

interface PortalDropdownDismissRuntimeDeps {
  documentTarget?: ListenerTarget | undefined;
  windowTarget?: ResizeTarget | undefined;
  isEventInside: (target: EventTarget | null) => boolean;
  onDismiss: () => void;
}

interface BrowserPortalDropdownDismissRuntimeDeps {
  documentTarget?: ListenerTarget | undefined;
  windowTarget?: ResizeTarget | undefined;
  getTrigger: () => HTMLElement | null;
  getPanel: () => HTMLElement | null;
  nodeConstructor?: typeof Node | undefined;
  onDismiss: () => void;
}

interface AnchoredPopupDismissRuntimeDeps {
  addDocumentPointerDownListener?:
    | ((listener: (event: Event) => void) => () => void)
    | null;
  addDocumentMouseDownListener:
    | ((listener: (event: MouseEvent) => void) => () => void)
    | null;
  addDocumentScrollListener?:
    | ((listener: (event: Event) => void) => () => void)
    | null;
  addDocumentKeydownListener?:
    | ((listener: (event: KeyboardEvent) => void) => () => void)
    | null;
  addWindowResizeListener?:
    | ((listener: (event: Event) => void) => () => void)
    | null;
  isInsideTarget: (target: EventTarget | null) => boolean;
  onPointerDismiss?: (() => void) | undefined;
  onScrollDismiss?: (() => void) | undefined;
  onEscapeDismiss?: (() => void) | undefined;
  onResizeDismiss?: (() => void) | undefined;
}

export interface BrowserAnchoredPopupDismissRuntimeDeps {
  documentTarget?: ListenerTarget | undefined;
  getTrigger: () => HTMLElement | null;
  getPanel: () => HTMLElement | null;
  nodeConstructor?: typeof Node | undefined;
  onPointerDismiss?: (() => void) | undefined;
  onScrollDismiss?: (() => void) | undefined;
  onEscapeDismiss?: (() => void) | undefined;
  onResizeDismiss?: (() => void) | undefined;
  listenForScroll?: boolean | undefined;
  listenForEscape?: boolean | undefined;
  listenForResize?: boolean | undefined;
  keydownCapture?: boolean | undefined;
  pointerEventType?: 'mousedown' | 'pointerdown' | undefined;
  windowTarget?: ResizeTarget | undefined;
}

export function shouldDismissAnchoredPopupFromTarget(
  target: EventTarget | null,
  isInsideTarget: (target: EventTarget | null) => boolean,
): boolean {
  return !isInsideTarget(target);
}

export function shouldDismissAnchoredPopupFromKeyEvent(
  event: Pick<KeyboardEvent, 'isComposing' | 'key'>,
): boolean {
  return event.key === 'Escape' && !event.isComposing;
}

export function installAnchoredPopupDismissRuntime({
  addDocumentPointerDownListener = null,
  addDocumentMouseDownListener,
  addDocumentScrollListener = null,
  addDocumentKeydownListener = null,
  addWindowResizeListener = null,
  isInsideTarget,
  onPointerDismiss,
  onScrollDismiss,
  onEscapeDismiss,
  onResizeDismiss,
}: AnchoredPopupDismissRuntimeDeps): () => void {
  const cleanupPointerDown = addDocumentPointerDownListener
    ? addDocumentPointerDownListener((event) => {
        if (!shouldDismissAnchoredPopupFromTarget(event.target, isInsideTarget)) return;
        onPointerDismiss?.();
      })
    : null;

  const cleanupMouseDown = cleanupPointerDown === null && addDocumentMouseDownListener
    ? addDocumentMouseDownListener((event) => {
        if (!shouldDismissAnchoredPopupFromTarget(event.target, isInsideTarget)) return;
        onPointerDismiss?.();
      })
    : () => {};

  const cleanupScroll = addDocumentScrollListener
    ? addDocumentScrollListener((event) => {
        if (!shouldDismissAnchoredPopupFromTarget(event.target, isInsideTarget)) return;
        onScrollDismiss?.();
      })
    : () => {};

  const cleanupKeydown = addDocumentKeydownListener
    ? addDocumentKeydownListener((event) => {
        if (!shouldDismissAnchoredPopupFromKeyEvent(event)) return;
        event.preventDefault();
        event.stopPropagation();
        onEscapeDismiss?.();
      })
    : () => {};

  const cleanupResize = addWindowResizeListener
    ? addWindowResizeListener(() => {
        onResizeDismiss?.();
      })
    : () => {};

  return () => {
    cleanupPointerDown?.();
    cleanupMouseDown();
    cleanupScroll();
    cleanupKeydown();
    cleanupResize();
  };
}

export function createBrowserAnchoredPopupDismissRuntimeDeps({
  documentTarget = typeof document === 'undefined' ? undefined : document,
  getTrigger,
  getPanel,
  nodeConstructor = typeof Node === 'undefined' ? undefined : Node,
  onPointerDismiss,
  onScrollDismiss,
  onEscapeDismiss,
  onResizeDismiss,
  listenForScroll = false,
  listenForEscape = false,
  listenForResize = false,
  keydownCapture = false,
  pointerEventType = 'mousedown',
  windowTarget = typeof window === 'undefined' ? undefined : window,
}: BrowserAnchoredPopupDismissRuntimeDeps): AnchoredPopupDismissRuntimeDeps {
  return {
    addDocumentPointerDownListener: documentTarget === undefined || pointerEventType !== 'pointerdown'
      ? null
      : (listener) => {
          documentTarget.addEventListener('pointerdown', listener);
          return () => documentTarget.removeEventListener('pointerdown', listener);
        },
    addDocumentMouseDownListener: documentTarget === undefined
      || pointerEventType !== 'mousedown'
      ? null
      : (listener) => {
          documentTarget.addEventListener('mousedown', listener);
          return () => documentTarget.removeEventListener('mousedown', listener);
        },
    addDocumentScrollListener: documentTarget === undefined || !listenForScroll
      ? null
      : (listener) => {
          documentTarget.addEventListener('scroll', listener, { capture: true, passive: true });
          return () => documentTarget.removeEventListener('scroll', listener, true);
        },
    addDocumentKeydownListener: documentTarget === undefined || !listenForEscape
      ? null
      : (listener) => {
          documentTarget.addEventListener('keydown', listener, keydownCapture);
          return () => documentTarget.removeEventListener('keydown', listener, keydownCapture);
        },
    addWindowResizeListener: documentTarget === undefined || windowTarget === undefined || !listenForResize
      ? null
      : (listener) => {
          windowTarget.addEventListener('resize', listener);
          return () => windowTarget.removeEventListener('resize', listener);
        },
    isInsideTarget: (target) => (
      documentTarget !== undefined
      && nodeConstructor !== undefined
      && target instanceof nodeConstructor
      && Boolean(getTrigger()?.contains(target) || getPanel()?.contains(target))
    ),
    onPointerDismiss,
    onScrollDismiss,
    onEscapeDismiss,
    onResizeDismiss,
  };
}

export function startPortalDropdownDismissRuntime({
  documentTarget,
  windowTarget,
  isEventInside,
  onDismiss,
}: PortalDropdownDismissRuntimeDeps): () => void {
  if (!documentTarget) return () => {};
  return installAnchoredPopupDismissRuntime({
    addDocumentPointerDownListener: (listener) => {
      documentTarget.addEventListener('pointerdown', listener);
      return () => documentTarget.removeEventListener('pointerdown', listener);
    },
    addDocumentMouseDownListener: null,
    addDocumentScrollListener: (listener) => {
      documentTarget.addEventListener('scroll', listener, { capture: true, passive: true });
      return () => documentTarget.removeEventListener('scroll', listener, true);
    },
    addWindowResizeListener: windowTarget
      ? (listener) => {
          windowTarget.addEventListener('resize', listener);
          return () => windowTarget.removeEventListener('resize', listener);
        }
      : null,
    isInsideTarget: isEventInside,
    onPointerDismiss: onDismiss,
    onScrollDismiss: onDismiss,
    onResizeDismiss: onDismiss,
  });
}

export function createBrowserPortalDropdownDismissRuntimeDeps({
  documentTarget = typeof document === 'undefined' ? undefined : document,
  windowTarget = typeof window === 'undefined' ? undefined : window,
  getTrigger,
  getPanel,
  nodeConstructor = typeof Node === 'undefined' ? undefined : Node,
  onDismiss,
}: BrowserPortalDropdownDismissRuntimeDeps): PortalDropdownDismissRuntimeDeps {
  return {
    documentTarget,
    windowTarget: documentTarget === undefined ? undefined : windowTarget,
    isEventInside: (target) => (
      documentTarget !== undefined
      && nodeConstructor !== undefined
      && target instanceof nodeConstructor
      && Boolean(getTrigger()?.contains(target) || getPanel()?.contains(target))
    ),
    onDismiss,
  };
}
