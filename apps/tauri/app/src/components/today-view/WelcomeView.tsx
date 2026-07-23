import { openUrl } from '@tauri-apps/plugin-opener';

import type { TranslationKey } from '@/lib/i18n';
import type { View } from '@/lib/types';
import { reportClientError } from '@/lib/errors/errorLogging';
import { useNetworkStatus } from '@/lib/useNetworkStatus';
import { Banner } from '@/components/ui/Banner';

// "Learn more" link opens the canonical offline-first explainer on
// GitHub (the doc is also shipped in the source tree at
// docs/setup/FIRST_RUN_OFFLINE.md). We point at the GitHub URL so the
// link works identically from a packaged app or a dev build; neither
// can resolve a repo-relative path.
// The URL tracks the canonical project repo used everywhere else in
// the app (sidebar Releases link, About panel, Help menu).
const OFFLINE_DOC_URL =
  'https://github.com/lorvex/lorvex/blob/main/docs/setup/FIRST_RUN_OFFLINE.md';

interface WelcomeViewProps {
  onNavigate?: ((view: View) => void) | undefined;
  /**
   * when provided, the Welcome view renders an inline
   * "Keyboard shortcuts" button that opens the cheatsheet modal. Wired
   * by surfaces that have access to the shortcuts-panel state (the
   * Help-menu modal does this; the Today empty-state currently omits
   * the button to keep the first-run hierarchy simple).
   */
  onOpenShortcuts?: (() => void) | undefined;
  t: (key: TranslationKey) => string;
}

export function WelcomeView({ onNavigate, onOpenShortcuts, t }: WelcomeViewProps): React.JSX.Element {
  const { online } = useNetworkStatus();
  return (
    <div className="max-w-lg mx-auto py-12 space-y-6">
      {!online && (
        <div data-testid="welcome-offline-banner">
          <Banner
            tone="warning"
            icon={<OfflineCloudIcon />}
            bodyTone="primary"
            className="animate-[fade-in_0.2s_ease-out]"
          >
            <p className="leading-relaxed">{t('welcome.offline.banner')}</p>
            <div className="flex items-center gap-4 mt-1.5">
              <button
                type="button"
                onClick={() => onNavigate?.({ type: 'settings' })}
                className="text-accent text-xs font-medium hover:underline focus-ring-soft rounded-r-control"
              >
                {t('welcome.offline.openSettings')} →
              </button>
              <button
                type="button"
                data-testid="welcome-offline-learn-more"
                aria-label={t('welcome.offline.learnMoreAria')}
                onClick={() => {
                  openUrl(OFFLINE_DOC_URL).catch((error) => {
                    reportClientError(
                      'welcome.offline.learnMore.openUrl',
                      'Failed to open offline-first documentation URL',
                      error,
                    );
                  });
                }}
                className="text-text-muted text-xs font-medium hover:text-accent hover:underline focus-ring-soft rounded-r-control"
              >
                {t('welcome.offline.learnMore')}
              </button>
            </div>
          </Banner>
        </div>
      )}
      <div className="text-center space-y-2">
        <p className="text-4xl">✦</p>
        <h2 className="text-text-primary text-lg font-medium">{t('welcome.title')}</h2>
        <p className="text-text-secondary text-sm leading-relaxed">{t('welcome.description')}</p>
      </div>
      {/*
       * Numbered timeline of onboarding steps with monoline
       * illustrations and a stagger-fade entrance. Each step has:
       *   - circular numbered node (01/02/03) on a vertical rail
       *   - small monoline SVG illustration anchored to the row
       *   - title + detail copy
       * The vertical rail is drawn by `.welcome-timeline::before` (a
       * thin `--color-surface-3` line behind the column of badges in
       * `styles/components.css`); each badge's `bg-surface-2` masks
       * the rail at its row and `z-[var(--z-elevated)]` keeps the
       * badge stacked above the pseudo-element line.
       */}
      <div className="rounded-r-card border border-surface-3 bg-surface-1 p-6">
        <h3 className="text-text-primary text-sm font-medium mb-5">{t('welcome.gettingStarted')}</h3>
        <ol className="welcome-timeline relative ps-1">
          <TimelineStep
            index={1}
            delayMs={0}
            title={t('welcome.step1title')}
            detail={t('welcome.step1auto')}
            illustration={<TerminalIllustration />}
          />
          <TimelineStep
            index={2}
            delayMs={60}
            title={t('welcome.step2title')}
            detail={t('welcome.step2detail')}
            illustration={<NotebookIllustration />}
          />
          <TimelineStep
            index={3}
            delayMs={120}
            title={t('welcome.step3title')}
            detail={t('welcome.step3detail')}
            illustration={<HeatmapIllustration />}
          />
        </ol>
      </div>
      {/*
       * Onboarding example task. A non-interactive preview card
       * showing what a real task looks like once the user has wired
       * up an assistant, paired with the exact phrase to say. The
       * empty-state branch above only renders when there are no
       * tasks; once the user creates a real task, the empty state
       * collapses and this card disappears with it. No DB seed
       * required — the card is pure illustration so a first-time
       * user can mentally rehearse the workflow before sending a
       * prompt.
       */}
      <div className="rounded-r-card border border-surface-3 bg-surface-1 p-5">
        <p className="text-text-muted/80 text-2xs font-semibold tracking-widest uppercase mb-3">
          {t('welcome.exampleTaskEyebrow')}
        </p>
        <div
          className="flex items-start gap-3 rounded-r-card bg-surface-2/70 px-3.5 py-3 border border-surface-3/60"
          aria-hidden="true"
        >
          <span
            className="mt-0.5 inline-flex h-4 w-4 shrink-0 rounded-full border border-surface-3 bg-surface-1"
          />
          <div className="min-w-0 flex-1">
            <p className="text-text-primary text-sm font-medium truncate">
              {t('welcome.exampleTaskTitle')}
            </p>
            <p className="text-text-muted text-2xs mt-0.5">
              {t('welcome.exampleTaskMeta')}
            </p>
          </div>
        </div>
        <p className="mt-3 text-text-secondary text-xs leading-relaxed">
          {t('welcome.exampleTaskPromptIntro')}
          <span className="font-mono text-text-primary bg-surface-2/80 rounded-r-control px-1.5 py-0.5 mx-1 inline-block">
            {t('welcome.exampleTaskPrompt')}
          </span>
        </p>
      </div>

      <div className="flex flex-col items-center gap-3">
        <button
          type="button"
          onClick={() => onNavigate?.({ type: 'settings' })}
          className="px-5 py-2.5 rounded-r-control bg-accent text-on-accent active:scale-[0.97] text-sm font-medium hover:bg-accent/90 transition-colors focus-ring-strong"
        >
          {t('welcome.openSettings')}
        </button>
        {onOpenShortcuts && (
          /* surface the keyboard-shortcuts cheatsheet on
             the Welcome surface so first-time users learn `?` exists.
             Rendered as a quiet text button so it doesn't compete with
             the primary "Open Settings" CTA. */
          <button
            type="button"
            onClick={onOpenShortcuts}
            className="text-xs text-text-muted hover:text-text-secondary hover:underline transition-colors focus-ring-soft rounded-r-control"
          >
            {t('welcome.openShortcuts')}
          </button>
        )}
        <p className="text-text-muted text-xs text-center max-w-sm">
          {t('welcome.privacyNote')}
        </p>
      </div>
    </div>
  );
}

// \u2014 Single timeline row. Stagger-fade is driven by an inline
// `animation-delay` per row so the three rows resolve 60ms apart on
// mount. `motion-reduce` zeroes the delay AND the animation so reduced-
// motion users see all three rows in their final state immediately.
function TimelineStep({
  index,
  delayMs,
  title,
  detail,
  illustration,
}: {
  index: number;
  delayMs: number;
  title: string;
  detail: string;
  illustration: React.ReactNode;
}) {
  return (
    <li
      className="welcome-timeline-step relative flex items-start gap-3 pb-5 last:pb-0 motion-safe:animate-[fade-in_0.36s_cubic-bezier(0.22,1,0.36,1)_both]"
      style={{ animationDelay: `${delayMs}ms` }}
    >
      <div className="flex flex-col items-center shrink-0">
        <span
          className="inline-flex items-center justify-center w-8 h-8 rounded-full bg-surface-2 border border-surface-3 text-2xs font-semibold tabular-nums text-accent z-[var(--z-elevated)]"
          aria-hidden="true"
        >
          {String(index).padStart(2, '0')}
        </span>
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-text-primary text-sm font-medium">{title}</p>
        <p className="text-text-secondary text-xs mt-0.5 leading-relaxed">{detail}</p>
      </div>
      <div className="shrink-0 text-text-muted/70" aria-hidden="true">
        {illustration}
      </div>
    </li>
  );
}

function TerminalIllustration() {
  return (
    <svg width="48" height="40" viewBox="0 0 48 40" fill="none" stroke="currentColor" strokeWidth="1.25" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="6" width="42" height="28" rx="3" />
      <line x1="3" y1="12" x2="45" y2="12" />
      <circle cx="7" cy="9" r="0.6" fill="currentColor" stroke="none" />
      <circle cx="10" cy="9" r="0.6" fill="currentColor" stroke="none" />
      <circle cx="13" cy="9" r="0.6" fill="currentColor" stroke="none" />
      <path d="M8 19l4 4-4 4" />
      <line x1="16" y1="27" x2="26" y2="27" />
    </svg>
  );
}

function NotebookIllustration() {
  return (
    <svg width="40" height="40" viewBox="0 0 40 40" fill="none" stroke="currentColor" strokeWidth="1.25" strokeLinecap="round" strokeLinejoin="round">
      <rect x="7" y="5" width="26" height="30" rx="2.5" />
      <line x1="11" y1="5" x2="11" y2="35" />
      <line x1="15" y1="12" x2="29" y2="12" />
      <line x1="15" y1="17" x2="29" y2="17" />
      <line x1="15" y1="22" x2="24" y2="22" />
      <path d="M15 28l2 2 4-4" />
    </svg>
  );
}

function HeatmapIllustration() {
  return (
    <svg width="48" height="40" viewBox="0 0 48 40" fill="none" stroke="currentColor" strokeWidth="0.6">
      {Array.from({ length: 6 }).map((_, col) =>
        Array.from({ length: 5 }).map((_, row) => {
          const filled = ((col * 5 + row) % 3) === 0;
          return (
            <rect
              key={`${col}-${row}`}
              x={4 + col * 7}
              y={4 + row * 7}
              width="5"
              height="5"
              rx="1"
              fill={filled ? 'currentColor' : 'none'}
              opacity={filled ? 0.55 : 1}
            />
          );
        })
      )}
    </svg>
  );
}

// Inline cloud-with-slash glyph, mirrored from sidebar/SidebarHeader so the
// Welcome banner matches the header\u2019s existing offline visual vocabulary
// without pulling in an icon library just for one screen.
function OfflineCloudIcon() {
  return (
    <svg
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
      className="text-warning shrink-0"
      aria-hidden="true"
    >
      <path d="M17.5 19H9a7 7 0 0 1-6.71-5" />
      <path d="M8.5 4.6A7 7 0 0 1 21 9v1a4 4 0 0 1 1.13 7.47" />
      <line x1="2" y1="2" x2="22" y2="22" />
    </svg>
  );
}
