import { MilkdownProvider } from '@milkdown/react';

import MilkdownEditorInner from './MilkdownEditorInner';
import type { MilkdownEditorProps } from './types';

/**
 * WYSIWYG Markdown editor powered by Milkdown (prosemirror + remark).
 * Supports headings, lists, checkboxes, formatting, links, blockquotes, and
 * auto-continuation of list items.
 */
export default function MilkdownEditor(props: MilkdownEditorProps) {
  return (
    <MilkdownProvider>
      <MilkdownEditorInner {...props} />
    </MilkdownProvider>
  );
}
