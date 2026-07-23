import type { TranslationKey } from '@/lib/i18n';
import type { View } from '@/lib/types';

interface AllClearViewProps {
  onNavigate?: ((view: View) => void) | undefined;
  /**
   * primary CTA in the empty-Today state. When the
   * caller threads QuickCapture's open handler down, AllClearView
   * surfaces a "+ Add task" button as the principal action so an
   * empty Today doesn't dead-end the user — the secondary
   * "Browse upcoming" / "Browse someday" buttons stay as
   * tertiary navigation, demoted from outline to ghost styling.
   */
  onAddTask?: (() => void) | undefined;
  t: (key: TranslationKey) => string;
}

export function AllClearView({ onNavigate, onAddTask, t }: AllClearViewProps): React.JSX.Element {
  return (
    <div className="flex flex-col items-center justify-center py-24 text-center bg-gradient-to-b from-[var(--accent-tint-xxs)] to-transparent rounded-r-panel">
      <p className="text-5xl text-accent/60 mb-4" aria-hidden="true">✦</p>
      <p className="text-text-secondary text-sm">{t('today.allClear')}</p>
      <p className="text-text-muted text-xs mt-1">{t('today.askAssistant')}</p>
      {onAddTask && (
        <button
          type="button"
          onClick={onAddTask}
          className="mt-5 inline-flex items-center gap-1.5 text-xs font-semibold px-4 py-2 rounded-r-control bg-accent text-on-accent shadow-[var(--shadow-tooltip)] hover:bg-accent/90 active:scale-[0.97] transition-[color,background-color,transform,box-shadow] duration-150 focus-ring-strong"
        >
          <span aria-hidden="true">+</span>
          {t('capture.addTask')}
        </button>
      )}
      {onNavigate && (
        <div className="flex gap-2 mt-3">
          <button
            type="button"
            onClick={() => onNavigate({ type: 'upcoming' })}
            className="text-xs px-3 py-1.5 rounded-r-control text-text-muted hover:text-text-secondary hover:bg-surface-2 transition-[color,background-color] duration-150 focus-ring-soft"
          >
            {t('today.browseUpcoming')}
          </button>
          <button
            type="button"
            onClick={() => onNavigate({ type: 'someday' })}
            className="text-xs px-3 py-1.5 rounded-r-control text-text-muted hover:text-text-secondary hover:bg-surface-2 transition-[color,background-color] duration-150 focus-ring-soft"
          >
            {t('today.browseSomeday')}
          </button>
        </div>
      )}
      <p className="text-text-muted text-xs mt-3">{t('today.emptyHint')}</p>
    </div>
  );
}
