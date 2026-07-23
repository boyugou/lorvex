// Trusted Types policy registration.
//
// Lorvex renders user- and AI-authored Markdown via
// `react-markdown`, which builds React elements (no `innerHTML`) — so
// the existing default-deny is enforced at the React layer. Even so,
// the audit flagged the absence of a Trusted Types policy as a defense
// gap: if any future code path (a third-party tooltip library, a
// hand-rolled overlay, an analytics shim) reaches for `innerHTML` /
// `outerHTML` / `document.write`, Chromium's Trusted Types runtime is
// the last line of defense. Once `require-trusted-types-for 'script'`
// lands in CSP, every sink call MUST flow through a
// registered policy or get rejected.
//
// We register a single `lorvex-default` policy that:
// 1. **Refuses** to materialize raw HTML strings — `createHTML` returns
//    the empty string. This guarantees that any unsanctioned
//    `innerHTML = userInput` produces nothing instead of a possible
//    XSS sink, even if CSP enforcement is later relaxed by mistake.
// 2. **Refuses** to materialize raw script URLs — `createScriptURL`
//    returns the empty string. Lorvex never loads dynamic remote
//    scripts (CSP `script-src 'self'`), so this is purely a guardrail
//    against future regressions.
// 3. **Refuses** inline scripts — `createScript` returns the empty
//    string. Matches CSP `script-src 'self'` (no `'unsafe-inline'`).
//
// By registering as the *default* policy, every sink in the document
// without an explicit policy assignment routes through these refuse-
// to-materialize stubs. We also register the same policy under the
// explicit name `lorvex-default` so callers that opt-in (e.g. a
// future trusted-markdown renderer) can request it by name.
//
// Trusted Types is Chromium-only (WebView2 on Windows; Tauri on
// Linux). macOS WKWebView ignores the API. The registration is a
// no-op there but stays harmless: the `try/catch` around the
// `createPolicy` call is defensive in case the API is ever toggled
// off via experimental flags.

import { reportClientError } from '../errors/errorLogging';

const LORVEX_TRUSTED_TYPES_POLICY_NAME = 'lorvex-default';

let installed = false;

interface TrustedTypePolicyOptions {
  createHTML?: (input: string) => string;
  createScript?: (input: string) => string;
  createScriptURL?: (input: string) => string;
}

interface TrustedTypePolicyFactoryLike {
  createPolicy: (name: string, options: TrustedTypePolicyOptions) => unknown;
  defaultPolicy?: unknown;
}

interface WindowWithTrustedTypes extends Window {
  trustedTypes?: TrustedTypePolicyFactoryLike;
}

/**
 * Install the default Trusted Types policy on first call. Idempotent —
 * subsequent calls short-circuit so HMR / re-mounted roots don't throw
 * `TrustedTypePolicyFactory: Policy with name "default" already exists`.
 *
 * Safe to call before React mounts: the policy is process-wide.
 */
export function installTrustedTypesPolicy(): void {
  if (installed) return;
  installed = true;

  const w = window as WindowWithTrustedTypes;
  const factory = w.trustedTypes;
  if (!factory) {
    // Browser doesn't support Trusted Types (e.g. WKWebView). The
    // default-deny via React + CSP `script-src 'self'` still applies;
    // there is just no extra runtime gate.
    return;
  }

  // If something else already claimed `default` (e.g. a vendored
  // library that pre-registered), don't clobber it — Chromium throws
  // on duplicate names. Persist the conflict so Settings ->
  // Diagnostics surfaces it in packaged builds.
  if (factory.defaultPolicy != null) {
    reportClientError(
      'security.trusted_types',
      'Trusted Types default policy already registered',
      undefined,
      undefined,
      'warn',
    );
    return;
  }

  const refuse = (_input: string): string => '';

  try {
    factory.createPolicy('default', {
      createHTML: refuse,
      createScript: refuse,
      createScriptURL: refuse,
    });
  } catch (error) {
    reportClientError(
      'security.trusted_types',
      'Failed to register Trusted Types default policy',
      error,
      undefined,
      'warn',
    );
    return;
  }

  try {
    factory.createPolicy(LORVEX_TRUSTED_TYPES_POLICY_NAME, {
      createHTML: refuse,
      createScript: refuse,
      createScriptURL: refuse,
    });
  } catch (error) {
    // Named policy is best-effort; the default policy above is the
    // primary defense. A duplicate-name error here just means a prior
    // install (HMR) already registered it.
    reportClientError(
      'security.trusted_types',
      'Failed to register named Trusted Types policy',
      error,
      undefined,
      'warn',
    );
  }
}
