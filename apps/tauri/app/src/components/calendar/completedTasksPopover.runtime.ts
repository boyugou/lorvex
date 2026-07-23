export interface CompletedTasksPopoverFocusHost {
  requestAnimationFrame: (callback: FrameRequestCallback) => number;
  cancelAnimationFrame: (handle: number) => void;
}

interface CompletedTasksPopoverRect {
  top: number;
  bottom: number;
  left: number;
  width: number;
}

interface CompletedTasksPopoverSize {
  width: number;
  height: number;
}

interface CompletedTasksPopoverViewport {
  width: number;
  height: number;
}

interface CompletedTasksPopoverPositionArgs {
  triggerRect: CompletedTasksPopoverRect;
  popoverSize: CompletedTasksPopoverSize;
  viewport: CompletedTasksPopoverViewport;
  gap?: number;
  margin?: number;
  maxHeight?: number;
  minWidth?: number;
}

export interface CompletedTasksPopoverPosition {
  top: number;
  left: number;
  width: number;
  maxHeight: number;
  openUpward: boolean;
}

interface FocusableTarget {
  focus: () => void;
}

interface CompletedTasksPopoverInitialFocusArgs {
  panel: FocusableTarget | null;
  firstItem: FocusableTarget | null;
  activeElement: unknown;
  isActiveElementInPanel: (activeElement: unknown) => boolean;
}

type CompletedTasksPopoverInitialFocusTarget =
  | 'none'
  | 'active-element'
  | 'first-item'
  | 'panel';

export function focusCompletedTasksPopoverInitialTarget({
  panel,
  firstItem,
  activeElement,
  isActiveElementInPanel,
}: CompletedTasksPopoverInitialFocusArgs): CompletedTasksPopoverInitialFocusTarget {
  if (!panel) return 'none';
  if (isActiveElementInPanel(activeElement)) return 'active-element';
  if (firstItem) {
    firstItem.focus();
    return 'first-item';
  }
  panel.focus();
  return 'panel';
}

export function shouldDismissCompletedTasksPopoverFromKeyEvent(
  event: { key: string; isComposing?: boolean | undefined },
): boolean {
  return event.key === 'Escape' && !event.isComposing;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

export function computeCompletedTasksPopoverPosition({
  triggerRect,
  popoverSize,
  viewport,
  gap = 4,
  margin = 8,
  maxHeight = 320,
  minWidth = 160,
}: CompletedTasksPopoverPositionArgs): CompletedTasksPopoverPosition {
  const viewportWidth = Math.max(viewport.width, margin * 2);
  const viewportHeight = Math.max(viewport.height, margin * 2);
  const width = Math.min(
    Math.max(triggerRect.width, popoverSize.width, minWidth),
    Math.max(minWidth, viewportWidth - margin * 2),
  );
  const left = clamp(triggerRect.left, margin, viewportWidth - margin - width);
  const availableBelow = viewportHeight - triggerRect.bottom - gap - margin;
  const availableAbove = triggerRect.top - gap - margin;
  const openUpward = availableBelow < Math.min(popoverSize.height, minWidth) && availableAbove > availableBelow;
  const availableHeight = Math.max(0, openUpward ? availableAbove : availableBelow);
  const resolvedMaxHeight = Math.min(popoverSize.height, availableHeight, maxHeight);
  const height = Math.max(0, resolvedMaxHeight);
  const rawTop = openUpward
    ? triggerRect.top - gap - height
    : triggerRect.bottom + gap;
  const top = clamp(rawTop, margin, viewportHeight - margin - height);

  return {
    top,
    left,
    width,
    maxHeight: height,
    openUpward,
  };
}

function scheduleCompletedTasksPopoverFocus(
  host: CompletedTasksPopoverFocusHost,
  getTarget: () => FocusableTarget | null,
): () => void {
  const handle = host.requestAnimationFrame(() => {
    getTarget()?.focus();
  });
  return () => host.cancelAnimationFrame(handle);
}

export function scheduleCompletedTasksPopoverInitialFocus(
  host: CompletedTasksPopoverFocusHost,
  getArgs: () => CompletedTasksPopoverInitialFocusArgs,
): () => void {
  const handle = host.requestAnimationFrame(() => {
    focusCompletedTasksPopoverInitialTarget(getArgs());
  });
  return () => host.cancelAnimationFrame(handle);
}

export function restoreCompletedTasksPopoverTriggerFocus(
  host: CompletedTasksPopoverFocusHost,
  getTrigger: () => FocusableTarget | null,
): () => void {
  return scheduleCompletedTasksPopoverFocus(host, getTrigger);
}
