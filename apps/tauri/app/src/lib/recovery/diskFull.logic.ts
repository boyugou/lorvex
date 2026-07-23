// the disk-full classifier now reads the typed
// `CommandError` envelope (kind: 'disk_full') instead of a free-text
// `__disk_full__:` sentinel prefix. The wire format change is
// described in `app/src-tauri/src/error.rs`; the legacy sentinel was
// retired with the rest of the prefix family.
import { parseCommandError } from '../ipc/commandError';

export function extractDiskFullDetails(error: unknown): string | null {
  const envelope = parseCommandError(error);
  if (envelope === null || envelope.kind !== 'disk_full') return null;
  // Round-trip: the Rust `From<AppError> for String` impl puts the
  // raw OS / SQLite cause in `detail`; the human-facing `message` is
  // the same "Local storage is full." string for every variant. The
  // toast layer prefers `detail` because it is the diagnostic the
  // code rendered. Either is safe to surface to the user.
  return envelope.detail?.trim() ?? envelope.message;
}

export function isDiskFullError(error: unknown): boolean {
  return extractDiskFullDetails(error) !== null;
}
