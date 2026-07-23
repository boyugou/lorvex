import { useI18n } from '@/lib/i18n';
import { useCopyToClipboard } from '@/lib/platform/useCopyToClipboard';
import { SparkleIcon } from './icons';

/**
 * Canonical "Ask your AI assistant to change this" pill used wherever
 * AI-managed content is rendered to the user (memory entries, habits,
 * other agent-owned fields). The pill is visually non-editable: it
 * names the affordance and exposes a single "Copy prompt" button so
 * users can paste a seed prompt into their assistant chat.
 *
 * The pill ships its own ARIA wiring — a labelled action group with
 * a focusable Copy button. Callers pass the prompt template that
 * should be copied; the pill does not own the prompt copy itself.
 */
export function AskAssistantPill({
  prompt,
  className,
}: {
  /** Prompt text copied to clipboard when the user clicks "Copy prompt". */
  prompt: string;
  /** Optional extra container classes (alignment, margin). */
  className?: string;
}) {
  const { t } = useI18n();
  const { copy, copying } = useCopyToClipboard();

  const handleCopy = () => {
    void copy(prompt);
  };

  return (
    <div
      role="group"
      aria-label={t('aiManaged.askAssistant')}
      className={[
        'inline-flex items-center gap-1.5 rounded-full',
        'bg-accent/10 border border-accent/25',
        'px-2 py-0.5 text-2xs font-medium text-accent',
        'dark:bg-accent/15 dark:border-accent/35',
        className ?? '',
      ].join(' ')}
    >
      <SparkleIcon className="w-3 h-3" />
      <span>{t('aiManaged.askAssistant')}</span>
      <button
        type="button"
        onClick={handleCopy}
        disabled={copying}
        aria-label={t('aiManaged.copyPromptAria')}
        title={t('aiManaged.copyPrompt')}
        className="ms-0.5 inline-flex items-center justify-center rounded-full px-1.5 py-0.5 text-2xs font-medium hover:bg-accent/15 focus-ring-soft transition-colors disabled:opacity-50"
      >
        {t('aiManaged.copyPrompt')}
      </button>
    </div>
  );
}
