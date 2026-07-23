import { useEffect, useRef } from 'react';
import { Editor, commandsCtx, defaultValueCtx, rootCtx } from '@milkdown/kit/core';
import { commonmark } from '@milkdown/kit/preset/commonmark';
import { gfm } from '@milkdown/kit/preset/gfm';
import { history, redoCommand, undoCommand } from '@milkdown/kit/plugin/history';
import { listener, listenerCtx } from '@milkdown/kit/plugin/listener';
import { Milkdown, useEditor } from '@milkdown/react';
import { replaceAll } from '@milkdown/utils';

import { registerEditorHistoryShortcutHandler } from '@/lib/shortcuts/editorHistory';
import { useMilkdownPlaceholderPlugin } from './placeholderPlugin';
import type { MilkdownEditorProps, MilkdownEditorGetter } from './types';
import { useMilkdownAccessibility } from './useMilkdownAccessibility';
import { useMilkdownLinkOpening } from './useMilkdownLinkOpening';

export default function MilkdownEditorInner({
  defaultValue,
  onChange,
  className,
  placeholder,
  maxLength,
  ariaLabel,
}: MilkdownEditorProps) {
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;
  const maxLengthRef = useRef(maxLength);
  maxLengthRef.current = maxLength;
  const initialValueRef = useRef(defaultValue);
  const lastEditorOutputRef = useRef(defaultValue);
  const placeholderPlugin = useMilkdownPlaceholderPlugin(placeholder);

  const { get } = useEditor((root) => {
    const editor = Editor.make()
      .config((ctx) => {
        ctx.set(rootCtx, root);
        ctx.set(defaultValueCtx, initialValueRef.current);
        ctx.get(listenerCtx).markdownUpdated((_ctx, markdown, prevMarkdown) => {
          if (markdown !== prevMarkdown) {
            const cap = maxLengthRef.current;
            const next = cap != null && markdown.length > cap
              ? markdown.slice(0, cap)
              : markdown;
            lastEditorOutputRef.current = next;
            onChangeRef.current(next);
          }
        });
      })
      .use(commonmark)
      .use(gfm)
      .use(history)
      .use(listener);
    if (placeholderPlugin) {
      editor.use(placeholderPlugin);
    }
    return editor;
  });

  const getRef = useRef<MilkdownEditorGetter>(get);
  getRef.current = get;
  const editorHasFocusRef = useRef(false);
  const wrapperRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (editorHasFocusRef.current) return;
    if (defaultValue !== lastEditorOutputRef.current) {
      const editor = get();
      if (editor) {
        try {
          editor.action(replaceAll(defaultValue));
          lastEditorOutputRef.current = defaultValue;
        } catch {
          // Editor not fully initialized yet; retry on the next effect pass.
        }
      }
    }
  }, [defaultValue, get]);

  useEffect(() => {
    const root = wrapperRef.current;
    if (!root) return;
    return registerEditorHistoryShortcutHandler(root, (action) => {
      const editor = getRef.current();
      if (!editor) return false;
      try {
        return editor.action((ctx) => ctx.get(commandsCtx).call(
          action === 'undo' ? undoCommand.key : redoCommand.key,
        ));
      } catch {
        return false;
      }
    });
  }, []);

  useMilkdownAccessibility(wrapperRef, ariaLabel);
  useMilkdownLinkOpening(wrapperRef);

  return (
    <div
      ref={wrapperRef}
      className={`milkdown-editor-wrapper ${className ?? ''}`}
      onFocus={() => { editorHasFocusRef.current = true; }}
      onBlur={() => { editorHasFocusRef.current = false; }}
      // The `group` role gives the wrapper a11y semantics matching its
      // onFocus/onBlur tracking and satisfies jsx-a11y for the interactive
      // event handlers on this otherwise-static element. `ariaLabel` is
      // required by the prop contract so the group always has an
      // accessible name.
      role="group"
      aria-label={ariaLabel}
    >
      <Milkdown />
    </div>
  );
}
