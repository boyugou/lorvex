import { useI18n } from '@/lib/i18n';
import { CheckIcon } from '../ui/icons';
import { ListViewSkeleton } from '../ui/SkeletonShimmer';

// ---------------------------------------------------------------------------
// ListViewLoadError
// ---------------------------------------------------------------------------

interface ListViewLoadErrorProps {
  onRetryLoad: () => void;
  onBack?: (() => void) | undefined;
}

export function ListViewLoadError({ onRetryLoad, onBack }: ListViewLoadErrorProps): React.JSX.Element {
  const { t } = useI18n();
  return (
    <div className="flex items-center justify-center h-full text-text-muted text-sm">
      <div className="text-center">
        <p>{t('list.loadFailed')}</p>
        <p className="text-xs mt-1">{t('list.loadFailedHint')}</p>
        <button
          type="button"
          onClick={onRetryLoad}
          className="mt-3 px-3 py-1.5 rounded-r-card border border-surface-3 text-text-secondary text-xs hover:bg-surface-3 transition-colors focus-ring-soft"
        >
          {t('common.retry')}
        </button>
        {onBack && (
          <button
            type="button"
            onClick={onBack}
            className="mt-3 px-3 py-1.5 rounded-r-card bg-surface-2 text-text-secondary text-xs hover:bg-surface-3 transition-colors focus-ring-soft"
          >
            {t('common.back')}
          </button>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// LoadingState
// ---------------------------------------------------------------------------

export function LoadingState(): React.JSX.Element {
  return (
    <div className="h-full">
      <ListViewSkeleton />
    </div>
  );
}

// ---------------------------------------------------------------------------
// EmptyList
// ---------------------------------------------------------------------------

interface EmptyListProps {
  listName: string;
  onFocusInput: () => void;
}

export function EmptyList({ listName, onFocusInput }: EmptyListProps): React.JSX.Element {
  const { t } = useI18n();
  return (
    <button
      type="button"
      className="w-full flex flex-col items-center justify-center py-16 text-center cursor-text bg-transparent rounded-r-card focus-ring-soft"
      onClick={onFocusInput}
    >
      <p className="mb-4"><CheckIcon className="w-8 h-8 text-text-primary mx-auto" /></p>
      <p className="text-text-secondary text-sm">
        {listName} {t('list.isClear')}
      </p>
      <p className="text-text-muted text-xs mt-1">{t('list.emptyHint')}</p>
    </button>
  );
}
