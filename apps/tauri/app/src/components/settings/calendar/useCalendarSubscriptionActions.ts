import { useQueryClient } from '@tanstack/react-query';

import {
  addCalendarSubscription,
  removeCalendarSubscription,
  retryCalendarSubscriptionNow,
  syncCalendarSubscription,
  toggleCalendarSubscription,
  updateCalendarSubscriptionColor,
} from '@/lib/ipc/calendar';
import { defineEntityHooks } from '@/lib/query/defineEntityHooks';
import { invalidateCalendarViewQueries } from '@/lib/query/queryKeys';
import { confirm } from '@/lib/dialogs/confirm';
import { useI18n } from '@/lib/i18n';
import { toast } from '@/lib/notifications/toast';

interface UseCalendarSubscriptionActionsArgs {
  nextAutoColor: string;
  onAddSuccess: () => void;
}

/**
 * Calendar-subscription mutations routed through `defineEntityHooks`
 * with `entity: 'calendar_subscription'`, which fans out to every
 * subscription-aware query head via
 * `QUERY_ENTITY_INVALIDATION_MAP['calendar_subscription']`
 * (= `CALENDAR_SUBSCRIPTION_QUERY_KEY_HEADS`: subscription list +
 * every event-shape head touched by a subscription sync). The color
 * mutation widens the invalidation to also cover calendar tasks via a
 * `successMessage`-free `onSuccess` hook — color affects task tinting
 * outside the subscription head set.
 */
const calendarSubHooks = defineEntityHooks({
  entity: 'calendar_subscription',
  mutations: {
    add: {
      run: ({ name, url, color }: { name: string; url: string; color: string }) =>
        addCalendarSubscription(name, url, color),
      errorContext: 'settings.calendarSub.add',
    },
    remove: {
      run: (id: string) => removeCalendarSubscription(id),
      errorContext: 'settings.calendarSub.remove',
    },
    toggle: {
      run: ({ id, enabled }: { id: string; enabled: boolean }) =>
        toggleCalendarSubscription(id, enabled),
      errorContext: 'settings.calendarSub.toggle',
    },
    color: {
      run: ({ id, color }: { id: string; color: string | null }) =>
        updateCalendarSubscriptionColor(id, color),
      errorContext: 'settings.calendarSub.color',
    },
    sync: {
      run: (id: string) => syncCalendarSubscription(id),
      errorContext: 'settings.calendarSub.sync',
    },
    retryNow: {
      run: (id: string) => retryCalendarSubscriptionNow(id),
      errorContext: 'settings.calendarSub.retryNow',
    },
  },
});

export function useCalendarSubscriptionActions({
  nextAutoColor,
  onAddSuccess,
}: UseCalendarSubscriptionActionsArgs) {
  const { t, format } = useI18n();
  const queryClient = useQueryClient();

  const addMutation = calendarSubHooks.mutations.add.useMutation({
    successMessage: t('settings.calendarSubAdded'),
    errorMessage: t('common.error'),
    onSuccess: () => onAddSuccess(),
  });

  const removeMutation = calendarSubHooks.mutations.remove.useMutation({
    successMessage: t('settings.calendarSubRemoved'),
    errorMessage: t('common.error'),
  });

  const toggleMutation = calendarSubHooks.mutations.toggle.useMutation({
    errorMessage: t('common.error'),
  });

  // Subscription colors also tint linked calendar tasks + today-surface
  // overviews. The default `'calendar_subscription'` invalidation
  // already covers calendarTasks/calendarEvents (via CALENDAR_MUTATION
  // heads), but today-surface heads (overview, currentFocus, todayPool,
  // todayBootstrap, …) sit outside that set — the original site
  // explicitly widened to calendar-view, so preserve that with a
  // post-invalidation hook.
  const colorMutation = calendarSubHooks.mutations.color.useMutation({
    errorMessage: t('common.error'),
    onSuccess: () => invalidateCalendarViewQueries(queryClient),
  });

  const buildSyncToast = (result: Awaited<ReturnType<typeof syncCalendarSubscription>>) => {
    if (result.error) {
      toast.error(format('settings.calendarSubSyncFailed', { 0: result.error ?? '' }));
    } else {
      toast.success(format('settings.calendarSubSyncResult', {
        0: result.subscription_name ?? '',
        1: result.events_imported,
        2: result.events_updated,
        3: result.events_removed,
      }));
    }
  };

  const syncMutation = calendarSubHooks.mutations.sync.useMutation({
    errorMessage: t('common.error'),
    onSuccess: (result) => buildSyncToast(result),
  });

  // "Retry now" bypasses the per-subscription backoff
  // gate and forces a fresh sync for a single feed. Reuses the sync
  // mutation's success/failure toast shape so the UX is consistent
  // with the manual sync button, and always invalidates so the row's
  // `consecutive_failures` / `next_retry_at` refresh after the call.
  const retryNowMutation = calendarSubHooks.mutations.retryNow.useMutation({
    errorMessage: t('common.error'),
    onSuccess: (result) => buildSyncToast(result),
  });

  const handleAddSubscription = (name: string, url: string) => {
    const trimmedName = name.trim();
    const trimmedUrl = url.trim();
    if (!trimmedName || !trimmedUrl) return;
    if (!trimmedUrl.startsWith('https://')) {
      toast.error(t('settings.calendarSubUrlError'));
      return;
    }
    addMutation.mutate({ name: trimmedName, url: trimmedUrl, color: nextAutoColor });
  };

  return {
    addPending: addMutation.isPending,
    colorPending: colorMutation.isPending,
    removePending: removeMutation.isPending,
    syncPending: syncMutation.isPending,
    togglePending: toggleMutation.isPending,
    retryNowPending: retryNowMutation.isPending,
    handleAddSubscription,
    handleColorChange: (id: string, color: string | null) => {
      if (colorMutation.isPending) return;
      colorMutation.mutate({ id, color });
    },
    // Gate removal behind a confirm dialog: the IPC has no undo and
    // the row's events vanish from the calendar on the next refresh.
    // The confirm names the URL so the user can tell two
    // similarly-named feeds apart before pulling the trigger.
    handleRemoveSubscription: async (id: string, url: string) => {
      const ok = await confirm({
        title: t('settings.calendarSubRemoveConfirmTitle'),
        message: format('settings.calendarSubRemoveConfirmMessage', { url }),
        variant: 'danger',
        confirmLabel: t('settings.calendarSubRemoveConfirmAction'),
      });
      if (!ok) return;
      removeMutation.mutate(id);
    },
    handleSyncSubscription: (id: string) => {
      syncMutation.mutate(id);
    },
    handleRetryNow: (id: string) => {
      retryNowMutation.mutate(id);
    },
    handleToggleSubscription: (id: string, enabled: boolean) => {
      if (toggleMutation.isPending) return;
      toggleMutation.mutate({ id, enabled });
    },
  };
}
