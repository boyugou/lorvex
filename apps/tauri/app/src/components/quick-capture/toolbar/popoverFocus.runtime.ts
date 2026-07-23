export interface QuickCapturePopoverFocusHost {
  requestAnimationFrame: (callback: FrameRequestCallback) => number;
  cancelAnimationFrame: (handle: number) => void;
}

interface FocusableTrigger {
  focus: () => void;
}

export function createBrowserQuickCapturePopoverFocusHost(): QuickCapturePopoverFocusHost {
  return {
    requestAnimationFrame: (callback) => {
      if (typeof window === 'undefined') {
        callback(0);
        return 0;
      }
      return window.requestAnimationFrame(callback);
    },
    cancelAnimationFrame: (handle) => {
      if (typeof window === 'undefined') return;
      window.cancelAnimationFrame(handle);
    },
  };
}

export function restoreQuickCapturePopoverTriggerFocus(
  host: QuickCapturePopoverFocusHost,
  getTrigger: () => FocusableTrigger | null,
): () => void {
  const handle = host.requestAnimationFrame(() => {
    getTrigger()?.focus();
  });
  return () => host.cancelAnimationFrame(handle);
}
