import { useState } from 'react';
import { useMounted } from '@/lib/useMounted';
import { RecurrenceSummary } from './RecurrenceSummary';
import {
  RecurrenceRuleEditor,
  type RecurrenceRulePatch,
} from './RecurrenceRuleEditor';
import {
  parseRecurrence,
  type Translator,
} from './shared';

export type { RecurrenceRulePatch };

interface RecurrenceFieldProps {
  locale: string;
  onSave: (recurrence: RecurrenceRulePatch) => Promise<void>;
  t: Translator;
  task: { id: string; recurrence: string | null };
}

/**
 * Orchestrator for the task-detail recurrence field. Three visual
 * modes:
 *
 *   1. No persisted rule, not editing → "+ Add recurrence" button
 *   2. Persisted rule, not editing → `RecurrenceSummary` row
 *   3. Editing → `RecurrenceRuleEditor` form
 *
 * Owns the mode + sync-during-edit ("use latest" banner) state, plus
 * the snapshot semantics for `editStartRecurrence`:
 *
 * The snapshot captures `task.recurrence` at the moment edit begins.
 * Whenever the persisted value diverges from the snapshot while the
 * editor is open, the editor shows a banner offering "Use latest" /
 * "Dismiss". This means the local form state is the single source of
 * truth while editing; the banner is the only opt-in path to adopt
 * the incoming value. Comparison goes through `recurrenceStringsEqual`
 * so equivalent rules with different key orders or cosmetic whitespace
 * compare equal.
 */
export default function RecurrenceField({ task, locale, t, onSave }: RecurrenceFieldProps) {
  const existing = task.recurrence ? parseRecurrence(task.recurrence) : null;
  const [editing, setEditing] = useState(false);
  const [editStartRecurrence, setEditStartRecurrence] = useState<string | null>(null);
  const mountedRef = useMounted();

  const advancedReadOnly = existing?.editable === false;
  // Compare *parsed* recurrence semantics so a sync replay or AI
  // rewrite that produces equivalent JSON with different key order or
  // whitespace doesn't trip the banner.
  const externalUpdate =
    editing &&
    editStartRecurrence !== null &&
    !recurrenceStringsEqual(task.recurrence ?? null, editStartRecurrence);

  const openEditor = () => {
    setEditStartRecurrence(task.recurrence ?? null);
    setEditing(true);
  };

  const handleSave = async (rule: RecurrenceRulePatch) => {
    await onSave(rule);
    if (mountedRef.current) {
      setEditing(false);
      setEditStartRecurrence(null);
    }
  };

  const handleClear = async () => {
    await onSave(null);
    if (mountedRef.current) {
      setEditing(false);
      setEditStartRecurrence(null);
    }
  };

  const handleCancel = () => {
    setEditing(false);
    setEditStartRecurrence(null);
  };

  const handleAdoptLatest = () => {
    // Bump the snapshot to the current persisted value. The editor is
    // keyed on `editStartRecurrence`, so this also remounts it with
    // `initial` re-derived from the new `task.recurrence` — the
    // canonical "adopt the sync push" gesture.
    setEditStartRecurrence(task.recurrence ?? null);
  };

  const handleDismissUpdate = () => {
    setEditStartRecurrence(task.recurrence ?? null);
  };

  if (!editing) {
    if (existing) {
      return (
        <RecurrenceSummary
          rule={existing}
          locale={locale}
          t={t}
          onEdit={openEditor}
        />
      );
    }
    return (
      <button
        type="button"
        onClick={openEditor}
        className="text-xs text-text-muted hover:text-text-primary transition-colors text-start rounded-r-control focus-ring-soft"
      >
        + {t('task.recurrence.add')}
      </button>
    );
  }

  const editorInitial = (() => {
    const recurrence = task.recurrence ? parseRecurrence(task.recurrence) : null;
    return {
      freq: recurrence?.freq ?? 'WEEKLY',
      interval: recurrence?.interval ?? 1,
      byday: recurrence?.byday ?? [],
      until: recurrence?.until ?? '',
    };
  })();

  return (
    <RecurrenceRuleEditor
      // `key` remounts the editor with the adopted snapshot's initial
      // state when the user clicks "Use latest". Without the key the
      // editor's `useState` would retain the in-flight draft.
      key={editStartRecurrence ?? '__new__'}
      initial={editorInitial}
      taskRecurrence={task.recurrence}
      advancedReadOnly={advancedReadOnly}
      externalUpdate={externalUpdate}
      onSave={handleSave}
      onClear={handleClear}
      onCancel={handleCancel}
      onAdoptLatest={handleAdoptLatest}
      onDismissUpdate={handleDismissUpdate}
      t={t}
    />
  );
}

/**
 * semantic equality on the persisted recurrence JSON.
 * `parseRecurrence` canonicalizes so equivalent rules with different
 * key orders or cosmetic whitespace compare equal; then deep-equal
 * the canonical `RecurrenceRule` shape (BYDAY arrays are order-stable
 * in our writer, so a sorted string-equal is sufficient).
 */
function recurrenceStringsEqual(a: string | null, b: string | null): boolean {
  if (a === b) return true;
  if (a === null || b === null) return false;
  const parsedA = parseRecurrence(a);
  const parsedB = parseRecurrence(b);
  // If either side is unparseable (e.g. an advanced rule the editor
  // can't round-trip), fall back to raw string compare — those are
  // already handled as `editable: false` in the UI.
  if (!parsedA || !parsedB) return a === b;
  if (parsedA.freq !== parsedB.freq) return false;
  if ((parsedA.interval ?? 1) !== (parsedB.interval ?? 1)) return false;
  if ((parsedA.until ?? null) !== (parsedB.until ?? null)) return false;
  const bydayA = parsedA.byday ? [...parsedA.byday].sort() : [];
  const bydayB = parsedB.byday ? [...parsedB.byday].sort() : [];
  if (bydayA.length !== bydayB.length) return false;
  for (let i = 0; i < bydayA.length; i++) {
    if (bydayA[i] !== bydayB[i]) return false;
  }
  return true;
}
