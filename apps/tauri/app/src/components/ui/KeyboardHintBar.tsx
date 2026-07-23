import { useI18n } from '@/lib/i18n';

/**
 * Floating keyboard shortcut hint bar.
 * Appears on first j/k navigation in a session, auto-dismisses after 8s or on action key.
 */
interface KeyboardHintBarProps {
  visible: boolean;
}

export function KeyboardHintBar({ visible }: KeyboardHintBarProps) {
  const { t } = useI18n();
  if (!visible) return null;

  return (
    <div
      className="sticky bottom-0 z-[var(--z-sticky)] flex items-center justify-center gap-4 py-2 px-4 bg-surface-2/90 backdrop-blur-sm border-t border-card text-2xs text-text-muted animate-[fade-in_0.2s_ease-out]"
    >
      <span><kbd className="font-mono text-text-secondary">x</kbd> {t('hints.done')}</span>
      <span className="text-surface-3">·</span>
      <span><kbd className="font-mono text-text-secondary">s</kbd> {t('hints.defer')}</span>
      <span className="text-surface-3">·</span>
      <span><kbd className="font-mono text-text-secondary">Enter</kbd> {t('hints.open')}</span>
      <span className="text-surface-3">·</span>
      <span><kbd className="font-mono text-text-secondary">Space</kbd> {t('hints.select')}</span>
      <span className="text-surface-3">·</span>
      <span><kbd className="font-mono text-text-secondary">?</kbd> {t('hints.allShortcuts')}</span>
    </div>
  );
}
