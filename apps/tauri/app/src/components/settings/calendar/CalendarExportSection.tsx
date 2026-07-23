import { useState } from 'react';
import { exportCalendarIcs } from '@/lib/ipc/calendar';
import { useI18n } from '@/lib/i18n';
import { toast } from '@/lib/notifications/toast';
import { reportClientError } from '@/lib/errors/errorLogging';
import { SettingsSection } from '../SettingsPrimitives';

export function CalendarExportSection() {
  const { t } = useI18n();
  const [exporting, setExporting] = useState(false);

  const handleExport = async () => {
    setExporting(true);
    try {
      // Export all events (wide range)
      const from = '2020-01-01';
      const to = '2030-12-31';
      const icsContent = await exportCalendarIcs(from, to);
      const blob = new Blob([icsContent], { type: 'text/calendar;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      const stamp = new Date().toISOString().replace(/[:.]/g, '-');
      anchor.href = url;
      anchor.download = `lorvex-calendar-${stamp}.ics`;
      anchor.click();
      URL.revokeObjectURL(url);
      toast.success(t('calendar.exportIcsSuccess'));
    } catch (error) {
      reportClientError('settings.exportIcs', 'Failed to export calendar as .ics', error);
      // route through errorWithDetail so disk-full sentinels
      // and Rust-internal leakage get redacted while genuine reasons
      // (permission denied on the chosen directory, invalid date range)
      // still reach the user.
      toast.errorWithDetail(error, t('calendar.exportIcsError'));
    } finally {
      setExporting(false);
    }
  };

  return (
    <SettingsSection title={t('calendar.exportIcs')}>
      <button
        type="button"
        disabled={exporting}
        onClick={() => { void handleExport(); }}
        className="text-xs px-3 py-1.5 rounded-r-control bg-surface-1 border border-surface-3 text-text-secondary hover:bg-surface-3 disabled:opacity-50 disabled:cursor-not-allowed transition-colors focus-ring-soft"
      >
        {exporting ? t('common.saving') : t('calendar.exportIcs')}
      </button>
    </SettingsSection>
  );
}
