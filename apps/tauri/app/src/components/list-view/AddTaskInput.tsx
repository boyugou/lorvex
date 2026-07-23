import { MAX_TITLE_LENGTH } from '@lorvex/shared/validation';
import { useI18n } from '@/lib/i18n';
import { isImeComposing } from '@/lib/ime';

import { useListView } from './ListViewContext';

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function AddTaskInput(): React.JSX.Element {
  const { t } = useI18n();
  const { inputRef, draft, adding, onDraftChange, onAdd } = useListView();

  return (
    <div className="flex items-center gap-2 mt-3">
      <div className="w-5 h-5 rounded-full border border-dashed border-surface-3 shrink-0" />
      <input
        ref={node => {
          inputRef.current = node;
        }}
        type="text"
        value={draft}
        onChange={event => onDraftChange(event.target.value)}
        onKeyDown={event => {
          if (event.key === 'Enter' && !isImeComposing(event)) {
            event.preventDefault();
            onAdd();
          }
          if (event.key === 'Escape' && !isImeComposing(event)) {
            onDraftChange('');
            event.currentTarget.blur();
          }
        }}
        maxLength={MAX_TITLE_LENGTH}
        placeholder={t('list.addTask')}
        aria-label={t('list.addTask')}
        disabled={adding}
        className="flex-1 bg-transparent text-sm text-text-primary placeholder:text-text-muted/50 outline-hidden focus-ring-soft py-1 disabled:opacity-50"
      />
      {draft.trim() && (
        <kbd className="text-xs text-text-muted bg-surface-3 px-1.5 py-0.5 rounded-r-control">↵</kbd>
      )}
    </div>
  );
}
