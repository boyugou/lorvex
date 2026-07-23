import { Component, type ReactNode } from 'react';
import { reportClientError } from '../lib/errors/errorLogging';
import { truncateGraphemes } from '../lib/textTruncate';
import { useI18n } from '../lib/i18n';
import { BUILD_SHA_SHORT } from '../lib/build/version';
import { getRuntimeUserAgentSnippet } from '../lib/platform/platform';
import { TonalButton } from './ui/TonalButton';
import { TonalIconBubble } from './ui/TonalIconBubble';

/**
 * `resetKeys` accepts arbitrary values — strings, numbers, booleans,
 * nullish slots, plus opaque identity tokens (objects / Symbols) used
 * as navigation discriminators. The boundary only needs
 * change-detection, not encoding, so `componentDidUpdate` does a
 * shallow array compare: any value type works and there is zero
 * per-render allocation in the steady state.
 */
type ResetKey = unknown;

interface InnerProps {
  children: ReactNode;
  fallback?: ReactNode;
  title: string;
  message: string;
  devDetailSummary: string;
  tryAgain: string;
  reload: string;
  copyReport: string;
  copyReportCopied: string;
  resetKeys: ReadonlyArray<ResetKey>;
}

interface State {
  hasError: boolean;
  error: Error | null;
  copied: boolean;
}

function resetKeysChanged(prev: ReadonlyArray<ResetKey>, next: ReadonlyArray<ResetKey>): boolean {
  if (prev.length !== next.length) return true;
  for (let i = 0; i < prev.length; i += 1) {
    if (!Object.is(prev[i], next[i])) return true;
  }
  return false;
}

// React's error-boundary API (`componentDidCatch`,
// `getDerivedStateFromError`) is class-only — there is no functional-component
// equivalent. The functional `ErrorBoundary` wrapper below stays the public
// surface; this inner class is the only sanctioned exception to the
// "functional components only" rule in CONTRIBUTING.md.
class ErrorBoundaryInner extends Component<InnerProps, State> {
  override state: State = { hasError: false, error: null, copied: false };
  private copiedResetTimer: ReturnType<typeof setTimeout> | null = null;

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error, copied: false };
  }

  /**
   * Builds the truncated clipboard payload. Keeps the original message
   * + timestamp + UA — same shape `reportClientError` already routes
   * to the error log, so support requests carry comparable detail.
   * App version is injected at build time via
   * `import.meta.env.VITE_APP_VERSION`; the build SHA flows through
   * [`BUILD_SHA_SHORT`] in `lib/build/version.ts` so the About panel
   * and this paste-into-issue payload render byte-identical
   * identities. Capped at 1 KB so paste-into-issue stays readable.
   */
  private buildReport(error: Error): string {
    const ts = new Date().toISOString();
    const message = (error.message ?? 'Unknown error').slice(0, 700);
    const ua = getRuntimeUserAgentSnippet();
    const version = (import.meta.env.VITE_APP_VERSION as string | undefined) ?? 'unknown';
    // `BUILD_SHA_SHORT` is the canonical 7-char build identity rendered
    // in the About panel. Both surfaces flow through one helper
    // (`lib/build/version.ts`) so a user copying their version from
    // Settings and a user pasting an error report ship the same
    // string into a GitHub issue — no `''` vs `'unknown'` drift.
    return `[Lorvex error report]\nVersion: ${version}\nBuild: ${BUILD_SHA_SHORT}\nWhen: ${ts}\nMessage: ${message}\nClient: ${ua}`;
  }

  private handleCopyReport = () => {
    const error = this.state.error;
    if (!error) return;
    const payload = this.buildReport(error);
    const finish = () => {
      this.setState({ copied: true });
      if (this.copiedResetTimer) clearTimeout(this.copiedResetTimer);
      this.copiedResetTimer = setTimeout(() => {
        this.setState({ copied: false });
      }, 2200);
    };
    try {
      if (typeof navigator !== 'undefined' && navigator.clipboard?.writeText) {
        void navigator.clipboard.writeText(payload).then(finish).catch((err) => {
          reportClientError('ErrorBoundary.copyReport', 'Failed to copy error report', err, undefined, 'warn');
        });
      } else {
        // No Clipboard API available (older WebViews); silently no-op
        // rather than throwing a second error inside the boundary.
        finish();
      }
    } catch (err) {
      reportClientError('ErrorBoundary.copyReport', 'Failed to copy error report', err, undefined, 'warn');
    }
  };

  override componentWillUnmount() {
    if (this.copiedResetTimer) clearTimeout(this.copiedResetTimer);
  }

  override componentDidCatch(error: Error, info: React.ErrorInfo) {
    reportClientError(
      'ErrorBoundary',
      error.message || 'Unknown React render error',
      error,
      info.componentStack?.slice(0, 500) ?? undefined,
    );
  }

  override componentDidUpdate(prevProps: InnerProps) {
    if (
      this.state.hasError
      && resetKeysChanged(prevProps.resetKeys, this.props.resetKeys)
    ) {
      this.setState({ hasError: false, error: null, copied: false });
    }
  }

  override render() {
    if (this.state.hasError) {
      if (this.props.fallback) return this.props.fallback;
      return (
        <div className="flex flex-col items-center justify-center h-full px-4 sm:px-8 text-center">
          <TonalIconBubble tone="danger" size="lg" tint="sm" className="mb-4">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-danger">
              <circle cx="12" cy="12" r="10" /><line x1="12" y1="8" x2="12" y2="12" /><line x1="12" y1="16" x2="12.01" y2="16" />
            </svg>
          </TonalIconBubble>
          <p className="text-lg font-medium mb-2">{this.props.title}</p>
          <p className="text-text-secondary text-sm mb-4 max-w-md">
            {this.props.message}
          </p>
          {/* raw `error.message` can leak sensitive
              identifiers (file paths, user IDs, SQL fragments,
              stringified IPC payloads). Production users only need the
              friendly title/message above; developers running a dev
              build still get the truncated detail one collapsed level
              away. `import.meta.env.DEV` is statically replaced by Vite
              so the entire branch tree-shakes out of release bundles. */}
          {import.meta.env.DEV && this.state.error?.message && (
            <details className="text-text-muted text-xs bg-surface-2 rounded-r-card p-3 max-w-lg mb-4 select-text">
              <summary className="cursor-pointer text-text-secondary">
                {this.props.devDetailSummary}
              </summary>
              <pre className="mt-2 overflow-auto whitespace-pre-wrap break-words">
                {truncateGraphemes(this.state.error.message, 200)}
              </pre>
            </details>
          )}
          <div className="flex items-center gap-3 flex-wrap justify-center">
            <TonalButton
              tone="accent"
              size="lg"
              onClick={() => this.setState({ hasError: false, error: null, copied: false })}
            >
              {this.props.tryAgain}
            </TonalButton>
            <button type="button"
              onClick={() => window.location.reload()}
              className="text-sm px-3 py-1.5 rounded-r-card border border-surface-3 text-text-secondary hover:bg-surface-3 transition-colors focus-ring-soft"
            >
              {this.props.reload}
            </button>
            {this.state.error && (
              <button
                type="button"
                onClick={this.handleCopyReport}
                aria-live="polite"
                className="text-xs px-3 py-1.5 rounded-r-card border border-surface-3 text-text-muted hover:text-text-secondary hover:bg-surface-3 transition-colors focus-ring-soft tabular-nums"
              >
                {this.state.copied ? this.props.copyReportCopied : this.props.copyReport}
              </button>
            )}
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
  resetKeys?: ReadonlyArray<ResetKey>;
}

const EMPTY_RESET_KEYS: ReadonlyArray<ResetKey> = [];

export default function ErrorBoundary({ children, fallback, resetKeys = EMPTY_RESET_KEYS }: Props) {
  const { t } = useI18n();
  return (
    <ErrorBoundaryInner
      fallback={fallback}
      title={t('error.title')}
      message={t('error.message')}
      devDetailSummary={t('error.devDetailSummary')}
      tryAgain={t('error.tryAgain')}
      reload={t('error.reload')}
      copyReport={t('error.copyReport')}
      copyReportCopied={t('error.copyReportCopied')}
      resetKeys={resetKeys}
    >
      {children}
    </ErrorBoundaryInner>
  );
}
