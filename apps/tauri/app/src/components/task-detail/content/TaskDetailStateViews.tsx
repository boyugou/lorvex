import type { ReactNode } from 'react';

import type { TranslationKey } from '@/lib/i18n';
import { TaskDetailSkeleton } from '@/components/ui/SkeletonShimmer';
import { Tooltip } from '@/components/ui/Tooltip';

function TaskDetailStateShell({
  isMobile,
  onClose,
  closeLabel,
  children,
}: {
  isMobile: boolean;
  onClose: () => void;
  closeLabel: string;
  children: ReactNode;
}) {
  return (
    <div className={`h-full flex flex-col bg-surface-1 ${isMobile ? '' : 'border-s border-surface-3'}`}>
      <div
        className={`flex justify-end ${isMobile ? 'px-4' : 'px-6 pt-4'}`}
        style={isMobile ? { paddingTop: 'max(1rem, env(safe-area-inset-top, 1rem))' } : undefined}
      >
        <Tooltip label={closeLabel}>
          <button
            type="button"
            onClick={onClose}
            aria-label={closeLabel}
            className={`text-text-muted hover:text-text-primary text-lg rounded-r-control focus-ring-soft flex items-center justify-center ${isMobile ? 'min-tap' : 'h-7 w-7'}`}
          >
            {/* hide the ×-glyph from AT so SR users
                hear the real `closeLabel` (carried by `aria-label`)
                rather than the literal "multiplication sign" U+00D7. */}
            <span aria-hidden="true">×</span>
          </button>
        </Tooltip>
      </div>
      {children}
    </div>
  );
}

export function TaskDetailLoadingState({
  isMobile,
  onClose,
  t,
}: {
  isMobile: boolean;
  onClose: () => void;
  t: (key: TranslationKey) => string;
}) {
  return (
    <TaskDetailStateShell isMobile={isMobile} onClose={onClose} closeLabel={t('common.close')}>
      <div className="flex-1" role="status" aria-live="polite"><TaskDetailSkeleton /></div>
    </TaskDetailStateShell>
  );
}

export function TaskDetailErrorState({
  isMobile,
  onClose,
  hasError,
  onRetry,
  t,
}: {
  isMobile: boolean;
  onClose: () => void;
  hasError: boolean;
  onRetry: () => void;
  t: (key: TranslationKey) => string;
}) {
  return (
    <TaskDetailStateShell isMobile={isMobile} onClose={onClose} closeLabel={t('common.close')}>
      <div className="flex-1 flex flex-col items-center justify-center gap-3 text-center px-6" role="alert" aria-live="assertive">
        <p className="text-text-secondary text-sm">{hasError ? t('task.loadFailed') : t('task.notFound')}</p>
        <p className="text-text-muted text-xs">{hasError ? t('task.loadFailedHint') : t('task.notFoundHint')}</p>
        {hasError ? (
          <button
            type="button"
            onClick={onRetry}
            className="mt-1 text-xs px-3 py-1.5 rounded-r-control bg-accent text-on-accent active:scale-[0.97] hover:bg-accent/90 transition-colors focus-ring-strong"
          >
            {t('error.tryAgain')}
          </button>
        ) : null}
      </div>
    </TaskDetailStateShell>
  );
}
