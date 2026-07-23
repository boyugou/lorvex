import { useCallback, useEffect } from 'react';
import { resolveMainWindowShortcutAction } from './useMainWindowShortcuts.runtime';

interface UseMainWindowShortcutsOptions {
  closeCommandPalette: (expectedSessionId?: number) => void;
  usesMobileLayout: boolean;
  selectedTaskId: string | null;
  setSelectedTaskId: (taskId: string | null) => void;
  showCapture: boolean;
  showPalette: boolean;
}

/**
 * Handles keyboard shortcuts that have no menu accelerator equivalent.
 * Most shortcuts (Cmd+1-7, Cmd+N, Cmd+K, Shift+Cmd+F) are now handled
 * natively by macOS menu accelerators in app_menu.rs.
 */
export function useMainWindowShortcuts({
  closeCommandPalette,
  usesMobileLayout,
  selectedTaskId,
  setSelectedTaskId,
  showCapture,
  showPalette,
}: UseMainWindowShortcutsOptions) {
  const handleKeyDown = useCallback((event: KeyboardEvent) => {
    if (event.key !== 'Escape') return;
    queueMicrotask(() => {
      switch (resolveMainWindowShortcutAction(event, {
        selectedTaskId,
        showCapture,
        showPalette,
        usesMobileLayout,
      })) {
        case 'close-command-palette':
          closeCommandPalette();
          return;
        case 'clear-selected-task':
          setSelectedTaskId(null);
          return;
        case 'none':
          return;
      }
    });
  }, [
    closeCommandPalette,
    usesMobileLayout,
    selectedTaskId,
    setSelectedTaskId,
    showCapture,
    showPalette,
  ]);

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [handleKeyDown]);
}
