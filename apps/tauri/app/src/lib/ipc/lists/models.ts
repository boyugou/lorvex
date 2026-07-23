/**
 * IPC models for list-domain results.
 *
 * this lived under `ipc/tasks/models.ts` — a list is not a
 * task, so the type was rehomed here for consistency with the other
 * per-domain IPC layouts (calendar, habits, …).
 */

export interface DeleteListResult {
  deleted_list_id: string;
  /** Opaque snapshot-undo token. Pass to `undoDeleteEntity` to
   *  restore the list within the TTL window (~5s). */
  undo_token: string;
}
