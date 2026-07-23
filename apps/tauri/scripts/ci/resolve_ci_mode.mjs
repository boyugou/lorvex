#!/usr/bin/env node
/**
 * CI mode resolver — determines whether to run fast or full CI.
 *
 * Usage:
 *   node scripts/ci/resolve_ci_mode.mjs \
 *     --event push|pull_request|workflow_dispatch \
 *     --dispatch-full true|false \
 *     --pr-labels-env PR_LABELS_JSON \
 *     --changed-files-env PR_CHANGED_FILES
 *
 * Output (stdout, one key=value per line for GITHUB_OUTPUT):
 *   run_full=true|false
 *   mode=<descriptive mode string>
 *   reason=<mode reason>
 *
 * Rules:
 *   push                           -> full (main post-merge gate)
 *   pull_request without ci:full   -> fast unless risky files changed
 *   pull_request with ci:full      -> full
 *   pull_request touching risky sync/MCP paths -> full
 *   workflow_dispatch full=true     -> full
 *   workflow_dispatch full=false    -> fast
 */

const args = process.argv.slice(2);

function getArg(name) {
  const idx = args.indexOf(`--${name}`);
  return idx !== -1 && idx + 1 < args.length ? args[idx + 1] : undefined;
}

function requirePrLabelParse(event, reason) {
  if (event === 'pull_request') {
    throw new Error(
      `Failed to parse pull_request label JSON; refusing to choose fast CI by default: ${reason}`,
    );
  }
  return [];
}

function requirePrChangedFilesParse(event, reason) {
  if (event === 'pull_request') {
    throw new Error(
      `Failed to parse pull_request changed files; refusing to choose fast CI by default: ${reason}`,
    );
  }
  return [];
}

export const RISKY_FULL_CI_PATH_PREFIXES = [
  'app/src-tauri/src/commands/sync/',
  'app/src-tauri/src/mcp_runtime.rs',
  'lorvex-sync/',
  'mcp-server/',
  'scripts/mcp/',
  'scripts/tests/mcp/',
];

export function parsePrLabels(raw, { event = 'push' } = {}) {
  if (!raw) return [];

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    return requirePrLabelParse(event, error.message);
  }

  if (!Array.isArray(parsed)) {
    return requirePrLabelParse(event, `expected an array, got ${typeof parsed}`);
  }

  if (parsed.some((label) => typeof label !== 'string')) {
    return requirePrLabelParse(event, 'expected every label name to be a string');
  }

  return parsed;
}

export function parseChangedFiles(raw, { event = 'push' } = {}) {
  if (!raw) return [];

  const trimmed = raw.trim();
  if (!trimmed) return [];

  if (trimmed.startsWith('[')) {
    let parsed;
    try {
      parsed = JSON.parse(trimmed);
    } catch (error) {
      return requirePrChangedFilesParse(event, error.message);
    }

    if (!Array.isArray(parsed)) {
      return requirePrChangedFilesParse(event, `expected an array, got ${typeof parsed}`);
    }

    if (parsed.some((file) => typeof file !== 'string')) {
      return requirePrChangedFilesParse(event, 'expected every changed file to be a string');
    }

    return parsed;
  }

  return trimmed
    .split(/\r?\n/)
    .map((file) => file.trim())
    .filter(Boolean);
}

export function readPrLabels({ event, labelsJson, labelsEnvName, env = process.env }) {
  const raw = labelsJson ?? (labelsEnvName ? env[labelsEnvName] : undefined);
  return parsePrLabels(raw, { event });
}

export function readPrChangedFiles({
  event,
  changedFiles,
  changedFilesEnvName,
  env = process.env,
}) {
  const raw = changedFiles ?? (changedFilesEnvName ? env[changedFilesEnvName] : undefined);
  return parseChangedFiles(raw, { event });
}

export function riskyFullCiPath(changedFiles = []) {
  return changedFiles.find((file) =>
    RISKY_FULL_CI_PATH_PREFIXES.some((prefix) => {
      if (prefix.endsWith('/')) {
        return file === prefix.slice(0, -1) || file.startsWith(prefix);
      }
      return file === prefix;
    }),
  );
}

export function resolveCiMode({ event, dispatchFull, prLabels, changedFiles }) {
  if (event === 'workflow_dispatch') {
    if (dispatchFull === 'true' || dispatchFull === true) {
      return { run_full: true, mode: 'full-manual-dispatch', reason: 'manual-dispatch-full-checks' };
    }
    return { run_full: false, mode: 'fast-manual-dispatch', reason: 'manual-dispatch-fast-checks' };
  }

  if (event === 'pull_request') {
    const labels = Array.isArray(prLabels) ? prLabels : [];
    if (labels.includes('ci:full')) {
      return { run_full: true, mode: 'full-pr-label', reason: 'label:ci:full' };
    }

    const riskyPath = riskyFullCiPath(Array.isArray(changedFiles) ? changedFiles : []);
    if (riskyPath) {
      return { run_full: true, mode: 'full-pr-risky-path', reason: `risky-path:${riskyPath}` };
    }

    return { run_full: false, mode: 'fast-pr-default', reason: 'pull-request-default-fast' };
  }

  if (event === 'push') {
    return { run_full: true, mode: 'full-main-push', reason: 'main-push' };
  }

  // Unknown events stay cheap by default; add an explicit branch above
  // before depending on full-mode behavior for a new trigger.
  return { run_full: false, mode: 'fast-unknown-event', reason: 'unknown-event-default-fast' };
}

// CLI entrypoint (skip when imported as module for testing)
const isMainModule = process.argv[1]?.endsWith('resolve_ci_mode.mjs');
if (isMainModule) {
  const event = getArg('event') || 'push';
  const dispatchFull = getArg('dispatch-full') || 'false';
  const prLabels = readPrLabels({
    event,
    labelsJson: getArg('pr-labels'),
    labelsEnvName: getArg('pr-labels-env'),
  });
  const changedFiles = readPrChangedFiles({
    event,
    changedFiles: getArg('changed-files'),
    changedFilesEnvName: getArg('changed-files-env'),
  });

  const result = resolveCiMode({ event, dispatchFull, prLabels, changedFiles });
  console.log(`run_full=${result.run_full}`);
  console.log(`mode=${result.mode}`);
  console.log(`reason=${result.reason}`);
}
