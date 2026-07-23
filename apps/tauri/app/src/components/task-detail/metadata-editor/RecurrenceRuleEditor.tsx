import { useId, useRef, useState } from 'react';
import { DatePicker } from '@/components/ui/DatePicker';
import { Banner } from '@/components/ui/Banner';
import { useMounted } from '@/lib/useMounted';
import { RECURRENCE_INTERVAL_MAX, RECURRENCE_INTERVAL_MIN } from '@/lib/recurrenceInterval';
import { RecurrencePresets } from './RecurrencePresets';
import {
  normalizeRecurrenceIntervalValue,
  type RecurrenceRule,
  type Translator,
} from './shared';

/**
 * Structured recurrence rule patch the editor emits via `onSave`.
 * Mirrors the typed `RecurrenceRuleArgs` shape every write surface
 * (Tauri `update_task`, MCP `update_task` / `set_recurrence`)
 * accepts. `null` clears the rule.
 */
export type RecurrenceRulePatch =
  | {
      FREQ: 'DAILY' | 'WEEKLY' | 'MONTHLY' | 'YEARLY';
      INTERVAL: number;
      BYDAY?: string[];
      UNTIL?: string;
    }
  | null;

/**
 * The full recurrence editor form: presets + UNTIL picker + save /
 * remove / cancel buttons + the "synced during edit" banner that fires
 * when the persisted rule changes mid-edit. Read-only mode (when the
 * persisted rule is an advanced rule the local editor can't
 * round-trip) hides the presets and only shows remove/cancel.
 */
export function RecurrenceRuleEditor({
  initial,
  taskRecurrence,
  advancedReadOnly,
  externalUpdate,
  onSave,
  onClear,
  onCancel,
  onAdoptLatest,
  onDismissUpdate,
  t,
}: {
  initial: { freq: RecurrenceRule['freq']; interval: number; byday: string[]; until: string };
  taskRecurrence: string | null;
  advancedReadOnly: boolean;
  externalUpdate: boolean;
  onSave: (rule: RecurrenceRulePatch) => Promise<void>;
  onClear: () => Promise<void>;
  onCancel: () => void;
  onAdoptLatest: () => void;
  onDismissUpdate: () => void;
  t: Translator;
}) {
  // The form keeps its local state authoritative while editing. The
  // outer `RecurrenceField` orchestrator passes `initial` only on
  // mount; subsequent sync pushes flow through `externalUpdate` +
  // `onAdoptLatest` rather than overwriting the in-flight draft.
  const [freq, setFreq] = useState<RecurrenceRule['freq']>(initial.freq);
  const [repeatInterval, setRepeatInterval] = useState<number>(initial.interval);
  const [byday, setByday] = useState<string[]>(initial.byday);
  const [until, setUntil] = useState<string>(initial.until);
  const [saving, setSaving] = useState(false);
  const mountedRef = useMounted();

  // a11y: thread aria-invalid through the interval input so AT hears
  // "invalid" when the value falls outside the shared recurrence interval range. The onChange
  // logic silently clamps illegal values, but we still want to
  // signal *why* the displayed value doesn't match what the user
  // typed.
  const intervalErrorId = useId();
  const intervalInvalid =
    !Number.isInteger(repeatInterval)
    || repeatInterval < RECURRENCE_INTERVAL_MIN
    || repeatInterval > RECURRENCE_INTERVAL_MAX;

  const toggleDay = (code: string) => {
    setByday((prev) => (prev.includes(code) ? prev.filter((day) => day !== code) : [...prev, code]));
  };

  const handleSave = async () => {
    if (advancedReadOnly) {
      onCancel();
      return;
    }
    setSaving(true);
    try {
      const rule: RecurrenceRulePatch = {
        FREQ: freq,
        INTERVAL: normalizeRecurrenceIntervalValue(repeatInterval),
      };
      if (freq === 'WEEKLY' && byday.length > 0) rule.BYDAY = byday;
      if (until) rule.UNTIL = until;
      await onSave(rule);
    } finally {
      if (mountedRef.current) {
        setSaving(false);
      }
    }
  };

  const handleClear = async () => {
    setSaving(true);
    try {
      await onClear();
    } finally {
      if (mountedRef.current) {
        setSaving(false);
      }
    }
  };

  return (
    <div className="bg-surface-3/50 rounded-r-control p-3 space-y-3">
      <p className="text-xs font-medium text-text-secondary">{t('task.recurrence')}</p>

      {externalUpdate && (
        <Banner
          tone="warning"
          actions={
            <>
              <button
                type="button"
                onClick={onAdoptLatest}
                className="text-2xs px-2 py-0.5 rounded-r-control chip-warning chip-warning-interactive focus-ring-soft"
              >
                {t('task.recurrence.useLatest')}
              </button>
              <button
                type="button"
                onClick={onDismissUpdate}
                className="text-2xs px-2 py-0.5 rounded-r-control text-text-muted hover:text-text-primary transition-colors focus-ring-soft"
              >
                {t('task.recurrence.dismissUpdate')}
              </button>
            </>
          }
        >
          {t('task.recurrence.syncedDuringEdit')}
        </Banner>
      )}

      {!advancedReadOnly && (
        <>
          <RecurrencePresets
            freq={freq}
            setFreq={setFreq}
            repeatInterval={repeatInterval}
            setRepeatInterval={setRepeatInterval}
            byday={byday}
            toggleDay={toggleDay}
            intervalInvalid={intervalInvalid}
            intervalErrorId={intervalErrorId}
            t={t}
          />

          <RecurrenceUntilPicker
            until={until}
            setUntil={setUntil}
            t={t}
          />
        </>
      )}

      <div className="flex gap-2">
        {!advancedReadOnly && (
          <button
            type="button"
            onClick={handleSave}
            disabled={saving}
            className="text-xs px-2.5 py-1 rounded-r-control bg-accent text-on-accent active:scale-[0.97] hover:opacity-90 disabled:opacity-60 transition-opacity focus-ring-strong"
          >
            {saving ? t('common.saving') : t('common.save')}
          </button>
        )}
        <button
          type="button"
          onClick={handleClear}
          disabled={saving || !taskRecurrence}
          className="text-xs px-2.5 py-1 rounded-r-control border border-surface-3 text-text-muted hover:text-danger hover:border-danger/50 disabled:opacity-50 transition-colors focus-ring-soft"
        >
          {t('common.remove')}
        </button>
        <button
          type="button"
          onClick={onCancel}
          disabled={saving}
          className="text-xs px-2.5 py-1 rounded-r-control border border-surface-3 text-text-muted hover:text-text-primary transition-colors focus-ring-soft"
        >
          {t('common.cancel')}
        </button>
      </div>
    </div>
  );
}

function RecurrenceUntilPicker({ until, setUntil, t }: {
  until: string;
  setUntil: (v: string) => void;
  t: Translator;
}) {
  const [open, setOpen] = useState(false);
  const anchorRef = useRef<HTMLButtonElement>(null);

  return (
    <div className="flex items-center gap-2">
      <span className="text-xs text-text-muted">{t('task.recurrence.until')}</span>
      <button
        ref={anchorRef}
        type="button"
        onClick={() => setOpen(true)}
        className="bg-surface-2 border border-surface-3 rounded-r-control px-2 py-0.5 text-xs text-text-primary hover:border-accent/50 transition-colors"
      >
        {until || '—'}
      </button>
      {until && (
        <button
          type="button"
          onClick={() => setUntil('')}
          className="text-xs text-text-muted hover:text-danger transition-colors rounded-r-control focus-ring-soft"
        >
          {t('quickdate.clear')}
        </button>
      )}
      {open && (
        <DatePicker
          value={until || null}
          onChange={(date) => { setUntil(date ?? ''); }}
          onClose={() => setOpen(false)}
          anchorRef={anchorRef}
          showQuickChips={false}
          popoverLayer="modalPopover"
        />
      )}
    </div>
  );
}
