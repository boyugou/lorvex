import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { getDeviceState } from '@/lib/ipc/settings';
import { getOverview } from '@/lib/ipc/tasks/reviews';
import { useI18n } from '@/lib/i18n';
import { useMcpServerStatus } from '@/lib/hooks/useMcpServerStatus';
import {
  DEV_NOTIFICATION_PERMISSION_GRANTED,
  DEV_ONBOARDING_DISMISSED,
  DEV_ONBOARDING_PREVIOUSLY_DONE,
  PREF_SYNC_BACKEND_KIND,
} from '@/lib/preferences/keys';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { writeDeviceStateWithQueryUpdate } from '@/lib/query/deviceState';
import { usePreference } from '@/lib/query/usePreference';
import { parseString } from '@/lib/query/usePreference.logic';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { reportClientError } from '@/lib/errors/errorLogging';
import type { View } from '@/lib/types';
import { CheckIcon, SparkleIcon } from '../ui/icons';

import {
  ONBOARDING_STEP_META,
  buildPreviouslyDoneState,
  computeOnboardingProgress,
  parsePreviouslyDoneState,
  serializePreviouslyDoneState,
  shouldShowOnboardingChecklist,
  type OnboardingProgress,
  type OnboardingStepMeta,
  type OnboardingStepState,
} from './onboardingProgress.logic';

interface OnboardingChecklistProps {
  onNavigate: (view: View) => void;
  onQuickCapture: () => void;
  forceOpen?: boolean;
  /** Optional callback fired when the user clicks "Hide for now". */
  onDismissed?: (() => void) | undefined;
}

/**
 * sidebar onboarding checklist that scaffolds the
 * multi-step setup the original WelcomeView could only describe in
 * static prose. Renders directly under the sidebar header so it sits
 * above the list section without taking the prime "first paint" pixel
 * the primary-nav rows occupy.
 *
 * The component is intentionally chatty (icon, gradient, animated check
 * marks) per CLAUDE.md core rule #8 ("UI/UX quality over code
 * minimalism"). The checklist is the user's first moment of agency
 * after dismissing Welcome — a spartan card here would feel lifeless.
 */
export default function OnboardingChecklist({
  onNavigate,
  onQuickCapture,
  forceOpen = false,
  onDismissed,
}: OnboardingChecklistProps): React.JSX.Element | null {
  const { t, format } = useI18n();
  const queryClient = useQueryClient();

  const mcpStatus = useMcpServerStatus();

  const { value: syncBackendKind } = usePreference(
    PREF_SYNC_BACKEND_KIND,
    parseString(''),
    { staleTime: STALE_DEFAULT },
  );

  const { data: notificationsGrantedRaw = null } = useQuery({
    queryKey: QUERY_KEYS.deviceState(DEV_NOTIFICATION_PERMISSION_GRANTED),
    queryFn: ({ signal }) => getDeviceState(DEV_NOTIFICATION_PERMISSION_GRANTED, signal),
    staleTime: STALE_DEFAULT,
  });

  const { data: dismissedRaw = null } = useQuery({
    queryKey: QUERY_KEYS.deviceState(DEV_ONBOARDING_DISMISSED),
    queryFn: ({ signal }) => getDeviceState(DEV_ONBOARDING_DISMISSED, signal),
    staleTime: STALE_DEFAULT,
  });

  const { data: previouslyDoneRaw = null } = useQuery({
    queryKey: QUERY_KEYS.deviceState(DEV_ONBOARDING_PREVIOUSLY_DONE),
    queryFn: ({ signal }) => getDeviceState(DEV_ONBOARDING_PREVIOUSLY_DONE, signal),
    staleTime: STALE_DEFAULT,
  });

  // We use the same overview query the sidebar already fires. Treat as
  // "no tasks yet" when the data hasn't loaded — the row will flip to
  // "done" as soon as the count comes back > 0.
  const { data: overview } = useQuery({
    queryKey: QUERY_KEYS.overview(),
    queryFn: ({ signal }) => getOverview(signal),
    staleTime: STALE_DEFAULT,
  });
  const hasAnyTask = useMemo(() => {
    if (!overview) return false;
    const stats = overview.stats;
    return (stats.open_count ?? 0) > 0 || (stats.completed_today ?? 0) > 0
      || (stats.completed_this_week ?? 0) > 0
      || (stats.completed_last_week ?? 0) > 0
      || (stats.someday_count ?? 0) > 0;
  }, [overview]);

  const previouslyDone = useMemo(
    () => parsePreviouslyDoneState(previouslyDoneRaw ?? null),
    [previouslyDoneRaw],
  );

  const progress = useMemo<OnboardingProgress>(
    () => computeOnboardingProgress(
      {
        mcpResolved: mcpStatus?.resolved ?? null,
        syncBackendKind,
        hasAnyTask,
        notificationsGranted: notificationsGrantedRaw === 'true',
      },
      previouslyDone,
    ),
    [
      mcpStatus,
      syncBackendKind,
      hasAnyTask,
      notificationsGrantedRaw,
      previouslyDone,
    ],
  );

  // Persist the cumulative done-set so we can detect regression next
  // launch. Run on every progress change but de-dup against the last
  // serialization to avoid hammering the IPC layer when, e.g., react
  // query refetches return identical data.
  const lastSerializedRef = useRef<string | null>(null);
  useEffect(() => {
    const nextPreviouslyDone = buildPreviouslyDoneState(progress, previouslyDone);
    const serialized = serializePreviouslyDoneState(progress, previouslyDone);
    if (serialized === lastSerializedRef.current) return;
    lastSerializedRef.current = serialized;
    void (async () => {
      try {
        await writeDeviceStateWithQueryUpdate({
          key: DEV_ONBOARDING_PREVIOUSLY_DONE,
          queryClient,
          value: nextPreviouslyDone,
        });
      } catch (error) {
        reportClientError(
          'onboarding.persistDone',
          'Failed to persist onboarding done-set',
          error,
        );
      }
    })();
  }, [progress, previouslyDone, queryClient]);

  const dismissed = dismissedRaw === 'true';
  const visible = forceOpen || shouldShowOnboardingChecklist(progress, dismissed);

  const handleDismiss = useCallback(() => {
    void (async () => {
      try {
        await writeDeviceStateWithQueryUpdate({
          key: DEV_ONBOARDING_DISMISSED,
          queryClient,
          value: true,
        });
        onDismissed?.();
      } catch (error) {
        reportClientError(
          'onboarding.dismiss',
          'Failed to persist onboarding dismissal',
          error,
        );
      }
    })();
  }, [queryClient, onDismissed]);

  const handleStepAction = useCallback(
    (meta: OnboardingStepMeta) => {
      switch (meta.action.kind) {
        case 'settings':
          onNavigate({ type: 'settings', sectionId: meta.action.sectionId });
          break;
        case 'quickCapture':
          onQuickCapture();
          break;
      }
    },
    [onNavigate, onQuickCapture],
  );

  if (!visible) return null;

  return (
    <div
      role="region"
      aria-label={t('onboarding.checklistAria')}
      data-testid="onboarding-checklist"
      className="mx-3 my-2.5 rounded-r-card border border-accent/25 bg-gradient-to-br from-[var(--accent-tint-xxs)] via-surface-2/80 to-surface-2/60 shadow-[var(--shadow-tooltip)] overflow-hidden animate-[fade-in_0.18s_ease-out]"
    >
      <ChecklistHeader
        completed={progress.completed}
        total={progress.total}
        onDismiss={handleDismiss}
        format={format}
        t={t}
      />

      <ul className="px-2.5 py-1.5 space-y-0.5">
        {progress.steps.map((step) => (
          <ChecklistRow
            key={step.id}
            step={step}
            meta={ONBOARDING_STEP_META[step.id]}
            onAction={handleStepAction}
            t={t}
          />
        ))}
      </ul>

      {progress.hasRegression && (
        <p className="px-4 pb-3 pt-0.5 text-2xs text-warning/90 leading-snug">
          {t('onboarding.regressionHint')}
        </p>
      )}
    </div>
  );
}

interface ChecklistHeaderProps {
  completed: number;
  total: number;
  onDismiss: () => void;
  format: ReturnType<typeof useI18n>['format'];
  t: ReturnType<typeof useI18n>['t'];
}

function ChecklistHeader({
  completed,
  total,
  onDismiss,
  format,
  t,
}: ChecklistHeaderProps): React.JSX.Element {
  const pct = total > 0 ? Math.round((completed / total) * 100) : 0;
  const allDone = completed === total;
  return (
    <div className="px-4 pt-3 pb-2">
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 min-w-0">
          <SparkleIcon className="w-3.5 h-3.5 text-accent shrink-0" />
          <h3 className="text-13 font-semibold text-text-primary truncate">
            {t('onboarding.checklistTitle')}
          </h3>
        </div>
        <button
          type="button"
          onClick={onDismiss}
          aria-label={t('onboarding.dismiss')}
          className="text-3xs text-text-muted hover:text-text-secondary px-1.5 py-0.5 rounded-r-control hover:bg-surface-3/60 transition-colors focus-ring-soft"
        >
          {t('onboarding.dismiss')}
        </button>
      </div>

      <div className="mt-2 flex items-center gap-2">
        <div
          role="progressbar"
          aria-valuenow={completed}
          aria-valuemin={0}
          aria-valuemax={total}
          aria-label={t('onboarding.checklistTitle')}
          className="flex-1 h-1 rounded-full bg-surface-3/70 overflow-hidden"
        >
          <div
            className={`progress-fill h-full rounded-full transition-[transform,background-color] duration-500 ease-out ${
              allDone ? 'bg-success' : 'bg-accent/80'
            }`}
            style={{ transform: `scaleX(${pct / 100})` }}
          />
        </div>
        <span className="text-3xs tabular-nums shrink-0 font-medium text-text-muted">
          {format('onboarding.progressLabel', { completed, total })}
        </span>
      </div>
    </div>
  );
}

interface ChecklistRowProps {
  step: OnboardingStepState;
  meta: OnboardingStepMeta;
  onAction: (meta: OnboardingStepMeta) => void;
  t: ReturnType<typeof useI18n>['t'];
}

function ChecklistRow({ step, meta, onAction, t }: ChecklistRowProps): React.JSX.Element {
  const [hintShown, setHintShown] = useState(false);
  const toggleHint = useCallback(() => setHintShown((prev) => !prev), []);

  return (
    <li
      data-testid={`onboarding-step-${step.id}`}
      data-step-done={step.done ? 'true' : 'false'}
      data-step-regressed={step.regressed ? 'true' : 'false'}
      className={`group rounded-r-card px-2 py-1.5 transition-colors ${
        step.done ? 'opacity-70' : 'hover:bg-surface-3/40'
      }`}
    >
      <div className="flex items-center gap-2">
        <span
          aria-hidden="true"
          className={`flex h-4 w-4 shrink-0 items-center justify-center rounded-full border transition-[color,background-color,border-color] duration-200 ${
            step.done
              ? 'tonal-surface-success-sm text-success'
              : step.regressed
              ? 'tonal-surface-warning-sm text-warning'
              : 'bg-surface-1 border-surface-3 text-text-muted'
          }`}
        >
          {step.done ? (
            <CheckIcon className="w-2.5 h-2.5" />
          ) : (
            <span className="block w-1 h-1 rounded-full bg-current opacity-70" />
          )}
        </span>
        <button
          type="button"
          onClick={toggleHint}
          className={`flex-1 min-w-0 text-start text-xs truncate transition-colors focus-ring-soft rounded-r-control ${
            step.done
              ? 'text-text-muted line-through decoration-text-muted/40'
              : 'text-text-primary hover:text-text-secondary'
          }`}
          aria-expanded={hintShown}
          aria-controls={`onboarding-hint-${step.id}`}
        >
          {t(meta.titleKey)}
        </button>
        {!step.done && (
          <button
            type="button"
            onClick={() => onAction(meta)}
            className="shrink-0 text-3xs font-medium text-accent hover:text-accent/80 hover:bg-accent/10 px-1.5 py-0.5 rounded-r-control transition-colors focus-ring-soft"
          >
            {t(meta.actionKey)}
          </button>
        )}
      </div>
      <p
        id={`onboarding-hint-${step.id}`}
        hidden={!hintShown}
        className="ms-6 mt-1 text-2xs leading-snug text-text-muted"
      >
        {t(meta.hintKey)}
      </p>
    </li>
  );
}
