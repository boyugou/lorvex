import type { ReactNode } from 'react';

import { useI18n } from '@/lib/i18n';
import { ValidatedField } from '@/components/ui/ValidatedField';
import { TonalButton } from '@/components/ui/TonalButton';
import { useDangerZoneActions } from './useDangerZoneActions';

interface DangerZonePanelProps {
  /** Forwarded from the diagnostics controller so "Clear error logs"
   *  can live in one place (here) rather than being duplicated in the
   *  Diagnostics panel. */
  onClearErrorLogs: () => Promise<void>;
  errorLogsBusy: boolean;
}

export function DangerZonePanel({ onClearErrorLogs, errorLogsBusy }: DangerZonePanelProps) {
  const { t } = useI18n();
  const {
    busy,
    purgeBusy,
    clearChangelogBusy,
    confirmText,
    dismissResetConfirm,
    handleClearChangelog,
    handlePurgeCancelled,
    handleResetAll,
    handleResetPreferences,
    setConfirmText,
    setShowResetConfirm,
    showResetConfirm,
  } = useDangerZoneActions();

  return (
    <div className="space-y-5">
      <p className="text-xs text-text-muted leading-snug">
        {t('settings.dangerZoneIntro')}
      </p>

      {/* ── Group: Logs & history ───────────────────────────── */}
      <DangerGroup title={t('settings.dangerGroupLogs')}>
        <DangerRow
          label={t('settings.errorLogsClear')}
          description={t('settings.dangerClearErrorLogsDesc')}
          actionLabel={t('settings.errorLogsClear')}
          busy={errorLogsBusy}
          onAction={() => { void onClearErrorLogs(); }}
        />
        <DangerRow
          label={t('settings.dangerClearChangelog')}
          description={t('settings.dangerClearChangelogDesc')}
          actionLabel={t('settings.dangerClearChangelog')}
          busy={clearChangelogBusy}
          onAction={() => { void handleClearChangelog(); }}
        />
      </DangerGroup>

      {/* ── Group: Tasks & data ─────────────────────────────── */}
      <DangerGroup title={t('settings.dangerGroupData')}>
        <DangerRow
          label={t('settings.purgeCancelled')}
          description={t('settings.dangerPurgeCancelledDesc')}
          actionLabel={t('settings.purgeButton')}
          busy={purgeBusy}
          onAction={() => { void handlePurgeCancelled(); }}
        />
      </DangerGroup>

      {/* ── Group: Reset ────────────────────────────────────── */}
      <DangerGroup title={t('settings.dangerGroupReset')}>
        <DangerRow
          label={t('settings.dangerResetPrefs')}
          description={t('settings.dangerResetPrefsDesc')}
          actionLabel={t('settings.dangerResetPrefsAction')}
          busy={busy}
          onAction={() => { void handleResetPreferences(); }}
        />

        {/* Delete All Data — needs two-step confirm with typed token */}
        <div className="pt-3 border-t border-danger/20 space-y-2">
          <div className="space-y-0.5">
            <p className="text-xs text-danger font-medium">{t('settings.dangerResetAll')}</p>
            <p className="text-xs text-text-muted">{t('settings.dangerResetAllDesc')}</p>
          </div>

          {!showResetConfirm ? (
            <TonalButton
              tone="danger"
              size="lg"
              disabled={busy}
              onClick={() => setShowResetConfirm(true)}
            >
              {t('settings.dangerResetAllAction')}
            </TonalButton>
          ) : (
            <div className="mt-1 space-y-2.5 p-3 rounded-r-control border border-danger/30 bg-[var(--danger-tint-xs)]">
              <p className="text-xs text-danger font-medium">
                {t('settings.dangerResetAllConfirmPrompt')}
              </p>
              {/* a11y: surface the token mismatch live
                through aria-invalid/aria-errormessage so screen readers
                know why the confirm button stays disabled. The button
                already checks the token — that logic is unchanged —
                but the message is now announced rather than implied.
              */}
              {(() => {
                const trimmedConfirm = confirmText.trim();
                const tokenMismatch = trimmedConfirm.length > 0
                  && trimmedConfirm !== t('settings.dangerResetAllConfirmToken');
                return (
                  <ValidatedField
                    label={t('settings.dangerResetAllConfirmPrompt')}
                    showLabel={false}
                    error={tokenMismatch ? t('settings.dangerResetAllConfirmMismatch') : null}
                  >
                    {({ fieldProps }) => (
                      <input
                        {...fieldProps}
                        type="text"
                        value={confirmText}
                        onChange={(e) => setConfirmText(e.target.value)}
                        // placeholder + the required-match
                        // string both live in
                        // t('settings.dangerResetAllConfirmToken') so
                        // non-Latin-script users don't have to IME-toggle
                        // to type an English word for a destructive
                        // confirm.
                        placeholder={t('settings.dangerResetAllConfirmToken')}
                        autoFocus
                        className={`${fieldProps.className} w-full text-sm px-2.5 py-1.5 rounded-r-control border border-danger/30 bg-surface-1 text-text-primary placeholder:text-text-muted/50 focus-ring-soft-danger`}
                        aria-label={t('settings.dangerResetAllConfirmPrompt')}
                      />
                    )}
                  </ValidatedField>
                );
              })()}
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  disabled={busy || confirmText.trim() !== t('settings.dangerResetAllConfirmToken')}
                  onClick={() => { void handleResetAll(); }}
                  className="text-xs px-3 py-1.5 rounded-r-control bg-danger text-on-accent hover:bg-[var(--danger-tint-2xl)] transition-colors disabled:opacity-40 focus-ring-soft-danger"
                >
                  {busy ? t('common.saving') : t('settings.dangerResetAllConfirmAction')}
                </button>
                <button
                  type="button"
                  disabled={busy}
                  onClick={dismissResetConfirm}
                  className="text-xs px-3 py-1.5 rounded-r-control text-text-muted hover:text-text-primary transition-colors focus-ring-soft"
                >
                  {t('common.cancel')}
                </button>
              </div>
            </div>
          )}
        </div>
      </DangerGroup>
    </div>
  );
}

function DangerGroup({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="space-y-2">
      <p className="text-2xs uppercase tracking-wide text-text-muted font-medium">{title}</p>
      <div className="space-y-3">{children}</div>
    </div>
  );
}

function DangerRow({
  label,
  description,
  actionLabel,
  busy,
  onAction,
}: {
  label: string;
  description: string;
  actionLabel: string;
  busy: boolean;
  onAction: () => void;
}) {
  const { t } = useI18n();
  return (
    <div className="flex items-start justify-between gap-3">
      <div className="min-w-0 space-y-0.5">
        <p className="text-xs text-text-secondary font-medium">{label}</p>
        <p className="text-xs text-text-muted wrap-break-word">{description}</p>
      </div>
      {/* loading prop drives spinner + aria-busy, so the
          label stays stable instead of swapping to "Saving…". */}
      <TonalButton
        tone="danger"
        size="lg"
        loading={busy}
        onClick={onAction}
      >
        {busy ? t('common.saving') : actionLabel}
      </TonalButton>
    </div>
  );
}
