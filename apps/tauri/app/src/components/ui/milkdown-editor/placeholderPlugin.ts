import { useMemo, useRef } from 'react';
import { Plugin } from '@milkdown/kit/prose/state';
import { Decoration, DecorationSet } from '@milkdown/kit/prose/view';
import { $prose } from '@milkdown/utils';

export function useMilkdownPlaceholderPlugin(placeholder: string | undefined) {
  const placeholderRef = useRef(placeholder);
  placeholderRef.current = placeholder;

  return useMemo(() => {
    if (!placeholder) return null;
    return $prose(() => new Plugin({
      props: {
        decorations(state) {
          const doc = state.doc;
          if (doc.childCount === 1 && doc.firstChild?.isTextblock && doc.firstChild.content.size === 0) {
            const decoration = Decoration.node(0, doc.firstChild.nodeSize, {
              class: 'is-editor-empty',
              'data-placeholder': placeholderRef.current ?? '',
            });
            return DecorationSet.create(doc, [decoration]);
          }
          return DecorationSet.empty;
        },
      },
    }));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [!!placeholder]);
}
