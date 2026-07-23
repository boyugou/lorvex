import { useMemo, useState, type ReactNode } from 'react';
import { useMounted } from '@/lib/useMounted';
import { getTagColor } from '@/lib/tags/colors';
import { XIcon } from '@/components/ui/icons';
import { Tooltip } from '@/components/ui/Tooltip';
import { isImeComposing } from '@/lib/ime';

import { type Translator } from './shared';

export function MetaField({ label, value, className = '' }: { label: string; value: string; className?: string }) {
  return (
    <div>
      <span className="text-text-muted/60 text-2xs font-medium">{label}</span>
      <p className={`text-sm text-text-secondary ${className}`}>{value}</p>
    </div>
  );
}

export function InlineEditField({ label, display, displayClass = 'text-text-secondary', children }: {
  label: string;
  display: ReactNode;
  displayClass?: string;
  children: (close: () => void) => ReactNode;
}) {
  const [editing, setEditing] = useState(false);
  const inlineEditFieldMountedRef = useMounted();

  const close = () => {
    if (!inlineEditFieldMountedRef.current) return;
    setEditing(false);
  };

  return (
    <div>
      <span className="text-text-muted/60 text-2xs font-medium" aria-hidden="true">{label}</span>
      {editing ? (
        <div className="mt-0.5">{children(close)}</div>
      ) : (
        <button
          type="button"
          onClick={() => setEditing(true)}
          aria-label={label}
          className={`block text-xs mt-0.5 text-start w-full px-2.5 py-1.5 rounded-r-control bg-surface-2/60 border border-card hover:bg-surface-2 hover:border-accent/30 cursor-pointer transition-colors focus-ring-soft ${displayClass}`}
        >
          {display}
        </button>
      )}
    </div>
  );
}

export function TagsField({ tags, t, onSave }: {
  tags: string[];
  t: Translator;
  onSave: (tags: string[]) => Promise<void>;
}) {
  const [input, setInput] = useState('');
  const [editing, setEditing] = useState(false);
  const tagsFieldMountedRef = useMounted();

  // precompute the per-tag colour list once per `tags` change.
  // `getTagColor` is total + deterministic, but invoking it inline on
  // every render means re-hashing each tag name on every keystroke (the
  // input below re-renders the whole TagsField). Memoise to keep the
  // chip list stable when the user is typing into the add-tag input.
  const tagColors = useMemo(() => tags.map((tag) => ({ tag, color: getTagColor(tag) })), [tags]);

  const removeTag = async (tag: string) => {
    await onSave(tags.filter((item) => item !== tag));
  };

  const addTag = async () => {
    const trimmed = input.trim().toLowerCase();
    if (trimmed && !tags.includes(trimmed)) {
      await onSave([...tags, trimmed]);
    }
    if (tagsFieldMountedRef.current) {
      setInput('');
      setEditing(false);
    }
  };

  return (
    <div>
      <div className="flex flex-wrap gap-1.5 items-center">
        {tagColors.map(({ tag, color }) => {
          return (
            <span
              key={tag}
              title={tag}
              className={`group/tag relative flex max-w-full min-w-0 items-center gap-1.5 text-xs font-medium border-s-2 ${color.border} ${color.bg} ${color.text} ps-2 pe-2 py-1 rounded-r-control transition-colors`}
            >
              <span className="select-text-content min-w-0 truncate">{tag}</span>
              <Tooltip label={t('task.removeTag')}>
                <button
                  type="button"
                  onClick={() => removeTag(tag)}
                  aria-label={`${t('task.removeTag')}: ${tag}`}
                  // the reveal
                  // animation (width 0 ↔ 0.875rem, opacity 0 ↔ 1)
                  // lives on the inner `.tag-x-glyph` wrapper. The
                  // button hosts the WCAG 2.5.8 24×24 pointer target
                  // via the `.tag-x-button::before` overlay (constant
                  // 24×24 centred on the button so the hit target is
                  // invariant to the reveal animation), and the
                  // focus-visible outline is rendered on that overlay
                  // (not the animating button) so the ring traces the
                  // stable hit-target frame. See `.tag-x-button` /
                  // `.tag-x-glyph` in `index.css`.
                  className="tag-x-button text-text-muted hover:text-danger leading-none rounded-r-control focus-visible:outline-hidden shrink-0"
                >
                  <span className="tag-x-glyph" aria-hidden="true">
                    {/* align icon to the CSS reveal width
                        (`.tag-x-glyph` width=0.875rem = 14px) so
                        the glyph fills the revealed slot exactly. */}
                    <XIcon className="w-3.5 h-3.5" />
                  </span>
                </button>
              </Tooltip>
            </span>
          );
        })}
        {editing ? (
          <input
            autoFocus
            value={input}
            onChange={(event) => setInput(event.target.value)}
            onKeyDown={async (event) => {
              if ((event.key === 'Enter' || event.key === ',') && !isImeComposing(event)) {
                event.preventDefault();
                await addTag();
              }
              if (event.key === 'Escape') {
                setInput('');
                setEditing(false);
              }
            }}
            onBlur={addTag}
            placeholder={t('task.addTag')}
            className="text-xs bg-surface-2/60 border border-accent/30 rounded-r-control px-2 py-1 text-text-primary outline-hidden ring-1 ring-accent/20 w-24"
          />
        ) : (
          <button
            type="button"
            onClick={() => setEditing(true)}
            className="text-xs text-text-muted/60 hover:text-text-muted border border-dashed border-card hover:border-accent/30 hover:bg-surface-2/40 px-2 py-1 rounded-r-control transition-[color,background-color,border-color] duration-150 focus-ring-strong"
          >
            + {t('task.addTag')}
          </button>
        )}
      </div>
    </div>
  );
}
