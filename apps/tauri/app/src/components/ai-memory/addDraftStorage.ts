// Persisted "+ Add memory" draft. When memory-lock blur snaps the
// view shut mid-typing, the in-flight key/content is stashed under
// this localStorage key and rehydrated on the next unlock so users
// never lose half-typed entries. Cleared on successful save or
// explicit Cancel.
//
// Only real user input reaches this stash. `writeStoredDraft` is
// reachable only from inside `AddMemoryForm`'s `hasUserInput`-gated
// mirror effect: the controller never calls it directly, and the CTA
// seed path (`onOpenAddForm`) goes through `setAddFormDraft`
// in-memory only (no localStorage write). An ephemeral CTA pre-fill
// (e.g. clicking an empty-cluster row, which seeds `{key: "people.",
// content: ""}`) therefore leaves no localStorage residue if the
// user abandons the form without typing. `readStoredDraft`
// additionally trims both fields and drops an entry where both are
// blank as a belt-and-braces guard against any stray pre-fill that
// somehow bypassed the in-form gate.
const ADD_MEMORY_DRAFT_STORAGE_KEY = 'lorvex.aiMemory.addDraft.v1';

export interface AddMemoryDraft {
  key: string;
  content: string;
}

export function readStoredDraft(): AddMemoryDraft | null {
  try {
    const raw = window.localStorage.getItem(ADD_MEMORY_DRAFT_STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<AddMemoryDraft>;
    if (typeof parsed.key !== 'string' || typeof parsed.content !== 'string') return null;
    if (!parsed.key.trim() && !parsed.content.trim()) return null;
    return { key: parsed.key, content: parsed.content };
  } catch {
    return null;
  }
}

export function writeStoredDraft(draft: AddMemoryDraft | null): void {
  try {
    if (draft === null) {
      window.localStorage.removeItem(ADD_MEMORY_DRAFT_STORAGE_KEY);
    } else {
      window.localStorage.setItem(ADD_MEMORY_DRAFT_STORAGE_KEY, JSON.stringify(draft));
    }
  } catch {
    // Storage may be disabled (private mode, quota); drop silently —
    // the worst case is we don't restore the draft on unlock.
  }
}
