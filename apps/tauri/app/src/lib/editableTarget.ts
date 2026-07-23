interface EditableNodeLike {
  isContentEditable?: boolean;
  nodeType?: number;
  parentElement?: EditableNodeLike | null;
  parentNode?: EditableNodeLike | null;
  tagName?: string;
}

const EDITABLE_TAGS = new Set(['INPUT', 'TEXTAREA', 'SELECT']);

function isEditableNodeLike(value: EventTarget | EditableNodeLike | null): value is EditableNodeLike {
  return typeof value === 'object' && value !== null;
}

export function isEditableTarget(target: EventTarget | null): boolean {
  if (!isEditableNodeLike(target)) return false;

  const seen = new Set<EditableNodeLike>();
  let current: EditableNodeLike | null = target;
  while (current && !seen.has(current)) {
    seen.add(current);

    if (current.isContentEditable) return true;

    const tagName = current.tagName?.toUpperCase();
    if (tagName && EDITABLE_TAGS.has(tagName)) return true;

    current = current.parentElement ?? current.parentNode ?? null;
  }

  return false;
}
