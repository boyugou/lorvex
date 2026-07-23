export type TooltipSide = 'top' | 'bottom' | 'left' | 'right';

interface Rect {
  readonly top: number;
  readonly left: number;
  readonly width: number;
  readonly height: number;
}

interface Size {
  readonly width: number;
  readonly height: number;
}

interface TooltipKeyEventLike {
  key: string;
  isComposing?: boolean | undefined;
}

interface TooltipDismissRuntimeDeps {
  addWindowScrollListener: ((listener: () => void) => () => void) | null;
  addWindowResizeListener: ((listener: () => void) => () => void) | null;
  addWindowKeydownListener:
    | ((listener: (event: KeyboardEvent) => void) => () => void)
    | null;
  onDismiss: () => void;
}

export interface TooltipTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

export function createBrowserTooltipTimerHost(): TooltipTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function scheduleTooltipTimer(
  host: TooltipTimerHost,
  callback: () => void,
  delayMs: number,
): unknown {
  return host.setTimeout(callback, delayMs);
}

export function clearTooltipTimer(
  host: TooltipTimerHost,
  handle: unknown,
): void {
  if (handle != null) {
    host.clearTimeout(handle);
  }
}

export function mergeTooltipTriggerDescribedBy(
  existingDescribedBy: string | undefined,
  tooltipId: string | undefined,
): string | undefined {
  const ids = existingDescribedBy
    ?.split(/\s+/)
    .map((id) => id.trim())
    .filter((id) => id.length > 0) ?? [];

  if (tooltipId) {
    ids.push(tooltipId);
  }

  const uniqueIds = [...new Set(ids)];
  return uniqueIds.length > 0 ? uniqueIds.join(' ') : undefined;
}

export function computeTooltipPosition(
  trigger: Rect,
  tooltip: Size,
  viewport: Size,
  side: TooltipSide,
  offset: number,
): { x: number; y: number } {
  const margin = 8;
  let x = 0;
  let y = 0;
  switch (side) {
    case 'top':
      x = trigger.left + trigger.width / 2 - tooltip.width / 2;
      y = trigger.top - tooltip.height - offset;
      break;
    case 'bottom':
      x = trigger.left + trigger.width / 2 - tooltip.width / 2;
      y = trigger.top + trigger.height + offset;
      break;
    case 'left':
      x = trigger.left - tooltip.width - offset;
      y = trigger.top + trigger.height / 2 - tooltip.height / 2;
      break;
    case 'right':
      x = trigger.left + trigger.width + offset;
      y = trigger.top + trigger.height / 2 - tooltip.height / 2;
      break;
  }
  // Clamp into viewport with a small margin on each side.
  const maxX = viewport.width - tooltip.width - margin;
  const maxY = viewport.height - tooltip.height - margin;
  x = Math.min(Math.max(margin, x), Math.max(margin, maxX));
  y = Math.min(Math.max(margin, y), Math.max(margin, maxY));
  return { x, y };
}

export function shouldDismissTooltipFromKeyEvent(event: TooltipKeyEventLike): boolean {
  return event.key === 'Escape' && !event.isComposing;
}

export function installTooltipDismissRuntime({
  addWindowScrollListener,
  addWindowResizeListener,
  addWindowKeydownListener,
  onDismiss,
}: TooltipDismissRuntimeDeps): () => void {
  const cleanupScroll = addWindowScrollListener ? addWindowScrollListener(onDismiss) : () => {};
  const cleanupResize = addWindowResizeListener ? addWindowResizeListener(onDismiss) : () => {};
  const cleanupKeydown = addWindowKeydownListener
    ? addWindowKeydownListener((event) => {
        if (shouldDismissTooltipFromKeyEvent(event)) onDismiss();
      })
    : () => {};

  return () => {
    cleanupScroll();
    cleanupResize();
    cleanupKeydown();
  };
}
