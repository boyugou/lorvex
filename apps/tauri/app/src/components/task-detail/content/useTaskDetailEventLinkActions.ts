import { useI18n } from '@/lib/i18n';
import { linkTaskToEvent, linkTaskToProviderEvent, unlinkTaskFromEvent, unlinkTaskFromProviderEvent } from '@/lib/ipc/calendar';
import type { ProviderEventLinkWithResolution } from '@/lib/ipc/calendar';
import { defineEntityHooks } from '@/lib/query/defineEntityHooks';

// Migrated to `defineEntityHooks`. The entity-keyed `'task_calendar_event_link'`
// invalidation covers `taskEventLinks` + `taskProviderEventLinks` for every task,
// which is a superset of the previous per-`taskId` `invalidateTaskEventLinkQueries`
// — safe (over-invalidation, never under) and removes a per-call-site queryClient
// + toast + reportClientError boilerplate triple per mutation.
const eventLinkHooks = defineEntityHooks({
  entity: 'task_calendar_event_link',
  mutations: {
    linkCanonical: {
      run: (input: { taskId: string; eventId: string }) =>
        linkTaskToEvent(input.taskId, input.eventId),
      errorContext: 'taskDetail.eventLink.linkCanonical',
    },
    unlinkCanonical: {
      run: (input: { taskId: string; eventId: string }) =>
        unlinkTaskFromEvent(input.taskId, input.eventId),
      errorContext: 'taskDetail.eventLink.unlinkCanonical',
    },
    linkProvider: {
      run: (input: {
        taskId: string;
        providerKind: string;
        providerScope: string;
        providerEventKey: string;
      }) =>
        linkTaskToProviderEvent(
          input.taskId,
          input.providerKind,
          input.providerScope,
          input.providerEventKey,
        ),
      errorContext: 'taskDetail.eventLink.linkProvider',
    },
    unlinkProvider: {
      run: (input: { taskId: string; link: ProviderEventLinkWithResolution }) =>
        unlinkTaskFromProviderEvent(
          input.taskId,
          input.link.provider_kind,
          input.link.provider_scope,
          input.link.provider_event_key,
        ),
      errorContext: 'taskDetail.eventLink.unlinkProvider',
    },
  },
});

export function useTaskDetailEventLinkActions(taskId: string) {
  const { t } = useI18n();
  const errorMessage = t('common.error');

  const linkCanonicalMutation = eventLinkHooks.mutations.linkCanonical.useMutation({ errorMessage });
  const unlinkCanonicalMutation = eventLinkHooks.mutations.unlinkCanonical.useMutation({ errorMessage });
  const linkProviderMutation = eventLinkHooks.mutations.linkProvider.useMutation({ errorMessage });
  const unlinkProviderMutation = eventLinkHooks.mutations.unlinkProvider.useMutation({ errorMessage });

  return {
    linkCanonicalEvent: (eventId: string) => {
      linkCanonicalMutation.mutate({ taskId, eventId });
    },
    linkProviderEvent: (providerKind: string, providerScope: string, providerEventKey: string) => {
      linkProviderMutation.mutate({ taskId, providerKind, providerScope, providerEventKey });
    },
    unlinkCanonicalEvent: (eventId: string) => {
      unlinkCanonicalMutation.mutate({ taskId, eventId });
    },
    unlinkProviderEvent: (link: ProviderEventLinkWithResolution) => {
      unlinkProviderMutation.mutate({ taskId, link });
    },
  };
}
