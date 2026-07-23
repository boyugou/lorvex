import { useEffect, useRef } from 'react';
import { listen } from '@tauri-apps/api/event';

import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import { checkForUpdate } from '@/lib/ipc/runtime';
import { createAsyncTauriListenerScope } from '@/lib/tauriListenerLifecycle';
import { toast } from '@/lib/notifications/toast';
import type { View } from '@/lib/types';
import { resolveMenuDataView, resolveMenuView } from './useMenuEvents.logic';

interface UseMenuEventsOptions {
  closeCommandPalette: () => void;
  closeQuickCapture: () => void;
  navigateToView: (target: View) => View;
  openCommandPalette: () => void;
  openQuickCapture: () => void;
  showCapture: boolean;
  showPalette: boolean;
}

export function useMenuEvents({
  closeCommandPalette,
  closeQuickCapture,
  navigateToView,
  openCommandPalette,
  openQuickCapture,
  showCapture,
  showPalette,
}: UseMenuEventsOptions) {
  const { t } = useI18n();
  // Use refs so event listeners always see current state
  const showPaletteRef = useRef(showPalette);
  showPaletteRef.current = showPalette;
  const showCaptureRef = useRef(showCapture);
  showCaptureRef.current = showCapture;
  const tRef = useRef(t);
  tRef.current = t;

  useEffect(() => {
    let cancelled = false;
    const listeners = createAsyncTauriListenerScope();

    const addListener = <T = unknown>(
      event: string,
      handler: (payload: T) => void,
      label: string,
    ) => {
      listeners.add(
        listen<T>(event, (e) => {
          if (!cancelled) handler(e.payload);
        }),
        (error) => {
          reportClientError(`menu.${label}`, `Failed to listen ${event}`, error);
        },
      );
    };

    addListener<string>('menu://navigate', (viewType) => {
      const target = resolveMenuView(viewType);
      if (target) navigateToView(target);
    }, 'navigate');

    addListener('menu://quick-capture', () => {
      if (showCaptureRef.current) closeQuickCapture();
      else openQuickCapture();
    }, 'quickCapture');

    addListener('menu://command-palette', () => {
      if (showPaletteRef.current) closeCommandPalette();
      else openCommandPalette();
    }, 'commandPalette');

    addListener('menu://export-data', () => {
      navigateToView(resolveMenuDataView());
    }, 'exportData');

    addListener('menu://import-data', () => {
      navigateToView(resolveMenuDataView());
    }, 'importData');

    addListener('menu://check-updates', () => {
      // surface an offline-specific message instead of
      // the generic "Could not check" after ~20 s (the new Rust-side
      // timeout) when the browser already knows we're offline.
      if (typeof navigator !== 'undefined' && navigator.onLine === false) {
        toast.error(tRef.current('updates.offline'));
        return;
      }
      toast.info(tRef.current('updates.checking'));
      checkForUpdate()
        .then((version) => {
          if (version) {
            toast.success(`${tRef.current('updates.available')}: v${version}`, {
              label: tRef.current('updates.view'),
              onClick: () => {
                navigateToView({ type: 'settings' });
              },
            });
          } else {
            toast.success(tRef.current('updates.upToDate'));
          }
        })
        .catch((error: unknown) => {
          // the updater endpoint returns concrete reasons
          // (signature mismatch, manifest unreachable, SSL failure);
          // surface them so the user can distinguish transient network
          // issues from configuration problems that need reporting.
          toast.errorWithDetail(error, tRef.current('updates.checkFailed'));
        });
    }, 'checkUpdates');

    return () => {
      cancelled = true;
      listeners.dispose();
    };
  }, [closeCommandPalette, closeQuickCapture, navigateToView, openCommandPalette, openQuickCapture]);
}
