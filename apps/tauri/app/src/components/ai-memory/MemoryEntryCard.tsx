import { useState } from 'react';
import type { AIMemoryEntry } from '@/lib/ipc/memory';
import { useI18n, type TranslationKey } from '@/lib/i18n';
import { formatRelativeTime } from '@/lib/dates/dateLocale';
import { confirm } from '@/lib/dialogs/confirm';
import { TrashIcon, ClockIcon } from '../ui/icons';
import { AskAssistantPill } from '../ui/AskAssistantPill';
import { HistoryModal } from './HistoryModal';
import { formatKey, keyIcon } from './helpers';
import { useForgetMemoryEntryAction } from './useAiMemoryActions';

export function MemoryEntryCard({
  entry,
  locale,
  timezone,
  t,
  onMutate,
}: {
  entry: AIMemoryEntry;
  locale: string;
  timezone: string;
  t: (k: TranslationKey) => string;
  onMutate: () => void;
}) {
  const { format } = useI18n();
  const [historyKey, setHistoryKey] = useState<string | null>(null);
  const icon = keyIcon(entry.key);
  const forgetMutation = useForgetMemoryEntryAction({ onSuccess: onMutate, t });

  const handleForget = async () => {
    const confirmed = await confirm({
      title: t('memory.forgetConfirmTitle'),
      message: t('memory.forgetConfirmMessage'),
      confirmLabel: t('common.delete'),
      variant: 'danger',
    });
    if (confirmed) {
      forgetMutation.mutate(entry.key);
    }
  };

  return (
    <>
      <div className="bg-surface-2 border border-surface-3 rounded-r-card p-4">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-2">
            <span className="text-sm">{icon}</span>
            <h3 className="text-text-primary text-sm font-medium">
              {formatKey(entry.key)}
            </h3>
          </div>
          <span className="text-text-muted text-xs">
            {t('memory.updated')} {formatRelativeTime(entry.updated_at, locale, t, format, timezone)}
          </span>
        </div>
        <div className="text-text-secondary text-sm leading-relaxed whitespace-pre-wrap select-text-content">
          {entry.content}
        </div>
        <div className="mt-3">
          <AskAssistantPill prompt={t('aiManaged.promptMemoryEntry')} />
        </div>
        <div className="flex items-center justify-end gap-1 mt-3 pt-3 border-t border-card">
          <button
            type="button"
            onClick={() => setHistoryKey(entry.key)}
            className="text-text-muted hover:text-text-secondary text-xs px-2 py-1 rounded-r-control hover:bg-surface-3/50 transition-colors flex items-center gap-1 focus-ring-soft"
          >
            <ClockIcon className="w-3.5 h-3.5" />
            {t('memory.history')}
          </button>
          <button
            type="button"
            onClick={() => { void handleForget(); }}
            disabled={forgetMutation.isPending}
            className="text-text-muted hover:text-danger text-xs px-2 py-1 rounded-r-control hover:bg-[var(--danger-tint-sm)] transition-colors flex items-center gap-1 disabled:opacity-50 focus-ring-soft"
          >
            <TrashIcon className="w-3.5 h-3.5" />
            {t('common.delete')}
          </button>
        </div>
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
    </>
  );
}
