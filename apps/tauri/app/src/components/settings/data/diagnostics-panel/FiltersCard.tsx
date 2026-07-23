import { useCallback, useId, useMemo, useRef } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getDiagnosticsDeviceIds } from '@/lib/ipc/diagnostics';
import { useI18n } from '@/lib/i18n';
import { ToggleChip } from '@/components/ui/ToggleChip';
import {
  handleRovingRadioGroupKeyDown,
  handleRovingRadioSpaceKey,
} from '@/components/ui/radioGroupKeyboard';
import {
  buildDiagnosticsDeviceIdsQueryConfig,
  type DiagnosticsTimeWindowPreset,
} from '../diagnostics.logic';

export function FiltersCard({
  deviceScope,
  onDeviceScopeChange,
  onTimeWindowChange,
  timeWindow,
}: {
  deviceScope: string;
  onDeviceScopeChange: (next: string) => void;
  onTimeWindowChange: (next: DiagnosticsTimeWindowPreset) => void;
  timeWindow: DiagnosticsTimeWindowPreset;
}) {
  const { t } = useI18n();
  const deviceScopeSelectId = useId();
  const timeWindowLabelId = useId();

  return (
    <div className="bg-surface-2/60 border border-surface-3 rounded-r-card p-3.5 space-y-3">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <p id={timeWindowLabelId} className="text-xs text-text-secondary font-medium">
          {t('diagnostics.timeWindow.label')}
        </p>
        <TimeWindowPicker
          labelledBy={timeWindowLabelId}
          value={timeWindow}
          onChange={onTimeWindowChange}
        />
      </div>
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <label
          htmlFor={deviceScopeSelectId}
          className="text-xs text-text-secondary font-medium"
        >
          {t('diagnostics.deviceScope.label')}
        </label>
        <DeviceScopeFilter
          id={deviceScopeSelectId}
          value={deviceScope}
          onChange={onDeviceScopeChange}
        />
      </div>
    </div>
  );
}

function TimeWindowPicker({
  labelledBy,
  value,
  onChange,
}: {
  labelledBy: string;
  value: DiagnosticsTimeWindowPreset;
  onChange: (next: DiagnosticsTimeWindowPreset) => void;
}) {
  const { t } = useI18n();
  const radioRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const options: Array<{ key: DiagnosticsTimeWindowPreset; label: string }> = useMemo(() => [
    { key: 'hour', label: t('diagnostics.timeWindow.lastHour') },
    { key: 'day', label: t('diagnostics.timeWindow.last24h') },
    { key: 'week', label: t('diagnostics.timeWindow.last7d') },
    { key: 'all', label: t('diagnostics.timeWindow.allTime') },
  ], [t]);
  const selectedIndex = options.findIndex((option) => option.key === value);
  const selectAtIndex = useCallback((index: number) => {
    const option = options[index];
    if (!option) return;
    onChange(option.key);
  }, [onChange, options]);
  const focusAtIndex = useCallback((index: number) => {
    radioRefs.current[index]?.focus();
  }, []);
  return (
    <div
      role="radiogroup"
      aria-labelledby={labelledBy}
      onKeyDown={(event) => {
        handleRovingRadioGroupKeyDown({
          currentIndex: selectedIndex,
          focusOption: focusAtIndex,
          key: event.key,
          onSelect: selectAtIndex,
          optionCount: options.length,
          preventDefault: () => event.preventDefault(),
        });
      }}
      className="inline-flex rounded-r-control bg-surface-1 border border-surface-3 p-0.5"
    >
      {options.map((opt, index) => {
        const selected = value === opt.key;
        return (
          <ToggleChip
            ref={(element) => { radioRefs.current[index] = element; }}
            key={opt.key}
            size="sm"
            role="radio"
            aria-checked={selected}
            tabIndex={selected ? 0 : -1}
            onClick={() => onChange(opt.key)}
            onKeyDown={(event) => {
              handleRovingRadioSpaceKey({
                key: event.key,
                onSelect: () => onChange(opt.key),
                preventDefault: () => event.preventDefault(),
              });
            }}
            selected={selected}
            className="px-2.5"
          >
            {opt.label}
          </ToggleChip>
        );
      })}
    </div>
  );
}

function DeviceScopeFilter({
  id,
  value,
  onChange,
}: {
  id: string;
  value: string;
  onChange: (next: string) => void;
}) {
  const { t } = useI18n();
  const { data } = useQuery<string[]>({
    ...buildDiagnosticsDeviceIdsQueryConfig(),
    queryFn: ({ signal }) => getDiagnosticsDeviceIds(signal),
  });
  const deviceIds = data ?? [];
  return (
    <select
      data-theme-form-control="true"
      id={id}
      value={value}
      onChange={(event) => onChange(event.target.value)}
      className="text-xs px-2.5 py-1.5 rounded-r-control bg-surface-1 border border-surface-3 text-text-secondary focus-ring-soft"
    >
      <option value="">{t('diagnostics.deviceScope.allDevices')}</option>
      {deviceIds.map((id) => (
        <option key={id} value={id}>
          {id}
        </option>
      ))}
    </select>
  );
}
