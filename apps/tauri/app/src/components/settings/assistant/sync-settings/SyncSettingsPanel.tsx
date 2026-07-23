import { useId, useState } from 'react';

import { useI18n } from '@/lib/i18n';
import { SettingsSection } from '@/components/settings/SettingsPrimitives';
import type { AssistantSyncSettingsModel } from '../types';
import { SyncDiagnosticsPanel } from './SyncDiagnosticsPanel';
import { SyncMethodCard } from './SyncMethodCard';
import { SyncQueuePreview } from './SyncQueuePreview';

export interface SyncSettingsPanelProps {
  sync: AssistantSyncSettingsModel;
}

export function SyncSettingsPanel({ sync }: SyncSettingsPanelProps) {
  const { t } = useI18n();
  const [devToolsOpen, setDevToolsOpen] = useState(false);
  const devToolsPanelId = useId();

  return (
    <SettingsSection
      title={t('settings.sync')}
      description={t('settings.syncDesc')}
    >
      <div className="space-y-3">
        <SyncMethodCard sync={sync} />

        <button
          type="button"
          onClick={() => setDevToolsOpen((prev) => !prev)}
          aria-expanded={devToolsOpen}
          aria-controls={devToolsPanelId}
          className="text-xs text-text-muted hover:text-text-secondary focus-ring-soft transition-colors"
        >
          {devToolsOpen ? t('settings.hideDeveloperTools') : t('settings.showDeveloperTools')}
        </button>

        <div
          id={devToolsPanelId}
          hidden={!devToolsOpen}
          className="space-y-3 opacity-70"
        >
          {devToolsOpen && (
            <>
              {sync.syncStateBadge && (
                <div>
                  <span className={`text-xs px-2 py-1 rounded-r-control ${sync.syncStateBadge.className}`}>
                    {sync.syncStateBadge.label}
                  </span>
                </div>
              )}
              <SyncDiagnosticsPanel sync={sync} />
              <SyncQueuePreview sync={sync} />
            </>
          )}
        </div>
      </div>
    </SettingsSection>
  );
}
