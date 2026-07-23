#!/usr/bin/env node
/*
 * #3721 — bundle parallelization. The verification bundles
 * (`verify:repo-governance`, `verify:frontend-static-contracts`, etc.)
 * are composed of 6+ independent gates each — every gate runs in its
 * own process and reads its own files; there is no shared mutable
 * state. The previous sequential `for...of` loop walked them one at a
 * time, leaving 7 cores idle while one gate did its work. The bounded-
 * concurrency runner below collapses wall-clock time for the
 * governance + frontend bundles by ~3x without sacrificing readability.
 *
 * Argv handling:
 *   - The first positional (non-`--`) argument is the bundle name; an
 *     unknown bundle exits with code 2.
 *   - `--sequential` forces concurrency=1 (the legacy single-gate
 *     bisect path); `--concurrency=N` overrides the default of 4.
 *   - `--gate-timeout=Ns` sets a per-gate wallclock cap. SIGTERM is
 *     sent on timeout, escalating to SIGKILL after a 5-second grace
 *     period; the gate resolves with POSIX exit code 124. Default is
 *     no timeout.
 *   - Any other `--flag` is rejected loudly (exit 2) — pre-fix a typo
 *     like `--cocnurrency=8` was silently ignored, leaving the user
 *     thinking they had set a value they hadn't.
 *
 * Entry kinds (#3731): `npm` runs `npm run -w <ws> <script>`, `cargo`
 * shells out to `cargo` with the supplied args, and `shell` runs an
 * arbitrary command via `bash -c`. Every kind runs from the repo root
 * so absolute and relative paths in scripts behave the same as a
 * fresh checkout.
 *
 * Output discipline:
 *   - Each gate's stdout/stderr is forwarded line-by-line, prefixed
 *     with `[gate-name] …` so interleaving output from concurrent gates
 *     stays attributable.
 *   - Failures still short-circuit follow-on gates: once one fails, no
 *     new gates start, and the runner waits for in-flight gates to
 *     drain before returning a non-zero exit. The first non-zero exit
 *     code is propagated verbatim (rather than collapsed to 1) in
 *     BOTH the sequential and the parallel paths so a gate that
 *     intentionally exits with code 2 / 3 / 124 / N to signal a
 *     specific class of failure surfaces that signal to the caller.
 *   - Signal-killed children resolve with `128 + signal_number` (POSIX
 *     convention) so a SIGSEGV (139) is distinguishable from a gate's
 *     intentional exit 1.
 */
import { constants as osConstants } from 'node:os';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

import { bundleDefinitions, displayCommand } from './verification_manifest.mjs';

const DEFAULT_CONCURRENCY = 4;
const KNOWN_FLAGS = new Set(['--sequential']);
const KNOWN_FLAG_PREFIXES = ['--concurrency=', '--gate-timeout='];
// Grace period between SIGTERM and SIGKILL when a gate exceeds its
// timeout. Long enough for a well-behaved test runner to flush stdout
// and exit cleanly; short enough that a wedged child doesn't hold up
// the bundle. Matches the convention used by `timeout(1)`.
const GATE_TIMEOUT_GRACE_MS = 5_000;
// POSIX exit code for "command timed out" — matches `timeout(1)`'s
// default. Distinct from any value a gate is likely to use itself.
const TIMEOUT_EXIT_CODE = 124;
// POSIX convention for SIGINT (Ctrl-C) termination: 128 + 2.
// Used as the default propagation code when an abort interrupts the
// bundle without a more specific code on `abortSignal.reason` (#3763).
const SIGINT_EXIT_CODE = 130;

/*
 * #3763 — exit-code propagation for an aborted bundle. When the
 * top-level bundle is interrupted (SIGINT/SIGTERM, or a parent
 * cascading an abort), every still-pending entry should resolve with
 * a non-zero code so CI / shell pipelines see the failure. Prefer
 * `abortSignal.reason` if a caller stuffed a numeric code onto it
 * (e.g. forwarding 124 from a timeout); otherwise fall back to 130
 * (SIGINT convention).
 */
function abortExitCode(abortSignal) {
  const reason = abortSignal?.reason;
  if (typeof reason === 'number' && Number.isFinite(reason) && reason !== 0) {
    return Math.floor(reason);
  }
  if (reason && typeof reason === 'object' && typeof reason.code === 'number'
      && Number.isFinite(reason.code) && reason.code !== 0) {
    return Math.floor(reason.code);
  }
  return SIGINT_EXIT_CODE;
}

// Repo root: this file lives in `scripts/verify/`, so the project root
// is two levels up. Used as the cwd for `cargo` / `shell` entries so
// they run from the workspace root regardless of where `node` was
// invoked.
const __dirname = dirname(fileURLToPath(import.meta.url));
const rootDir = resolve(__dirname, '..', '..');

const argv = process.argv.slice(2);
const bundleName = argv.find((arg) => !arg.startsWith('--'));
const sequential = argv.includes('--sequential');
const concurrencyArg = argv.find((arg) => arg.startsWith('--concurrency='));
const gateTimeoutArg = argv.find((arg) => arg.startsWith('--gate-timeout='));

// argv validation. Pre-fix, an unknown flag (e.g. a typo
// `--cocnurrency=8`) was silently ignored: the bad flag landed in the
// non-flag position only if it didn't start with `--`, and the
// concurrency parser fell back to the default — leaving the user
// thinking they had set a value they hadn't. Mirror the unknown-flag
// shape from the rest of our verify scripts: warn loudly + exit 2.
const unknownFlags = argv.filter(
  (arg) =>
    arg.startsWith('--')
    && !KNOWN_FLAGS.has(arg)
    && !KNOWN_FLAG_PREFIXES.some((prefix) => arg.startsWith(prefix)),
);
if (unknownFlags.length > 0) {
  console.error(`[run_bundle] unknown flag(s): ${unknownFlags.join(', ')}`);
  console.error('Usage: node scripts/verify/run_bundle.mjs <bundle> [--sequential] [--concurrency=N] [--gate-timeout=Ns]');
  process.exit(2);
}

let concurrency;
if (sequential) {
  concurrency = 1;
} else if (concurrencyArg !== undefined) {
  const raw = concurrencyArg.slice('--concurrency='.length);
  const parsed = Number(raw);
  if (raw.length === 0 || !Number.isFinite(parsed) || parsed <= 0) {
    console.error(
      `[run_bundle] --concurrency= requires a positive numeric value (got ${JSON.stringify(raw)}), `
      + `falling back to default ${DEFAULT_CONCURRENCY}.`,
    );
    concurrency = DEFAULT_CONCURRENCY;
  } else {
    concurrency = Math.max(1, Math.floor(parsed));
  }
} else {
  concurrency = DEFAULT_CONCURRENCY;
}

// Per-gate timeout. Accept a value with optional `s` (seconds) suffix
// — bare numbers also parse as seconds. `0` or absent disables the
// timeout. Bad values fall back to disabled with a warning rather
// than aborting; a stuck gate is rare enough that a missed override
// is preferable to refusing to run the bundle entirely.
let gateTimeoutMs = 0;
if (gateTimeoutArg !== undefined) {
  const raw = gateTimeoutArg.slice('--gate-timeout='.length).replace(/s$/i, '');
  const parsed = Number(raw);
  if (raw.length === 0 || !Number.isFinite(parsed) || parsed < 0) {
    console.error(
      `[run_bundle] --gate-timeout= requires a non-negative numeric seconds value (got ${JSON.stringify(raw)}), `
      + `running without a per-gate timeout.`,
    );
    gateTimeoutMs = 0;
  } else {
    gateTimeoutMs = Math.floor(parsed * 1000);
  }
}

if (!bundleName || !bundleDefinitions[bundleName]) {
  const available = Object.keys(bundleDefinitions).sort().join(', ');
  console.error('Usage: node scripts/verify/run_bundle.mjs <bundle> [--sequential] [--concurrency=N] [--gate-timeout=Ns]');
  console.error(`Available bundles: ${available}`);
  process.exit(2);
}

/*
 * #3754 — global concurrency semaphore. The parallel path used to pass
 * `parallelism` recursively into nested bundles; each recursion got
 * its own worker pool, which meant a top-level bundle of `N=4` that
 * fanned out into another `N=4` parallel bundle could end up with up
 * to 4×4 = 16 gates running simultaneously. The semaphore below is
 * shared across every level so the total concurrent-gate count is
 * bounded by the user's `--concurrency=` flag regardless of nesting.
 *
 * #3755 — abort propagation. Bundles construct an AbortController at
 * the top level; nested bundles share the signal. On parent abort
 * (first failure inside this bundle, or the bundle being killed by an
 * outer cancel), in-flight children are signalled to terminate via
 * SIGTERM, then SIGKILL after the same grace window the per-gate
 * timeout uses. New gate launches are skipped — they observe the
 * aborted signal and resolve immediately as "skipped" (no exit code
 * change; the first failure that triggered the abort wins).
 */
function createSemaphore(limit) {
  // Classic counting semaphore. `acquire()` resolves once a slot is
  // free; `release()` hands the slot to the next waiter. Keeping it
  // local (no shared module state) means a future bundle invocation
  // from within Node can construct its own pool without cross-talk.
  let inUse = 0;
  const waiters = [];
  return {
    async acquire() {
      if (inUse < limit) {
        inUse += 1;
        return;
      }
      await new Promise((resolveAcquire) => {
        waiters.push(resolveAcquire);
      });
    },
    release() {
      const next = waiters.shift();
      if (next) {
        next();
      } else {
        inUse -= 1;
      }
    },
  };
}

const semaphore = createSemaphore(concurrency);
const rootController = new AbortController();
// Propagate Ctrl-C / SIGTERM at the controller level so an in-flight
// bundle can stop launching new gates and signal children to exit.
const signalAbort = (sig) => {
  if (rootController.signal.aborted) return;
  console.error(`[run_bundle] received ${sig} — aborting bundle`);
  rootController.abort();
};
process.on('SIGINT', () => signalAbort('SIGINT'));
process.on('SIGTERM', () => signalAbort('SIGTERM'));

const exitCode = await runBundle(bundleName, [], rootController.signal);
process.exit(exitCode);

async function runBundle(name, stack, abortSignal) {
  if (stack.includes(name)) {
    throw new Error(`verification bundle cycle detected: ${[...stack, name].join(' -> ')}`);
  }

  const entries = bundleDefinitions[name];
  if (concurrency <= 1 || entries.length <= 1) {
    return runEntriesSequentially(name, stack, entries, abortSignal);
  }
  return runEntriesInParallel(name, stack, entries, abortSignal);
}

async function runEntriesSequentially(name, stack, entries, abortSignal) {
  for (const entry of entries) {
    // #3763 — bubble a non-zero code for interrupted bundles instead
    // of returning 0 so callers (CI, parent scripts) observe the
    // abort as a failure rather than success.
    if (abortSignal.aborted) return abortExitCode(abortSignal);
    let code;
    if (entry.kind === 'bundle') {
      code = await runBundle(entry.name, [...stack, name], abortSignal);
    } else {
      // Even the sequential path acquires from the global semaphore
      // (#3754) so nested-bundle parallelism stays bounded: a top-
      // level parallel bundle that recurses into a sequential bundle
      // still consumes one of the global slots while its leaf gate
      // runs.
      await semaphore.acquire();
      try {
        code = await runCommand(entry, { tagOutput: false, abortSignal });
      } finally {
        semaphore.release();
      }
    }
    if (code !== 0) {
      // First-failure-wins exit-code propagation. Pre-fix the
      // sequential path collapsed every failure to `1`, hiding more-
      // specific signals (e.g. typecheck's `2`). Now we surface the
      // first non-zero code verbatim and stop the loop.
      return code;
    }
  }
  return 0;
}

async function runEntriesInParallel(name, stack, entries, abortSignal) {
  // Bounded concurrency — at most `concurrency` gates run at once
  // *globally*, enforced via the shared semaphore (#3754). We still
  // walk the entry list with a simple cursor + worker-pool pattern so
  // we don't pull in p-limit; the semaphore handles the actual
  // throttling.
  let cursor = 0;
  // Local abort controller: any failure inside this bundle aborts its
  // descendants but does NOT abort sibling bundles further up the
  // tree (those would have to be aborted by their own parent's
  // first-failure handler). The local controller is wired to the
  // inherited `abortSignal` so a parent abort propagates downward
  // (#3755).
  const localController = new AbortController();
  const onParentAbort = () => localController.abort();
  if (abortSignal.aborted) {
    localController.abort();
  } else {
    abortSignal.addEventListener('abort', onParentAbort, { once: true });
  }
  let firstNonZeroExitCode = 0;
  const inFlight = new Set();

  const startNext = () => {
    while (cursor < entries.length && !localController.signal.aborted) {
      const entry = entries[cursor];
      cursor += 1;
      const tag = displayCommand(entry);
      const promise = (async () => {
        if (localController.signal.aborted) return;
        let code;
        if (entry.kind === 'bundle') {
          code = await runBundle(entry.name, [...stack, name], localController.signal);
        } else {
          await semaphore.acquire();
          try {
            if (localController.signal.aborted) return;
            code = await runCommand(entry, { tagOutput: true, tag, abortSignal: localController.signal });
          } finally {
            semaphore.release();
          }
        }
        if (code !== 0) {
          if (firstNonZeroExitCode === 0) firstNonZeroExitCode = code;
          // Local abort signals every in-flight child to terminate
          // and stops new gates from launching. The parent's signal
          // is left untouched: the parent decides whether THIS
          // bundle's failure should also abort sibling bundles
          // further up the tree (today: yes, via its own
          // first-failure path).
          localController.abort();
        }
      })().finally(() => {
        inFlight.delete(promise);
      });
      inFlight.add(promise);
    }
  };

  try {
    startNext();
    while (inFlight.size > 0) {
      await Promise.race(inFlight);
      startNext();
    }
  } finally {
    // #3773 — always remove the parent-abort listener, even if the
    // loop body throws. Pre-fix a synchronous throw between the
    // listener addition and the explicit removeEventListener leaked
    // the listener onto `abortSignal`, holding a strong reference to
    // the (now-orphaned) local controller for the lifetime of the
    // parent signal.
    abortSignal.removeEventListener('abort', onParentAbort);
  }
  if (firstNonZeroExitCode === 0 && abortSignal.aborted) {
    // #3763 — parent-driven abort with no in-flight failure to
    // propagate. Surface a non-zero code so the bundle reports
    // interrupted-as-failure to CI.
    return abortExitCode(abortSignal);
  }
  return firstNonZeroExitCode;
}

// Translate a child-process termination (`code`, `signal`, plus our
// own `timedOut` flag) into the exit code the bundle should return.
//
//   - Clean exit                → numeric code (or 1 if missing).
//   - Timeout (we sent SIGTERM) → POSIX 124 so callers can recognise
//                                  the wallclock cap separately from
//                                  any code the gate happens to use.
//   - Other signal kill         → 128 + signal number (e.g. SIGSEGV →
//                                  139). Distinguishes a crash from a
//                                  gate's intentional `process.exit(1)`.
function resolveExitCode({ code, signal, timedOut }) {
  if (timedOut) return TIMEOUT_EXIT_CODE;
  if (signal) {
    const signalNum = osConstants.signals[signal];
    return signalNum != null ? 128 + signalNum : 1;
  }
  return code ?? 1;
}

/*
 * #3762 — signal the entire process group, not just the immediate
 * child. Gates frequently spawn deep trees: `npm run …` shells out to
 * `node`, which spawns `cargo`, which spawns `rustc` / `link.exe`. A
 * raw `child.kill()` only signals the npm wrapper; the grandchildren
 * keep working until they finish on their own. With `detached: true`
 * on spawn and `process.kill(-pgid, sig)`, the signal is delivered to
 * every process in the spawned group so a hung gate actually exits
 * within the timeout / grace window.
 *
 * On Windows process groups behave differently (negative-pid kill is
 * unsupported), so fall back to `child.kill(sig)` when the negative-
 * pid call throws ESRCH/EINVAL/ENOTSUP. The verify gates run on
 * macOS/Linux in CI; the fallback is a safety net for local dev.
 *
 * #3783 — additionally, `detached: true` itself is a POSIX-only
 * affordance. On Windows passing it to `spawn()` triggers a
 * `CREATE_NEW_PROCESS_GROUP` flag that confuses some signal-relay
 * helpers and, more importantly, doesn't grant negative-pid kill
 * semantics. We therefore platform-gate `detached` (POSIX only) and
 * rely on `child.kill()` as the best-effort termination path on
 * Windows. The killGroup() implementation already handles this — its
 * negative-pid call throws on Windows and routes into the
 * `child.kill(sig)` fallback below.
 */
function killGroup(child, signal) {
  if (!child.pid) return;
  try {
    process.kill(-child.pid, signal);
  } catch (err) {
    if (err && (err.code === 'ESRCH' || err.code === 'EINVAL' || err.code === 'ENOTSUP' || err.code === 'EPERM')) {
      try {
        child.kill(signal);
      } catch {
        /* child already exited */
      }
      return;
    }
    /* child already exited / unknown error — surface only via the close handler */
  }
}

// Arm a kill timer for a child. Returns a `clearTimers` callback that
// the caller invokes from the `close` handler so we don't fire on a
// child that exited cleanly. `gateTimeoutMs <= 0` means no timeout
// (default).
function armGateTimeout(child, label, onTimeout) {
  if (gateTimeoutMs <= 0) return () => {};
  let killTimer = null;
  const termTimer = setTimeout(() => {
    onTimeout();
    console.error(`[run_bundle] ${label} exceeded ${gateTimeoutMs}ms — sending SIGTERM`);
    killGroup(child, 'SIGTERM');
    // Escalate to SIGKILL if the child ignores SIGTERM during the
    // grace window. Most well-behaved CLIs (cargo, vitest) flush and
    // exit on SIGTERM in well under 5 seconds; this is a safety net,
    // not the primary kill path.
    killTimer = setTimeout(() => {
      console.error(`[run_bundle] ${label} did not exit after SIGTERM — sending SIGKILL`);
      killGroup(child, 'SIGKILL');
    }, GATE_TIMEOUT_GRACE_MS);
  }, gateTimeoutMs);
  return () => {
    clearTimeout(termTimer);
    if (killTimer) clearTimeout(killTimer);
  };
}

/*
 * #3755 — wire an AbortSignal into each spawned child so an aborted
 * bundle can SIGTERM in-flight gates instead of waiting for them to
 * exit on their own. The escalation mirrors the per-gate timeout
 * (`SIGTERM`, then `SIGKILL` after `GATE_TIMEOUT_GRACE_MS`) so a
 * wedged child doesn't hold up shutdown.
 */
function armAbortKill(child, label, abortSignal) {
  if (!abortSignal) return () => {};
  let killTimer = null;
  const onAbort = () => {
    console.error(`[run_bundle] ${label} aborted — sending SIGTERM`);
    killGroup(child, 'SIGTERM');
    killTimer = setTimeout(() => {
      console.error(`[run_bundle] ${label} did not exit after SIGTERM — sending SIGKILL`);
      killGroup(child, 'SIGKILL');
    }, GATE_TIMEOUT_GRACE_MS);
  };
  if (abortSignal.aborted) {
    onAbort();
  } else {
    abortSignal.addEventListener('abort', onAbort, { once: true });
  }
  return () => {
    abortSignal.removeEventListener('abort', onAbort);
    if (killTimer) clearTimeout(killTimer);
  };
}

function runCommand(entry, { tagOutput, tag, abortSignal }) {
  const command = commandForEntry(entry);
  const label = tag ?? displayCommand(entry);
  return new Promise((resolve) => {
    let timedOut = false;
    if (!tagOutput) {
      // Direct stdio inheritance keeps progress reporters (cargo,
      // vitest) live so the user sees streaming output.
      // #3762 — `detached: true` puts the child in its own process
      // group so we can later signal the entire group (npm → node →
      // cargo → rustc) via `process.kill(-pgid, sig)`. Despite the
      // option's name, the parent does NOT detach (no `child.unref()`)
      // — close events still fire and stdio inheritance still works.
      // #3783 — POSIX-only: on Windows `detached: true` does not grant
      // process-group kill semantics and can change the spawn flags in
      // surprising ways. Skip it there and let killGroup() fall back to
      // the best-effort `child.kill()` path.
      const child = spawn(command.bin, command.args, { stdio: 'inherit', cwd: command.cwd ?? process.cwd(), detached: process.platform !== 'win32' });
      const clearTimers = armGateTimeout(child, label, () => { timedOut = true; });
      const clearAbort = armAbortKill(child, label, abortSignal);
      child.on('error', (error) => {
        clearTimers();
        clearAbort();
        console.error(`[run_bundle] failed to start ${label}: ${error.message}`);
        resolve(1);
      });
      child.on('close', (code, signal) => {
        clearTimers();
        clearAbort();
        if (signal) {
          console.error(`[run_bundle] ${label} terminated by ${signal}`);
        }
        resolve(resolveExitCode({ code, signal, timedOut }));
      });
      return;
    }

    // Parallel mode: pipe + buffer + atomic flush so concurrent gates
    // produce attributable output. We flush partial output line-by-line
    // with a `[label] ` prefix so live progress remains visible; the
    // exit summary lands as the final tagged line.
    console.log(`[${label}] start`);
    const child = spawn(command.bin, command.args, {
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env, FORCE_COLOR: process.env.FORCE_COLOR ?? '1' },
      cwd: command.cwd ?? process.cwd(),
      // #3762 — see comment in the inherit branch above. Process-
      // group spawning lets us SIGTERM the full descendant tree on
      // timeout/abort instead of just the immediate child.
      // #3783 — POSIX-only; see Windows note in the inherit branch.
      detached: process.platform !== 'win32',
    });
    const clearTimers = armGateTimeout(child, label, () => { timedOut = true; });
    const clearAbort = armAbortKill(child, label, abortSignal);
    const prefixStream = (stream, sink) => {
      let buffer = '';
      stream.setEncoding('utf8');
      stream.on('data', (chunk) => {
        buffer += chunk;
        let nl;
        while ((nl = buffer.indexOf('\n')) !== -1) {
          const line = buffer.slice(0, nl);
          buffer = buffer.slice(nl + 1);
          sink.write(`[${label}] ${line}\n`);
        }
      });
      stream.on('end', () => {
        if (buffer.length > 0) sink.write(`[${label}] ${buffer}\n`);
      });
    };
    prefixStream(child.stdout, process.stdout);
    prefixStream(child.stderr, process.stderr);

    child.on('error', (error) => {
      clearTimers();
      clearAbort();
      console.error(`[${label}] failed to start: ${error.message}`);
      resolve(1);
    });
    child.on('close', (code, signal) => {
      clearTimers();
      clearAbort();
      if (signal) {
        console.error(`[${label}] terminated by ${signal}`);
      }
      const exit = resolveExitCode({ code, signal, timedOut });
      console.log(`[${label}] exit ${exit}`);
      resolve(exit);
    });
  });
}

function commandForEntry(entry) {
  switch (entry.kind) {
    case 'npm':
      return {
        bin: 'npm',
        args: ['run', ...(entry.workspace ? ['-w', entry.workspace] : []), entry.script, ...(entry.args ?? [])],
      };
    // #3731 — `cargo` entries (produced by `cargoGate` /
    // `cargoDoc` in verification_manifest.mjs) shell out directly so
    // bundle authors can mix npm scripts with native Rust gates
    // without funnelling everything through `npm run`.
    case 'cargo':
      return { bin: 'cargo', args: entry.args ?? [], cwd: rootDir };
    // #3731 — `shell` entries (produced by `shellGate`) carry a single
    // joined command string and run via `bash -lc`. The cwd is the
    // repo root so the gate's working directory matches what an
    // operator running the same command from a checkout would see.
    //
    // #3788 — POSIX-only by design. The hardcoded `bash` here means
    // any `shellGate(...)` consumer is a POSIX-only verification step.
    // Today's two consumers (`scripts/build_cli.sh`,
    // `scripts/build_dmg.sh`) are macOS/Linux build smokes that have
    // no Windows analog, so this is intentional. If you need a
    // cross-platform gate, route through `npmGate` (works under
    // `npm run` on Windows + POSIX) or `cargoGate` (works wherever
    // the cargo toolchain is installed). On Windows the spawn below
    // will fail with ENOENT for `bash` if WSL/Git-Bash isn't on PATH;
    // that failure is the contract — Windows runners must skip
    // shell-kind gates.
    case 'shell':
      return { bin: 'bash', args: ['-c', entry.command], cwd: rootDir };
    default:
      throw new Error(`run_bundle does not know how to dispatch entry kind ${JSON.stringify(entry.kind)}`);
  }
}
