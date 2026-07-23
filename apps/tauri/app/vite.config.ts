import path from 'node:path';
import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { visualizer } from 'rollup-plugin-visualizer';

/**
 * Resolve the app build SHA at build time. Tries `git rev-parse` first
 * (short SHA, suffixed with `-dirty` when the working tree has
 * uncommitted changes), then the `LORVEX_BUILD_SHA` env var supplied
 * by the release CI as a fallback for source-tarball builds where
 * `.git/` isn't present. Returns `'unknown'` if neither resolves;
 * callers (ErrorBoundary, About panel) treat that as a missing
 * identifier and degrade gracefully.
 */
function resolveBuildSha(): string {
  if (process.env.LORVEX_BUILD_SHA) return process.env.LORVEX_BUILD_SHA;
  try {
    const sha = execSync('git rev-parse --short HEAD', { stdio: ['ignore', 'pipe', 'ignore'] })
      .toString()
      .trim();
    let dirty = false;
    try {
      const status = execSync('git status --porcelain', { stdio: ['ignore', 'pipe', 'ignore'] })
        .toString()
        .trim();
      dirty = status.length > 0;
    } catch {
      // dirty check is best-effort
    }
    return dirty ? `${sha}-dirty` : sha;
  } catch {
    return 'unknown';
  }
}

function resolveAppVersion(): string {
  try {
    const pkg = JSON.parse(readFileSync(path.resolve(__dirname, 'package.json'), 'utf8')) as { version?: string };
    return pkg.version ?? 'unknown';
  } catch {
    return 'unknown';
  }
}

/**
 * Resolve the GitHub repo URL the About panel links to from the
 * Build SHA badge. Reads `LORVEX_REPO_URL` first (CI / release builds
 * can pin a canonical mirror) and falls back to the upstream
 * repository so local dev builds get a working link without any env
 * setup. The base URL is concatenated with `/commit/<sha>` at the
 * call site, so the value here must point at a GitHub project root
 * (https://github.com/<owner>/<repo>).
 */
function resolveRepoUrl(): string {
  return process.env.LORVEX_REPO_URL ?? 'https://github.com/boyugou/ai-native-todo';
}

const BUILD_SHA = resolveBuildSha();
const APP_VERSION = resolveAppVersion();
const REPO_URL = resolveRepoUrl();

// Audit #3054 (M10): the Tauri CSP under `app/src-tauri/tauri.conf.json`
// still includes `'unsafe-inline'` in `style-src`. Tailwind 4 with
// `@tailwindcss/vite` emits a single static `app.css` for utility
// classes — that part of the runtime no longer needs inline styles —
// but several runtime concerns still inject `<style>` elements or
// `style="..."` attributes:
//
//   * React 19 hydration occasionally inlines critical-CSS shims on
//     suspense boundaries before the route's split chunk lands.
//   * Tauri WebView injects platform fixups (vibrancy / native
//     scrollbars) via inline style on app start.
//   * Several third-party UI libraries (Milkdown / ProseMirror, the
//     Markdown vendor chunk) inject runtime style nodes for caret
//     positioning, virtualization measurement, etc. None of these
//     surfaces accept a CSP `nonce` today.
//
// Dropping `'unsafe-inline'` from `style-src` therefore breaks the app
// in WebKit/WebView2 in ways the CI smoke tests would catch, but only
// after the CSP regression test (which doesn't yet exist) is wired in.
// The right sequencing is: (1) add a nonce-injecting Vite plugin that
// also rewrites runtime injection sites; (2) add a CSP regression test;
// (3) drop `'unsafe-inline'`. None of those are 30-minute changes, so
// per the audit's own guidance this comment is the bookmark — not a
// silent shrug — until the follow-up lands.

// Opt-in bundle analyzer: set BUNDLE_REPORT=1 on a build to emit `app/stats.html`
// alongside the usual build output. Gated behind an env flag so normal builds
// (dev + CI) stay fast and don't produce extra artifacts. See issue #2728.
const bundleReport = process.env.BUNDLE_REPORT === '1';

// https://vitejs.dev/config/
export default defineConfig(async () => ({
  // Surface the resolved app version + build SHA to runtime code via
  // `import.meta.env` so ErrorBoundary's "Copy report" payload can
  // include both without an IPC round-trip. The `VITE_` prefix is the
  // canonical Vite convention for env values exposed to the client.
  define: {
    'import.meta.env.VITE_APP_VERSION': JSON.stringify(APP_VERSION),
    'import.meta.env.VITE_BUILD_SHA': JSON.stringify(BUILD_SHA),
    'import.meta.env.VITE_REPO_URL': JSON.stringify(REPO_URL),
  },
  plugins: [
    react(),
    tailwindcss(),
    ...(bundleReport
      ? [
          visualizer({
            filename: 'stats.html',
            gzipSize: true,
            brotliSize: true,
            open: false,
            emitFile: false,
          }),
        ]
      : []),
  ],
  // Ensure React is resolved from a single location even when npm workspace
  // hoisting places @tanstack/react-query in root node_modules/ while react
  // lives in app/node_modules/. Without this, Rolldown fails to resolve "react"
  // from the hoisted @tanstack package.
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
    dedupe: ['react', 'react-dom'],
  },
  // Vite options tailored for Tauri development and only applied in `tauri dev` or `tauri build`
  //
  // 1. prevent vite from obscuring rust errors
  clearScreen: false,
  // 2. tauri expects a fixed port, fail if that port is not available
  server: {
    port: 1420,
    strictPort: true,
    watch: {
      // 3. tell vite to ignore watching `src-tauri`
      ignored: ['**/src-tauri/**'],
    },
  },
  build: {
    // Warn when any emitted chunk exceeds 250 KB (uncompressed). This is a
    // signal, not a hard failure — paired with the gzip/brotli report below
    // and the opt-in visualizer to make bundle regressions obvious.
    chunkSizeWarningLimit: 250,
    reportCompressedSize: true,
    rolldownOptions: {
      output: {
        manualChunks(id: string) {
          // Locale files (except en.ts) are loaded via dynamic import() and
          // automatically split into per-locale chunks by Vite — no manual
          // chunk assignment needed.

          if (id.includes('/node_modules/')) {
            if (id.includes('/node_modules/react/') || id.includes('/node_modules/react-dom/')) {
              return 'react-vendor';
            }
            // split @tauri-apps/* per-plugin so a window
            // that never imports (say) plugin-dialog doesn't pay for
            // the dialog bindings. The core `@tauri-apps/api` surface
            // is shared across every window via lib/ipc.ts and stays
            // in a single chunk. Plugins are lazy-imported at the
            // call site (see settings controllers + notifications
            // runtime) and get their own chunk here so Rolldown
            // doesn't merge them back into the shared vendor bundle.
            if (id.includes('/node_modules/@tauri-apps/plugin-notification/')) {
              return 'tauri-plugin-notification-vendor';
            }
            if (id.includes('/node_modules/@tauri-apps/plugin-dialog/')) {
              return 'tauri-plugin-dialog-vendor';
            }
            if (id.includes('/node_modules/@tauri-apps/plugin-autostart/')) {
              return 'tauri-plugin-autostart-vendor';
            }
            if (id.includes('/node_modules/@tauri-apps/plugin-opener/')) {
              return 'tauri-plugin-opener-vendor';
            }
            if (id.includes('/node_modules/@tauri-apps/')) {
              return 'tauri-vendor';
            }
            if (id.includes('/node_modules/@tanstack/')) {
              return 'tanstack-vendor';
            }
            // Split heavy libraries so they load only when their consumer view renders.
            if (id.includes('/node_modules/@milkdown/') || id.includes('/node_modules/prosemirror') || id.includes('/node_modules/@prosemirror/')) {
              return 'milkdown-vendor';
            }
            if (id.includes('/node_modules/react-markdown/') || id.includes('/node_modules/remark-') || id.includes('/node_modules/rehype-') || id.includes('/node_modules/unified/') || id.includes('/node_modules/hast-') || id.includes('/node_modules/micromark')) {
              return 'markdown-vendor';
            }
            if (id.includes('/node_modules/chrono-node/')) {
              return 'chrono-vendor';
            }
            return 'vendor';
          }

          return undefined;
        },
      },
    },
  },
}));
