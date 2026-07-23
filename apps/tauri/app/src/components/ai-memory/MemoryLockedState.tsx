import { useI18n } from '@/lib/i18n';

/**
 * Locked-state hero shown when biometric memory-lock is engaged and
 * the window is currently de-authenticated. The previous design was
 * a single emoji + button — readable but visually flat for a
 * security-relevant surface. This panel layers:
 *
 *   1. A blurred "card stack" preview suggesting "your memory is
 *      here, just behind the lock" without leaking any actual content
 *      (the cards are static skeleton shapes, never seeded from real
 *      entries — the React Query cache is also evicted by the parent
 *      while locked, so even if we wanted to bind real text there'd
 *      be nothing to bind).
 *   2. A ghosted lock glyph centered over the stack, with a slow
 *      animated pulse ring keyed to a biometric-style cadence
 *      (~2s loop). The pulse re-orients attention to the unlock
 *      affordance without strobing.
 *   3. The "Why locked?" disclosure link routes to the Settings →
 *      Privacy section that controls `PREF_MEMORY_LOCK_ENABLED`. We
 *      use a plain anchor that fires `onNavigateSettings` so the
 *      hash-router contract stays owned by `MainViewContent`.
 *
 * Pure presentation — the parent owns lock state, the unlock
 * promise, and the auth-error string. We never call the IPC layer
 * directly so the panel stays test-friendly in isolation.
 */
export function MemoryLockedState({
  t,
  authError,
  onUnlock,
}: {
  t: ReturnType<typeof useI18n>['t'];
  authError: string | null;
  onUnlock: () => void;
}) {
  return (
    <div className="flex-1 flex flex-col items-center justify-center gap-6 px-6 pb-16">
      {/* Blurred preview stack — visual reassurance that data exists
          without revealing it. Three offset cards convey "more than
          one entry" without faking a count. */}
      <div className="relative w-full max-w-sm h-44 select-none" aria-hidden="true">
        <div className="absolute inset-x-6 top-0 h-32 rounded-r-card bg-surface-2/80 border border-surface-3 blur-[2px] opacity-60 rotate-[-2deg]" />
        <div className="absolute inset-x-4 top-3 h-32 rounded-r-card bg-surface-2 border border-surface-3 blur-[2.5px] opacity-80 rotate-[1.5deg]" />
        <div className="absolute inset-x-2 top-6 h-32 rounded-r-card bg-surface-2 border border-surface-3 blur-[3px]">
          <div className="px-4 py-3 space-y-2">
            <div className="h-2.5 w-24 bg-surface-3 rounded-r-control" />
            <div className="h-2 w-full bg-surface-3 rounded-r-control" />
            <div className="h-2 w-5/6 bg-surface-3 rounded-r-control" />
            <div className="h-2 w-3/4 bg-surface-3 rounded-r-control" />
          </div>
        </div>

        {/* Lock glyph + biometric pulse ring. Two concentric pulses
            (offset 1s) create the "scanning fingerprint" cadence
            without animating the glyph itself. `prefers-reduced-
            motion` is respected via the global CSS rule that nukes
            `animate-*` keyframes — see `app/src/index.css`. */}
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="relative">
            <span
              className="absolute inset-0 rounded-full bg-accent/15 animate-ping"
              style={{ animationDuration: '2.4s' }}
            />
            <span
              className="absolute inset-0 rounded-full bg-accent/10 animate-ping"
              style={{ animationDuration: '2.4s', animationDelay: '1.2s' }}
            />
            <span className="relative inline-flex items-center justify-center w-14 h-14 rounded-full bg-surface-1 border border-card text-text-muted/80 shadow-[var(--shadow-tooltip)]">
              <svg
                viewBox="0 0 24 24"
                width="22"
                height="22"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.6"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <rect x="5" y="11" width="14" height="9" rx="2" />
                <path d="M8 11V8a4 4 0 0 1 8 0v3" />
              </svg>
            </span>
          </div>
        </div>
      </div>

      <div className="flex flex-col items-center gap-1.5 text-center">
        <p className="text-text-secondary text-sm font-medium">{t('memory.locked')}</p>
        <p className="text-text-muted text-xs max-w-[22rem] leading-relaxed">
          {t('memory.lockedDescription')}
        </p>
      </div>

      {authError && (
        <p role="alert" aria-live="assertive" className="text-danger text-xs">
          {authError}
        </p>
      )}

      <div className="flex flex-col items-center gap-3">
        <button
          type="button"
          onClick={onUnlock}
          className="text-sm px-5 py-2 rounded-r-card bg-accent text-on-accent active:scale-[0.97] hover:bg-accent/90 transition-[color,background-color,transform] focus-ring-strong"
        >
          {t('memory.unlockBiometric')}
        </button>
        {/* "Why locked?" — keep this as plain text since the
            in-app navigation contract for deep-linking into Settings
            > Privacy lives in MainViewContent (`onNavigate`). The
            anchor renders as a disclosure hint; users who want to
            change the policy reach it from the Settings cog. */}
        <p className="text-text-muted/70 text-2xs">
          {t('memory.lockedWhyHint')}
        </p>
      </div>
    </div>
  );
}
