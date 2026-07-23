import { useEffect, useState } from 'react';
import { getDiagnosticsVersions } from '@/lib/ipc/settings';
import type { DiagnosticsVersions } from '@/lib/ipc/settings';
import { useI18n } from '@/lib/i18n';
import { reportClientError } from '@/lib/errors/errorLogging';
import { safeWriteToClipboard } from '@/lib/platform/safeClipboard';
import { toast } from '@/lib/notifications/toast';
import { BUILD_SHA_RAW, BUILD_SHA_SHORT } from '@/lib/build/version';
import { SettingsSection } from '../SettingsPrimitives';

// GitHub repo root for the Build SHA hyperlink — wired in vite.config.ts.
// `<REPO_URL>/commit/<full SHA>` lands on the exact commit GitHub renders
// for this binary. The link is suppressed when the SHA wears a `-dirty`
// suffix (`git rev-parse` saw uncommitted changes at build time) because
// there's no published commit to point at.
const REPO_URL = (import.meta.env.VITE_REPO_URL as string | undefined) ?? '';
const BUILD_SHA_IS_PUBLISHED =
  !!BUILD_SHA_RAW && BUILD_SHA_RAW !== 'unknown' && !BUILD_SHA_RAW.endsWith('-dirty');
const BUILD_SHA_COMMIT_URL =
  BUILD_SHA_IS_PUBLISHED && REPO_URL ? `${REPO_URL}/commit/${BUILD_SHA_RAW}` : '';


export function buildAboutVersionsLine(
  versions: DiagnosticsVersions,
  buildShaShort: string,
): string {
  return (
    `Lorvex app v${versions.app_version}` +
    ` (build ${buildShaShort})` +
    ` / MCP v${versions.mcp_server_version}` +
    ` / schema ${versions.schema_version}` +
    ` / payload-schema ${versions.payload_schema_version}`
  );
}

export function AboutPanel({ appVersion }: { appVersion?: string | null | undefined }) {
  const { t } = useI18n();
  const [versions, setVersions] = useState<DiagnosticsVersions | null>(null);

  useEffect(() => {
    let cancelled = false;
    getDiagnosticsVersions()
      .then((v) => {
        if (!cancelled) setVersions(v);
      })
      .catch((error) => {
        reportClientError(
          'settings.about.versions',
          'Failed to load diagnostics versions',
          error,
          undefined,
          'warn',
        );
      });
    return () => {
      cancelled = true;
    };
  }, []);

  // prefer the backend-reported version (drawn from
  // `env!("CARGO_PKG_VERSION")` at build time of the Tauri binary).
  // Fall back to the `appVersion` prop (sourced from the Tauri
  // `getVersion` API) so the panel still shows something even when
  // the diagnostics command hasn't resolved yet.
  const resolvedAppVersion = versions?.app_version ?? appVersion ?? '';

  const copyVersionsLine = async () => {
    if (!versions) return;
    const line = buildAboutVersionsLine(versions, BUILD_SHA_SHORT);
    const result = await safeWriteToClipboard(line, 'settings.about.copyVersions');
    if (result.ok) {
      toast.success(t('settings.aboutVersionsCopied'));
    } else {
      // surface the failure to the user instead of silently
      // dropping it. Otherwise a clipboard rejection (sandbox, permission,
      // missing Tauri bridge) leaves the user staring at an unchanged
      // button with no feedback.
      // when the clipboard helper detects a permission/sandbox
      // failure it returns a recovery hint; surface it as a follow-up
      // info toast so the user has an actionable next step instead of an
      // opaque "Error" message.
      toast.errorWithDetail(result.error, t('settings.aboutVersionsCopyFailed'));
      if (result.recoveryHint) {
        toast.info(t('settings.clipboardCopyHint'));
      }
    }
  };

  return (
    <SettingsSection
      title={t('settings.about')}
      description=""
    >
      <div className="space-y-3">
        <div className="flex items-baseline gap-2">
          <span className="text-sm font-medium text-text-primary">Lorvex</span>
          <span className="text-xs text-text-muted">
            {resolvedAppVersion ? `v${resolvedAppVersion}` : ''}
          </span>
        </div>

        <div className="text-2xs text-text-muted font-mono">
          <span className="font-sans">{t('settings.aboutBuild')}:</span>{' '}
          {BUILD_SHA_COMMIT_URL ? (
            <a
              href={BUILD_SHA_COMMIT_URL}
              target="_blank"
              rel="noopener noreferrer"
              title={BUILD_SHA_RAW || BUILD_SHA_SHORT}
              aria-label={t('settings.aboutBuildCommitLink')}
              className="text-accent hover:underline focus-ring-soft rounded-r-control"
            >
              {BUILD_SHA_SHORT}
            </a>
          ) : (
            <span title={BUILD_SHA_RAW || BUILD_SHA_SHORT}>{BUILD_SHA_SHORT}</span>
          )}
        </div>

        {versions && (
          <div className="flex flex-wrap items-center gap-2 text-2xs text-text-muted">
            <span>
              {t('settings.aboutMcpRuntimeVersion')}: {versions.mcp_server_version}
            </span>
            <span className="text-text-muted/40">·</span>
            <span>
              {t('settings.aboutSchemaVersion')}: {versions.schema_version}
            </span>
            <span className="text-text-muted/40">·</span>
            <span>
              {t('settings.aboutPayloadSchemaVersion')}: {versions.payload_schema_version}
            </span>
            <button
              type="button"
              onClick={() => {
                void copyVersionsLine();
              }}
              className="ms-1 text-accent hover:underline focus-ring-soft rounded-r-control"
            >
              {t('settings.aboutCopyVersions')}
            </button>
          </div>
        )}

        <p className="text-xs text-text-secondary leading-relaxed">{t('settings.aboutText')}</p>

        <div className="flex flex-wrap items-center gap-3 text-xs text-text-muted">
          {/* keep `Apache-2.0` as a literal SPDX
              identifier rather than a t() key. SPDX identifiers are
              case-sensitive ASCII tokens that machines (GitHub,
              package registries, license-scanning tools) parse
              verbatim — translating them would either drift from the
              SPDX specification or force the i18n bundle to encode
              the same canonical token in every locale, which is
              indistinguishable from a literal. The license LINK label
              (e.g. "License") would belong in i18n; the identifier
              itself stays in the source. */}
          <span>Apache-2.0</span>
          <span className="text-text-muted/40">|</span>
          <a
            href="https://github.com/boyugou/ai-native-todo"
            target="_blank"
            rel="noopener noreferrer"
            className="text-accent hover:underline focus-ring-soft rounded-r-control"
          >
            GitHub
          </a>
          <span className="text-text-muted/40">|</span>
          <a
            href="https://github.com/boyugou/ai-native-todo/issues"
            target="_blank"
            rel="noopener noreferrer"
            className="text-accent hover:underline focus-ring-soft rounded-r-control"
          >
            {t('settings.aboutFeedback')}
          </a>
        </div>
      </div>
    </SettingsSection>
  );
}
