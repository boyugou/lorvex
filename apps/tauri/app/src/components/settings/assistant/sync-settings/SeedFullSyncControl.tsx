import { Button } from '@/components/ui/Button';
import { useI18n } from '@/lib/i18n';

interface SeedFullSyncControlProps {
  syncRunning: boolean;
  seedSyncRunning: boolean;
  onSeedFullSync: () => Promise<void>;
}

export function SeedFullSyncControl({
  syncRunning,
  seedSyncRunning,
  onSeedFullSync,
}: SeedFullSyncControlProps) {
  const { t } = useI18n();

  return (
    <div className="space-y-1.5">
      <p className="text-xs text-text-muted">{t('settings.seedFullSyncHint')}</p>
      <Button
        variant="outline"
        onClick={() => { void onSeedFullSync(); }}
        disabled={seedSyncRunning || syncRunning}
      >
        {seedSyncRunning ? t('settings.seedFullSyncRunning') : t('settings.seedFullSync')}
      </Button>
    </div>
  );
}
