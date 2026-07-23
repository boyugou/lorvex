/**
 * Build-time version helpers shared by the About panel and the error
 * report clipboard payload.
 *
 * The Vite build injects `import.meta.env.VITE_BUILD_SHA` from the
 * release pipeline. In dev / local builds the variable is unset, and
 * historically two sentinel shapes leaked into the value: an empty
 * string (no var set) and the literal `'unknown'` (older CI default).
 * Either form must render as the same "unknown build" affordance so a
 * user copying versions from the About panel and a user pasting an
 * error report ship the same binary identity into a GitHub issue.
 */

/**
 * Normalise the raw `VITE_BUILD_SHA` value into a short, paste-friendly
 * identifier or the canonical `'unknown'` sentinel.
 *
 * Returns the leading 7 hex characters of a real SHA, or `'unknown'`
 * for any non-SHA input (empty string, literal `'unknown'`, etc.).
 * Both call sites use this single helper so the rendered identity is
 * byte-identical across surfaces.
 */
function formatBuildSha(sha: string | undefined): string {
  if (!sha || sha === 'unknown') return 'unknown';
  return sha.slice(0, 7);
}

/**
 * Raw `import.meta.env.VITE_BUILD_SHA` read once at module load so
 * both consumers share the same captured value.
 */
export const BUILD_SHA_RAW: string =
  (import.meta.env.VITE_BUILD_SHA as string | undefined) ?? '';

/**
 * Canonical short build SHA for display. `'unknown'` when the build
 * pipeline did not stamp a SHA.
 */
export const BUILD_SHA_SHORT: string = formatBuildSha(BUILD_SHA_RAW);
