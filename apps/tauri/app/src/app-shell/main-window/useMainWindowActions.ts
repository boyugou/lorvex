import { useCallback } from 'react';
import { getCurrentWindow } from '@tauri-apps/api/window';

import { reportClientError } from '@/lib/errors/errorLogging';

export function useMainWindowActions(usesMobileLayout: boolean) {
  const toggleMainWindowZoom = useCallback(async () => {
    if (usesMobileLayout) return;
    try {
      const win = getCurrentWindow();
      const maximized = await win.isMaximized();
      if (maximized) {
        await win.unmaximize();
      } else {
        await win.maximize();
      }
    } catch (error) {
      reportClientError('app.window.zoom', 'Toggle main window zoom failed', error);
    }
  }, [usesMobileLayout]);

  const startMainWindowDragging = useCallback(() => {
    if (usesMobileLayout) return;
    getCurrentWindow().startDragging().catch((error) => {
      reportClientError('app.window.drag', 'Main window drag failed', error);
    });
  }, [usesMobileLayout]);

  return {
    startMainWindowDragging,
    toggleMainWindowZoom,
  };
}
