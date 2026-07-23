import { useCallback, useEffect, useState } from 'react';

import { reportClientError } from '@/lib/errors/errorLogging';
import {
  clampHideCompletedOlderThanDays,
  DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS,
  parseHideCompletedOlderThanDays,
} from '@/lib/hideCompletedOlderThan';
import { usePreferenceMutationWithUndo } from '@/lib/hooks/usePreferenceMutationWithUndo';
import {
  PREF_AI_CHANGELOG_RETENTION_POLICY,
  PREF_ERROR_LOG_RETENTION_DAYS,
  PREF_HIDE_COMPLETED_OLDER_THAN_DAYS,
} from '@/lib/preferences/keys';
import { usePreference } from '@/lib/query/usePreference';
import { parseRetentionDaysPreference } from './retentionSettings.logic';

export function useRetentionSettingsController() {
  const changelogPreference = usePreference(
    PREF_AI_CHANGELOG_RETENTION_POLICY,
    parseRetentionDaysPreference,
  );
  const errorLogPreference = usePreference(
    PREF_ERROR_LOG_RETENTION_DAYS,
    parseRetentionDaysPreference,
  );
  const hideCompletedPreference = usePreference(
    PREF_HIDE_COMPLETED_OLDER_THAN_DAYS,
    parseHideCompletedOlderThanDays,
  );

  const [changelogDays, setChangelogDays] = useState<number | null>(null);
  const [errorLogDays, setErrorLogDays] = useState<number | null>(null);
  const [hideCompletedDays, setHideCompletedDays] = useState<number>(
    DEFAULT_HIDE_COMPLETED_OLDER_THAN_DAYS,
  );
  const [saving, setSaving] = useState(false);

  // per-preference undo toasts. Each mutation captures its own
  // previous value snapshot; the Undo button on the success toast
  // writes it back through the same IPC.
  const { run: runChangelogUndo } = usePreferenceMutationWithUndo({
    key: PREF_AI_CHANGELOG_RETENTION_POLICY,
    errorKeyPrefix: 'settings.retention.changelog',
  });
  const { run: runErrorLogUndo } = usePreferenceMutationWithUndo({
    key: PREF_ERROR_LOG_RETENTION_DAYS,
    errorKeyPrefix: 'settings.retention.errorLog',
  });
  const { run: runHideCompletedUndo } = usePreferenceMutationWithUndo({
    key: PREF_HIDE_COMPLETED_OLDER_THAN_DAYS,
    errorKeyPrefix: 'settings.retention.hideCompleted',
  });

  useEffect(() => {
    setChangelogDays(changelogPreference.value);
  }, [changelogPreference.value]);

  useEffect(() => {
    setErrorLogDays(errorLogPreference.value);
  }, [errorLogPreference.value]);

  useEffect(() => {
    setHideCompletedDays(hideCompletedPreference.value);
  }, [hideCompletedPreference.value]);

  const runWithBusy = useCallback(async <V,>(
    run: (next: V) => Promise<void>,
    next: V,
    errorKey: string,
  ) => {
    setSaving(true);
    try {
      await run(next);
    } catch (error) {
      reportClientError(errorKey, 'Failed to save retention preference', error);
    } finally {
      setSaving(false);
    }
  }, []);

  const handleChangelogRetention = useCallback((days: number | null) => {
    setChangelogDays(days);
    void runWithBusy<number | null>(runChangelogUndo, days, 'settings.retention.changelog');
  }, [runWithBusy, runChangelogUndo]);

  const handleErrorLogRetention = useCallback((days: number | null) => {
    setErrorLogDays(days);
    void runWithBusy<number | null>(runErrorLogUndo, days, 'settings.retention.errorLog');
  }, [runWithBusy, runErrorLogUndo]);

  const handleHideCompletedDays = useCallback((days: number) => {
    const clamped = clampHideCompletedOlderThanDays(days);
    setHideCompletedDays(clamped);
    void runWithBusy<number>(runHideCompletedUndo, clamped, 'settings.retention.hideCompleted');
  }, [runWithBusy, runHideCompletedUndo]);

  const loaded = !changelogPreference.isLoading &&
    !errorLogPreference.isLoading &&
    !hideCompletedPreference.isLoading;
  const isSaving = saving ||
    changelogPreference.isSaving ||
    errorLogPreference.isSaving ||
    hideCompletedPreference.isSaving;

  return {
    changelogDays,
    errorLogDays,
    hideCompletedDays,
    handleChangelogRetention,
    handleErrorLogRetention,
    handleHideCompletedDays,
    loaded,
    saving: isSaving,
  };
}
