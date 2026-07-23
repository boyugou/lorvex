import type { QueryClient } from '@tanstack/react-query';

import type {
  ClearNativeCalendarEventsResult,
  NativeCalendarProviderSource,
} from '@/lib/ipc/calendar';
import type { NativeCalendarSyncSummary } from '@/lib/nativeCalendarRuntime';
import type { TranslationKey, TranslationVars } from '@/locales';
import { invalidateCalendarMutationQueries } from '@/lib/query/queryKeys';

type NativeCalendarPanelToast = {
  errorWithDetail: (error: unknown, fallback: string) => void;
  success: (message: string) => void;
};

type NativeCalendarPanelTranslator = (key: TranslationKey) => string;
type NativeCalendarPanelFormatter = (key: TranslationKey, vars?: TranslationVars) => string;

export function invalidateNativeCalendarPanelMutationQueries(queryClient: QueryClient): void {
  invalidateCalendarMutationQueries(queryClient);
}

export async function syncNativeCalendarPanelNow(args: {
  queryClient: QueryClient;
  setLastResult: (result: NativeCalendarSyncSummary) => void;
  syncNow: () => Promise<NativeCalendarSyncSummary>;
  t: NativeCalendarPanelTranslator;
  format: NativeCalendarPanelFormatter;
  toast: NativeCalendarPanelToast;
}): Promise<void> {
  const { queryClient, setLastResult, syncNow, t, format, toast } = args;
  try {
    const result = await syncNow();
    setLastResult(result);
    if (result.error) {
      toast.errorWithDetail(result.error, t('common.error'));
    } else {
      toast.success(format('settings.nativeCalendarSyncedSummary', {
        imported: result.events_imported,
        updated: result.events_updated,
      }));
    }
    invalidateNativeCalendarPanelMutationQueries(queryClient);
  } catch (error) {
    toast.errorWithDetail(error, t('settings.nativeCalendarFailed'));
  }
}

export async function clearNativeCalendarPanelProviderEvents(args: {
  clearNativeCalendarEvents: (
    source: NativeCalendarProviderSource,
  ) => Promise<ClearNativeCalendarEventsResult>;
  clearProviderKind: NativeCalendarProviderSource;
  queryClient: QueryClient;
  t: NativeCalendarPanelTranslator;
  format: NativeCalendarPanelFormatter;
  toast: NativeCalendarPanelToast;
}): Promise<void> {
  const { clearNativeCalendarEvents, clearProviderKind, queryClient, format, toast } = args;
  try {
    const { deleted } = await clearNativeCalendarEvents(clearProviderKind);
    if (deleted > 0) {
      toast.success(format('settings.nativeCalendarClearedCount', { count: deleted }));
    }
    invalidateNativeCalendarPanelMutationQueries(queryClient);
  } catch {
    // Best effort cleanup only; stale provider events will be replaced on the next sync.
  }
}
