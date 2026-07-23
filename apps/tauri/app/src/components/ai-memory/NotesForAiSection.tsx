import { useRef, useState } from 'react';
import { MAX_MEMORY_CONTENT_LENGTH } from '@lorvex/shared/validation';
import type { AIMemoryEntry } from '@/lib/ipc/memory';
import { useI18n, type TranslationKey } from '@/lib/i18n';
import { isImeComposing } from '@/lib/ime';
import { formatRelativeTime } from '@/lib/dates/dateLocale';
import { confirm } from '@/lib/dialogs/confirm';
import { AutosizingTextarea } from '../ui/AutosizingTextarea';
import { PencilIcon, TrashIcon, ClockIcon } from '../ui/icons';
import { HistoryModal } from './HistoryModal';
import { useNotesForAiActions } from './useAiMemoryActions';

const NOTES_FOR_AI_KEY = 'notes_for_ai';

export function NotesForAiSection({
  entry,
  locale,
  timezone,
  t,
  onMutate,
}: {
  entry: AIMemoryEntry | null;
  locale: string;
  timezone: string;
  t: (k: TranslationKey) => string;
  onMutate: () => void;
}) {
  const { format } = useI18n();
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState('');
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const [historyKey, setHistoryKey] = useState<string | null>(null);
  // hook owns memory cache invalidation; the
  // caller-supplied `onMutate` is forwarded as the renamed
  // `onSuccess` notifier so `AIMemoryView`'s broader invalidation
  // (which also touches memoryHistory for the modal) keeps firing.
  const { saveMutation, deleteMutation } = useNotesForAiActions({
    onSuccess: onMutate,
    onSaved: () => setEditing(false),
    t,
  });

  const handleEdit = () => {
    setDraft(entry?.content ?? '');
    setEditing(true);
    requestAnimationFrame(() => {
      textareaRef.current?.focus();
    });
  };

  const handleSave = () => {
    const trimmed = draft.trim();
    if (!trimmed) return;
    saveMutation.mutate(trimmed);
  };

  const handleDelete = async () => {
    const confirmed = await confirm({
      title: t('memory.deleteNotesConfirmTitle'),
      message: t('memory.deleteNotesConfirmMessage'),
      confirmLabel: t('common.delete'),
      variant: 'danger',
    });
    if (confirmed) {
      deleteMutation.mutate();
    }
  };

  const handleAdd = () => {
    setDraft('');
    setEditing(true);
    requestAnimationFrame(() => {
      textareaRef.current?.focus();
    });
  };

  return (
    <section>
      <h2 className="text-text-primary text-base font-medium mb-3 flex items-center gap-2">
        <span className="text-sm">📝</span>
        {t('memory.notesForAi')}
      </h2>

      <div className="bg-surface-2 border border-surface-3 rounded-r-card p-4">
        {editing ? (
          <div className="space-y-3">
            <AutosizingTextarea
              ref={textareaRef}
              data-theme-form-control="true"
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              minRows={6}
              maxRows={20}
              resize="vertical"
              maxLength={MAX_MEMORY_CONTENT_LENGTH}
              className="w-full bg-surface-1 border border-surface-3 rounded-r-card px-3 py-2 text-sm text-text-primary placeholder:text-text-muted outline-hidden focus-ring-soft"
              aria-label={t('memory.notesForAi')}
              placeholder={t('memory.notesForAiEmpty')}
              onEscape={() => setEditing(false)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && (e.metaKey || e.ctrlKey) && !isImeComposing(e)) {
                  e.preventDefault();
                  handleSave();
                }
              }}
            />
            <div className="flex gap-2 justify-end">
              <button
                type="button"
                onClick={() => setEditing(false)}
                className="rounded-r-card border border-card bg-surface-2/50 text-text-secondary text-xs font-medium px-3 py-1.5 hover:bg-surface-3/60 transition-colors focus-ring-soft"
              >
                {t('common.cancel')}
              </button>
              <button
                type="button"
                onClick={handleSave}
                disabled={!draft.trim() || saveMutation.isPending || deleteMutation.isPending}
                className="rounded-r-card bg-[var(--accent-tint-sm)] hover:bg-[var(--accent-tint-md)] text-accent text-xs font-semibold px-3 py-1.5 transition-colors disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
              >
                {t('common.save')}
              </button>
            </div>
          </div>
        ) : entry ? (
          <div>
            <div className="flex items-start justify-between gap-3 mb-2">
              <div className="text-text-secondary text-sm leading-relaxed whitespace-pre-wrap select-text-content flex-1">
                {entry.content}
              </div>
            </div>
            <div className="flex items-center justify-between mt-3 pt-3 border-t border-card">
              <span className="text-text-muted text-xs">
                {t('memory.updated')} {formatRelativeTime(entry.updated_at, locale, t, format, timezone)}
              </span>
              <div className="flex items-center gap-1">
                <button
                  type="button"
                  onClick={() => setHistoryKey(NOTES_FOR_AI_KEY)}
                  className="text-text-muted hover:text-text-secondary text-xs px-2 py-1 rounded-r-control hover:bg-surface-3/50 transition-colors flex items-center gap-1 focus-ring-soft"
                >
                  <ClockIcon className="w-3.5 h-3.5" />
                  {t('memory.history')}
                </button>
                <button
                  type="button"
                  onClick={handleEdit}
                  className="text-text-muted hover:text-text-secondary text-xs px-2 py-1 rounded-r-control hover:bg-surface-3/50 transition-colors flex items-center gap-1 focus-ring-soft"
                >
                  <PencilIcon className="w-3.5 h-3.5" />
                  {t('common.edit')}
                </button>
                <button
                  type="button"
                  onClick={() => { void handleDelete(); }}
                  disabled={deleteMutation.isPending || saveMutation.isPending}
                  className="text-text-muted hover:text-danger text-xs px-2 py-1 rounded-r-control hover:bg-[var(--danger-tint-sm)] transition-colors flex items-center gap-1 disabled:opacity-50 focus-ring-soft"
                >
                  <TrashIcon className="w-3.5 h-3.5" />
                  {t('common.delete')}
                </button>
              </div>
            </div>
          </div>
        ) : (
          <div className="text-center py-4">
            <p className="text-text-muted text-sm mb-3">{t('memory.notesForAiEmpty')}</p>
            <button
              type="button"
              onClick={handleAdd}
              className="text-sm px-4 py-2 rounded-r-card bg-[var(--accent-tint-sm)] hover:bg-[var(--accent-tint-md)] text-accent font-medium transition-colors focus-ring-soft"
            >
              {t('memory.addNotes')}
            </button>
          </div>
        )}
      </div>

      {historyKey && (
        <HistoryModal
          memoryKey={historyKey}
          locale={locale}
          timezone={timezone}
          t={t}
          onClose={() => setHistoryKey(null)}
          onMutate={onMutate}
        />
      )}
    </section>
  );
}
