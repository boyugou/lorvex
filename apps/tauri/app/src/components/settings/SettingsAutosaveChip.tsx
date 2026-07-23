import { useEffect, useState } from 'react';
import { useReducedMotion } from '@/lib/reducedMotion';
import { useI18n } from '@/lib/i18n';

export type SettingsAutosaveState = 'idle' | 'saving' | 'saved' | 'error';

/**
 * Header chip that surfaces autosave outcomes in the Settings
 * header. Replaces the plain text banner with a compact pill that
 * transitions through saving → saved → idle. The saved state animates
 * a checkmark stroke "sweep" for ~360ms; `prefers-
 * reduced-motion` collapses the sweep to a static glyph.
 *
 * Idle is rendered as `null` so the chip vanishes when there is
 * nothing to report — keeping the header chrome clean during the
 * common case of an untouched settings page.
 */
export function SettingsAutosaveChip({ state }: { state: SettingsAutosaveState }) {
  const { t } = useI18n();
  const reducedMotion = useReducedMotion();
  // Bump on every saved-transition so the checkmark animation
  // restarts when the user saves twice in a row.
  const [savedKey, setSavedKey] = useState(0);
  useEffect(() => {
    if (state === 'saved') setSavedKey((k) => k + 1);
  }, [state]);

  if (state === 'idle') return null;

  const role = state === 'error' ? 'alert' : 'status';
  const liveness = state === 'error' ? 'assertive' : 'polite';

  let label = '';
  let toneClass = '';
  let icon: React.ReactNode = null;
  if (state === 'saving') {
    label = t('settings.autosaveSaving');
    toneClass = 'bg-surface-3/60 border-surface-3 text-text-muted';
    icon = (
      <svg
        aria-hidden="true"
        width="12"
        height="12"
        viewBox="0 0 24 24"
        fill="none"
        className={reducedMotion ? '' : 'animate-spin'}
      >
        <circle cx="12" cy="12" r="9" stroke="currentColor" strokeOpacity="0.25" strokeWidth="3" />
        <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      </svg>
    );
  } else if (state === 'saved') {
    label = t('settings.autosaveSaved');
    toneClass = 'border-success/40 bg-[var(--success-tint-sm)] text-success';
    icon = (
      <svg
        key={savedKey}
        aria-hidden="true"
        width="12"
        height="12"
        viewBox="0 0 16 16"
        fill="none"
      >
        <path
          d="M3.5 8.5 L7 12 L13 4"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          className={reducedMotion ? '' : 'settings-autosave-check-sweep'}
        />
      </svg>
    );
  } else {
    label = t('settings.autosaveError');
    toneClass = 'border-danger/40 bg-[var(--danger-tint-sm)] text-danger';
    icon = (
      <svg aria-hidden="true" width="12" height="12" viewBox="0 0 16 16" fill="none">
        <path
          d="M4 4 L12 12 M12 4 L4 12"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
        />
      </svg>
    );
  }

  return (
    <span
      role={role}
      aria-live={liveness}
      className={`inline-flex items-center gap-1.5 text-xs font-medium px-2 py-0.5 rounded-full border ${toneClass}`}
    >
      <span className="shrink-0 flex items-center">{icon}</span>
      <span>{label}</span>
    </span>
  );
}
