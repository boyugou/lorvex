import type { ReactNode } from 'react';

import { useI18n } from '@/lib/i18n';
import { SearchIcon, WarningIcon } from '../ui/icons';
import ModuleStatePanel from '../ui/ModuleStatePanel';

interface BoardEmptyState {
  /** Icon for the empty/no-match panel. */
  icon: ReactNode;
  /** Headline shown when the board has zero rows. */
  title: string;
  /** Optional subtitle below the title. */
  subtitle?: string | undefined;
  /** Optional reset-filters action label. */
  actionLabel?: string | undefined;
  /** Optional reset-filters handler. */
  onAction?: (() => void) | undefined;
}

interface TaskBoardBodyStateProps {
  isLoading: boolean;
  isError: boolean;
  hasAnyData: boolean;
  /** True when filters/search are active and they hide all rows. */
  isNoMatch?: boolean | undefined;
  /** Skeleton shown while `isLoading && !hasAnyData`. */
  loading?: ReactNode | undefined;
  /** Error retry callback (used for the full-screen error panel). */
  onRetry: () => void;
  /** Localized error title; falls back to `common.loadFailed`. */
  errorTitle?: string | undefined;
  /** Localized error subtitle; falls back to `common.loadFailedHint`. */
  errorSubtitle?: string | undefined;
  /** Empty-state copy + optional icon override (used when `!hasAnyData`). */
  empty?: BoardEmptyState | undefined;
  /** Filtered-but-no-match state copy. */
  noMatch?: BoardEmptyState | undefined;
  /** The board itself, rendered when there is data to show. */
  children: ReactNode;
}

/**
 * Body-state cascade shared by the four task-list-shaped views
 * (AllTasks, Upcoming, Eisenhower, Kanban).
 *
 * every view rolled the same five-branch ladder by hand:
 *
 *   loading                 → skeleton or `ModuleStatePanel(loading)`
 *   error & no cached data  → full-screen error panel with retry
 *   filter active & no rows → "no match" panel
 *   no rows                 → empty panel
 *   otherwise               → render children
 *
 * The branches drifted on title strings, retry button copy, and
 * which icon paired with which state. Centralizing the cascade
 * locks the contract once and lets future polish (icons, animations,
 * focus management on retry) land everywhere in one place.
 *
 * Returns the children directly when there is data to display, so
 * the primitive doesn't add a wrapper element to the DOM in the
 * common case — each view keeps its own scroll container.
 */
export function TaskBoardBodyState({
  isLoading,
  isError,
  hasAnyData,
  isNoMatch,
  loading,
  onRetry,
  errorTitle,
  errorSubtitle,
  empty,
  noMatch,
  children,
}: TaskBoardBodyStateProps) {
  const { t } = useI18n();

  if (isLoading) {
    return <>{loading ?? <ModuleStatePanel variant="loading" />}</>;
  }

  if (isError && !hasAnyData) {
    return (
      <ModuleStatePanel
        variant="error"
        icon={<WarningIcon className="w-9 h-9" />}
        title={errorTitle ?? t('common.loadFailed')}
        subtitle={errorSubtitle ?? t('common.loadFailedHint')}
        actionLabel={t('error.tryAgain')}
        onAction={onRetry}
      />
    );
  }

  if (isNoMatch && noMatch) {
    return (
      <ModuleStatePanel
        icon={noMatch.icon ?? <SearchIcon className="w-9 h-9" />}
        title={noMatch.title}
        subtitle={noMatch.subtitle}
        {...(noMatch.actionLabel && noMatch.onAction
          ? { actionLabel: noMatch.actionLabel, onAction: noMatch.onAction }
          : {})}
      />
    );
  }

  if (!hasAnyData && empty) {
    return (
      <ModuleStatePanel
        icon={empty.icon}
        title={empty.title}
        subtitle={empty.subtitle}
        {...(empty.actionLabel && empty.onAction
          ? { actionLabel: empty.actionLabel, onAction: empty.onAction }
          : {})}
      />
    );
  }

  return <>{children}</>;
}
