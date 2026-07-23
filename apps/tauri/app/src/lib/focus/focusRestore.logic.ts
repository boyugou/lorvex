export interface FocusRestorePolicy<T> {
  isRestorable: (candidate: T) => boolean;
  focus: (candidate: T) => void;
}

export interface FocusRestoreMachine<T> {
  open: (currentActive: T | null) => void;
  snapshot: () => T | null;
  close: () => boolean;
}

export function createFocusRestoreMachine<T>(
  policy: FocusRestorePolicy<T>,
): FocusRestoreMachine<T> {
  let snapshot: T | null = null;
  return {
    open(currentActive) {
      snapshot = currentActive;
    },
    snapshot: () => snapshot,
    close() {
      const target = snapshot;
      snapshot = null;
      if (target === null || target === undefined) return false;
      if (!policy.isRestorable(target)) return false;
      policy.focus(target);
      return true;
    },
  };
}

export function isRestorableHTMLElement(element: HTMLElement): boolean {
  if (!element.isConnected) return false;
  if (typeof element.getClientRects === 'function' && element.getClientRects().length === 0) {
    return false;
  }
  return true;
}

export function createHTMLElementFocusRestoreMachine(): FocusRestoreMachine<HTMLElement> {
  return createFocusRestoreMachine<HTMLElement>({
    isRestorable: isRestorableHTMLElement,
    focus: (element) => {
      element.focus();
    },
  });
}
