interface PopoverTaskDeferMenuRect {
  left: number;
  top: number;
  bottom: number;
}

interface PopoverTaskDeferMenuPosition {
  left: number;
  top: number;
}

interface PopoverTaskDeferMenuKeyEventLike {
  key: string;
  isComposing?: boolean | undefined;
  stopPropagation: () => void;
}

interface PopoverTaskDeferMenuDismissRuntimeDeps {
  addWindowMouseDownListener:
    | ((listener: (event: MouseEvent) => void) => () => void)
    | null;
  addWindowKeydownListener:
    | ((listener: (event: KeyboardEvent) => void) => () => void)
    | null;
  isInsideMenuOrTrigger: (target: EventTarget | null) => boolean;
  onDismiss: () => void;
}

const DEFER_MENU_HEIGHT_PX = 60;
const DEFER_MENU_PADDING_PX = 4;

export function resolvePopoverTaskDeferMenuPosition(
  buttonRect: PopoverTaskDeferMenuRect,
  viewportHeight: number,
  menuHeight = DEFER_MENU_HEIGHT_PX,
  padding = DEFER_MENU_PADDING_PX,
): PopoverTaskDeferMenuPosition {
  const spaceBelow = viewportHeight - buttonRect.bottom - padding;
  const top = spaceBelow < menuHeight
    ? buttonRect.top - menuHeight - padding
    : buttonRect.bottom + padding;

  return {
    left: buttonRect.left,
    top: Math.max(padding, top),
  };
}

export function shouldDismissPopoverTaskDeferMenuFromPointerTarget(
  target: EventTarget | null,
  isInsideMenuOrTrigger: (target: EventTarget | null) => boolean,
): boolean {
  return !isInsideMenuOrTrigger(target);
}

export function shouldDismissPopoverTaskDeferMenuFromKeyEvent(
  event: Pick<PopoverTaskDeferMenuKeyEventLike, 'key' | 'isComposing'>,
): boolean {
  return event.key === 'Escape' && !event.isComposing;
}

export function installPopoverTaskDeferMenuDismissRuntime({
  addWindowMouseDownListener,
  addWindowKeydownListener,
  isInsideMenuOrTrigger,
  onDismiss,
}: PopoverTaskDeferMenuDismissRuntimeDeps): () => void {
  const cleanupMouseDown = addWindowMouseDownListener
    ? addWindowMouseDownListener((event) => {
        if (shouldDismissPopoverTaskDeferMenuFromPointerTarget(event.target, isInsideMenuOrTrigger)) {
          onDismiss();
        }
      })
    : () => {};
  const cleanupKeydown = addWindowKeydownListener
    ? addWindowKeydownListener((event) => {
        if (!shouldDismissPopoverTaskDeferMenuFromKeyEvent(event)) return;
        event.stopPropagation();
        onDismiss();
      })
    : () => {};

  return () => {
    cleanupMouseDown();
    cleanupKeydown();
  };
}
