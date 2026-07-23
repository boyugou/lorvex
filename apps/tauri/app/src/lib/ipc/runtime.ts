import { invoke } from './core';

export interface DeepLinkTarget {
  route: 'today' | 'task' | 'quick_capture' | 'search' | 'add_task' | 'complete_task';
  task_id: string | null;
  /** Extra parameters for action-type deep links (add-task, search, etc.). */
  params?: Record<string, string>;
}

export const consumePendingDeepLink = (signal?: AbortSignal): Promise<DeepLinkTarget | null> =>
  invoke('consume_pending_deep_link', undefined, signal);

export const acknowledgePendingDeepLink = (payload: DeepLinkTarget, signal?: AbortSignal): Promise<boolean> =>
  invoke('acknowledge_pending_deep_link', { payload }, signal);

export const openMainQuickCapture = (signal?: AbortSignal): Promise<void> =>
  invoke('open_main_quick_capture', undefined, signal);



export const authenticateBiometrics = (reason: string, signal?: AbortSignal): Promise<boolean> =>
  invoke('authenticate_biometrics', { reason }, signal);

export const checkForUpdate = (signal?: AbortSignal): Promise<string | null> =>
  invoke('check_for_update', undefined, signal);

export const installUpdate = (signal?: AbortSignal): Promise<void> =>
  invoke('install_update', undefined, signal);

/** Reveal the local DB folder in the OS file manager. Paired with the
 *  "Storage is full" toast action button — gives the user a direct path
 *  to the file that triggered ENOSPC so they can inspect / free space.
 *. */
export const revealDbFolder = (signal?: AbortSignal): Promise<void> =>
  invoke('reveal_db_folder', undefined, signal);

/** Try to clear the DiskFull circuit breaker by running a tiny probe
 *  write. Returns `true` if the probe succeeded (writes resume), `false`
 *  if the disk is still full. Used by the "Try again" affordance on
 * the DiskFull toast. */
export const retryDiskFullProbe = (signal?: AbortSignal): Promise<boolean> =>
  invoke('retry_disk_full_probe', undefined, signal);

export const setTrayIconVisibility = (visible: boolean, signal?: AbortSignal): Promise<void> =>
  invoke('set_tray_icon_visibility', { visible }, signal);

export const hidePopoverWindow = (signal?: AbortSignal): Promise<void> =>
  invoke('hide_popover_window', undefined, signal);

export const setBadgeCount = (count: number | null, signal?: AbortSignal): Promise<void> =>
  invoke('set_badge_count', { count }, signal);

export const openMainTaskDetail = (taskId: string, signal?: AbortSignal): Promise<void> =>
  invoke('open_main_task_detail', { task_id: taskId }, signal);

/** Apply native window backdrop effects for the given theme (Mica on Windows, no-op elsewhere). */
export const setNativeWindowEffects = (theme: string, signal?: AbortSignal): Promise<void> =>
  invoke('set_native_window_effects', { theme }, signal);
