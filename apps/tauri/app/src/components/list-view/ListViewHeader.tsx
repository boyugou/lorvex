import { useCallback, useId, useRef } from 'react';
import { MAX_TITLE_LENGTH } from '@lorvex/shared/validation';

import { useI18n } from '@/lib/i18n';
import { isImeComposing } from '@/lib/ime';
import { useCopyToClipboard } from '@/lib/platform/useCopyToClipboard';
import { Tooltip } from '../ui/Tooltip';

import { formatListPlan } from './formatListPlan';
import { useListView } from './ListViewContext';

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function ListViewHeader(): React.JSX.Element {
  const { formatNumber, t } = useI18n();
  const {
    data,
    deleting,
    renaming,
    renameSaving,
    openTasks,
    completedTasks,
    onDeleteList,
    onRename,
    onStartRename,
    onCancelRename,
    selectionMode,
    onSetSelectionMode,
    bulk,
  } = useListView();
  const bulkBusy = bulk.bulkAction !== null;

  const { list } = data;
  const renameInputRef = useRef<HTMLInputElement | null>(null);
  const renameActionLabelId = useId();
  const listTitleId = useId();
  const { copy, copying } = useCopyToClipboard();

  const handleCopyListPlan = useCallback(async () => {
    if (copying) return;
    const text = formatListPlan(list.name, list.icon, openTasks, completedTasks, t);
    await copy(text, t('list.planCopied'));
  }, [completedTasks, copy, copying, list.icon, list.name, openTasks, t]);

  return (
    <div className="flex items-center gap-3">
      {list.icon && <span className="text-3xl">{list.icon}</span>}
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-3">
          {renaming ? (
            <RenameForm
              listName={list.name}
              listColor={list.color}
              renameSaving={renameSaving}
              inputRef={renameInputRef}
              onRename={onRename}
              onCancelRename={onCancelRename}
            />
          ) : (
            <>
              <span id={renameActionLabelId} className="sr-only">{t('list.rename')}</span>
              <h2
                className="text-2xl font-light tracking-tight"
                style={list.color ? { color: list.color } : undefined}
              >
                <Tooltip label={t('list.rename')}>
                  <button
                    type="button"
                    className="bg-transparent border-0 p-0 text-current text-start cursor-pointer hover:opacity-80 transition-opacity rounded-r-control focus-ring-soft"
                    onClick={onStartRename}
                    aria-labelledby={`${renameActionLabelId} ${listTitleId}`}
                  >
                    <span id={listTitleId}>{list.name}</span>
                  </button>
                </Tooltip>
              </h2>
            </>
          )}
          {!renaming && openTasks.length > 0 && (
            <span className="text-2xs font-medium text-text-muted/70 bg-surface-2/60 px-2 py-0.5 rounded-full tabular-nums">
              {formatNumber(openTasks.length)}
            </span>
          )}
        </div>
        {list.description && (
          <p className="text-text-muted text-sm mt-1 leading-relaxed">{list.description}</p>
        )}
      </div>
      <div className="ms-auto flex items-center gap-1.5">
        {openTasks.length > 0 && (
          <Tooltip label={t('list.copyPlan')}>
            <button
              type="button"
              onClick={() => { void handleCopyListPlan(); }}
              disabled={copying}
              className="text-text-muted text-xs px-2.5 py-1.5 rounded-r-card hover:text-text-secondary hover:bg-surface-2/60 transition-colors duration-150 disabled:opacity-50 focus-ring-soft"
            >
              {copying ? t('common.copying') : t('list.copyPlan')}
            </button>
          </Tooltip>
        )}
        {openTasks.length > 0 && (
          <button
            type="button"
            onClick={() => onSetSelectionMode(!selectionMode)}
            disabled={bulkBusy}
            className="text-xs px-2.5 py-1.5 rounded-r-card border border-card text-text-secondary hover:bg-surface-2 transition-colors duration-150 disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
          >
            {selectionMode ? t('common.done') : t('allTasks.select')}
          </button>
        )}
        <button
          type="button"
          onClick={onDeleteList}
          disabled={deleting}
          aria-label={t('list.delete')}
          className="h-7 px-2.5 rounded-r-card text-text-muted/60 hover:text-danger hover:bg-[var(--danger-tint-xs)] transition-colors duration-150 disabled:opacity-50 disabled:cursor-not-allowed text-xs focus-ring-soft"
        >
          {deleting ? t('common.saving') : t('list.delete')}
        </button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// RenameForm -- inline rename input extracted for clarity
// ---------------------------------------------------------------------------

interface RenameFormProps {
  listName: string;
  listColor: string | null | undefined;
  renameSaving: boolean;
  inputRef: React.RefObject<HTMLInputElement | null>;
  onRename: (newName: string) => void;
  onCancelRename: () => void;
}

function RenameForm({
  listName,
  listColor,
  renameSaving,
  inputRef,
  onRename,
  onCancelRename,
}: RenameFormProps): React.JSX.Element {
  const { t } = useI18n();

  // Centralised submit gate. Both Enter (form submit) and blur funnel
  // through the same trim + empty/unchanged check, so a whitespace-only
  // rename cannot land via one path while the other rejects it.
  const submit = (rawValue: string) => {
    const value = rawValue.trim();
    if (value && value !== listName) {
      onRename(value);
    } else {
      onCancelRename();
    }
  };

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        const input = inputRef.current;
        if (input) submit(input.value);
      }}
    >
      <input
        ref={(node) => {
          inputRef.current = node;
          node?.focus();
          node?.select();
        }}
        type="text"
        defaultValue={listName}
        disabled={renameSaving}
        maxLength={MAX_TITLE_LENGTH}
        aria-label={t('list.rename')}
        className="text-2xl font-light bg-transparent border-b border-accent/50 outline-hidden focus-ring-soft w-full text-text-primary disabled:opacity-50"
        style={listColor ? { color: listColor } : undefined}
        onBlur={(e) => {
          submit(e.currentTarget.value);
        }}
        onKeyDown={(e) => {
          if (isImeComposing(e)) return;
          if (e.key === 'Escape') {
            onCancelRename();
          }
        }}
      />
    </form>
  );
}
