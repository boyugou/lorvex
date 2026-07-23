// ESLint v9 flat config for the Lorvex desktop app frontend.
//
// Issue #3381 — adds static analysis for the highest-leverage React/TS
// pitfalls in this codebase: missing hook dependencies, floating
// promises, and misused promise event handlers.
//
// We intentionally do NOT use `eslint-plugin-tailwindcss`. Its v3 line
// scans `tailwind.config.{js,ts}` (which does not exist under Tailwind
// 4's CSS-based `@theme` config) and falls back to slow heuristics that
// take >2 minutes on this 800+ TSX-file tree. The v4 line is still
// alpha. Tailwind safety is enforced instead by
// `scripts/lint/tailwind_class_audit.mjs`, which catches the specific
// footguns the project actually trips over (`border-border`, dynamic
// `bg-${color}` strings, etc.).

import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import reactPlugin from 'eslint-plugin-react';
import reactHooks from 'eslint-plugin-react-hooks';
import jsxA11y from 'eslint-plugin-jsx-a11y';
import globals from 'globals';

export default tseslint.config(
  {
    ignores: [
      'node_modules/**',
      'dist/**',
      'build/**',
      'src-tauri/**',
      'apple/**',
      'e2e/**',
      'playwright-report/**',
      'test-results/**',
      'coverage/**',
      '**/*.generated.ts',
      'src/locales/*.ts', // codegen output from `npm run i18n:codegen`
      // Plain JS configs do not need ESLint coverage.
      'vite.config.ts',
      'vitest.config.ts',
      'vitest.setup.ts',
      'playwright.config.ts',
      'eslint.config.js',
    ],
  },

  js.configs.recommended,
  ...tseslint.configs.recommended,

  // React + hooks + a11y for TS/TSX (type-aware).
  {
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: {
        ecmaVersion: 2024,
        sourceType: 'module',
        ecmaFeatures: { jsx: true },
        // Type-aware linting for `no-floating-promises` and
        // `no-misused-promises`. `projectService` is the modern
        // replacement for the older `project: ['./tsconfig.json']`
        // approach; it lazily picks the nearest tsconfig.
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
      globals: {
        ...globals.browser,
        ...globals.es2024,
      },
    },
    plugins: {
      react: reactPlugin,
      'react-hooks': reactHooks,
      'jsx-a11y': jsxA11y,
    },
    settings: {
      react: { version: 'detect' },
    },
    rules: {
      // React 19 + the new JSX transform.
      'react/react-in-jsx-scope': 'off',
      'react/prop-types': 'off',
      'react/jsx-key': 'error',

      // <button> elements default to `type="submit"` when nested in a
      // form, which silently submits the form on click — a footgun in
      // forms with multiple action buttons. Require explicit `type=`
      // on every <button>. Issue #3416.
      'react/button-has-type': 'error',

      // Hooks — `rules-of-hooks` is a hard correctness invariant
      // (calling a hook conditionally crashes React);
      // `exhaustive-deps` was promoted from warn to error in #3390
      // after the initial-sweep backlog (~60 sites) was burned down.
      // Real bugs and stable-ref refinements were folded back into the
      // affected hooks; the remaining intentional non-exhaustive cases
      // carry a targeted `eslint-disable-next-line` with a comment
      // explaining the invariant (e.g. depending on a stable `.open`
      // method instead of the bag literal).
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'error',

      // Promise hygiene. Type-aware, requires `projectService`.
      // `no-floating-promises` stays at error: an unhandled async
      // error from a discarded promise is always a bug.
      // `no-misused-promises` was promoted from warn to error in
      // #3390. The previous backlog of 9 sites — async DOM listeners,
      // async `() => void` ref slots, async `refetch` properties —
      // was rewritten to wrap the async work in a `void`-returning
      // closure, making the floating-promise discard explicit.
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': [
        'error',
        {
          // Allow `onClick={async () => ...}` event handlers (very
          // common, not a bug pattern); still flag misused promises
          // in checked-conditional contexts.
          checksVoidReturn: { attributes: false },
        },
      ],

      // TS already errors on unused locals/params via tsconfig — keep
      // ESLint at warn so it surfaces in IDEs but never blocks.
      '@typescript-eslint/no-unused-vars': [
        'warn',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_', caughtErrorsIgnorePattern: '^_' },
      ],

      // a11y — `click-events-have-key-events` and
      // `no-static-element-interactions` were promoted from `warn` to
      // `error` globally in #3433 after the codebase-wide sweep. The
      // remaining intentional exceptions (HTML5 drag-and-drop wrappers,
      // Tauri window-drag regions, hover-popover hover regions, and
      // listbox options that delegate keyboard activation to a parent
      // input via aria-activedescendant) carry a targeted
      // `eslint-disable-next-line` with a comment explaining the
      // contract. With the rules at error globally, the per-directory
      // override that previously hardened only `src/components/ui/**`
      // is redundant and was removed.
      'jsx-a11y/anchor-is-valid': 'warn',
      'jsx-a11y/click-events-have-key-events': 'error',
      'jsx-a11y/no-static-element-interactions': 'error',
      'jsx-a11y/no-noninteractive-tabindex': 'warn',

      // Avoid noise from `any` in legacy code.
      '@typescript-eslint/no-explicit-any': 'off',
    },
  },

  // Component code must reach Tauri's event bus and window API through
  // the `@/lib/platform/{events,window}.ts` wrappers, not the raw
  // `@tauri-apps/api/event` / `@tauri-apps/api/window` modules. Keeping
  // the platform coupling scoped to those two files makes the surface
  // we'd need to swap for an alternative host (web, mobile-only,
  // sandbox harness) explicit and auditable.
  //
  // The wrappers themselves are the one allowed consumer of the raw
  // modules; everything else under `src/components/**` (and any
  // sibling tree that should sit on the same boundary) goes through
  // `@/lib/platform/`. Issue #4411.
  {
    files: ['src/components/**/*.{ts,tsx}'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          paths: [
            {
              name: '@tauri-apps/api/event',
              message:
                "Import from '@/lib/platform/events' instead — component code goes through the platform wrapper (issue #4411).",
            },
            {
              name: '@tauri-apps/api/window',
              message:
                "Import from '@/lib/platform/window' instead — component code goes through the platform wrapper (issue #4411).",
            },
          ],
        },
      ],
    },
  },

);
