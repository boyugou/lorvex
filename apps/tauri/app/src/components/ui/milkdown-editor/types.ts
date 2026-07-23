import type { Editor } from '@milkdown/kit/core';

export interface MilkdownEditorProps {
  /** Initial markdown content. */
  defaultValue: string;
  /** Called when the markdown content changes (debounced by the consumer). */
  onChange: (markdown: string) => void;
  /** Additional CSS class for the editor container. */
  className?: string;
  /** Placeholder text shown when the editor is empty. */
  placeholder?: string;
  /**
   * Accessible name for the editor surface: the Milkdown wrapper renders as a
   * contenteditable region, so consumers provide a plain-prose label that
   * matches the pre-Suspense fallback. Required so the `role="group"` wrapper
   * always has an accessible name — a group landmark without a name defeats
   * its purpose.
   */
  ariaLabel: string;
  /**
   * Maximum markdown character length. Mirrors the backend body cap so the
   * consumer draft state stays aligned with what sync will accept.
   */
  maxLength?: number;
}

export type MilkdownEditorGetter = () => Editor | undefined;
