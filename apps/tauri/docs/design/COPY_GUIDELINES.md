# Copy Guidelines
## Purpose
Keep product wording consistent across UI, docs, setup tutorials, and release materials.

This file is the source of truth for current wording decisions. Historical docs may keep older phrasing for context, but new user-facing text should follow this guide.

## Canonical Terms

### Core identity terms
- `AI assistant` (EN): generic operator term across Claude Desktop, Claude Code, Codex, and future MCP clients.
- `AI 助理` (ZH): Chinese default for the same concept. Do not use untranslated `assistant` in Chinese UI copy.
- `MCP client`: host app that launches/uses the Lorvex MCP server.

### Product surfaces
- `AI Activity`
- `AI Memory`
- `Quick Capture`
- `Sidebar modules`

### Chinese (UI-first)
- `AI 活动`
- `AI 记忆`
- `快速记录`
- `侧边栏模块`

## High-Frequency Term Map

| Concept | English | Chinese | Avoid |
|---|---|---|---|
| Operator role | `AI assistant` | `AI 助理` | `assistant` (raw in Chinese UI), product-specific identity in generic UX copy |
| Client surface | `Assistant MCP` | `AI 助理 MCP` | `Claude-only` wording when client-agnostic behavior is intended |
| Quick add action | `Quick Capture` | `快速记录` | mixed Chinese+English variants in the same flow |
| AI action log | `AI Activity` | `AI 活动` | inconsistent alternates such as `AI 变更日志` in primary UI copy |

## Required Usage Rules

- Keep business semantics assistant-agnostic:
  - prefer `human vs non-human` or `human vs AI assistant`
  - avoid hardcoded assistant identity assumptions in user-facing copy
- When referring to concrete client setup, name clients explicitly:
  - `Claude Desktop`
  - `Claude Code`
  - `Codex`
- Prefer plain language over internal architecture terms.
- Keep labels action-oriented and short.
- Do not mix English nouns into Chinese UI if a natural Chinese term exists.
- For multilingual UI strings, add the key in `en.json` first, then keep every strict-parity locale catalog complete before merging. `npm run verify:i18n` owns the blocking locale set.
- Additional non-strict locale JSON catalogs may lag during iteration; fallback to English is acceptable there while each strict-parity locale stays complete.
- Some i18n key names contain `claude` because they reference the Claude product (e.g. `settings.mcpClaudeDesktop`). This is correct — the key describes the content, not a legacy artifact.
- Network/update claims must be channel-scoped when behavior differs by distribution path (for example direct desktop builds vs future store builds in another app line).
- Use `AI Activity` in user-facing copy and `ai_changelog` only in internal/runtime/schema language.
- When MCP host identity matters, distinguish `embedded MCP` from `CLI-hosted MCP` instead of saying only `the MCP server`.

## Localization Policy

English (`en.json`) is the source locale. Strict-parity locales are first-class
shipping locales and must stay at full key parity, enforced on every PR by
`npm run verify:i18n`. The default strict set lives in
`app/src/locales/strict-parity.json`; CI or local release checks can temporarily
override it with `I18N_STRICT_PARITY_LOCALES=en,zh,fr,ja` as languages graduate
from soft to first-class coverage. Every new user-facing string lands in
`en.json` and each strict-parity catalog in the same commit.

Remaining locale catalogs under `app/src/locales/` are soft-parity catalogs with
a coverage floor. They may lag during iteration while being progressively
topped up. Missing keys fall back to `en.json` at runtime via the
`fallbackTranslations[key] ?? key` branch in `translate` (see
`app/src/locales/runtime.ts`), so readers see English for any missing key rather
than the raw key string. The default soft-parity floor is calibrated to the
current weakest supported locale cohort; tighten it with
`I18N_SOFT_PARITY_MAX_MISSING_RATIO=0.30 npm run verify:i18n` during translation
refresh work.

Per-locale completion percentages are emitted into `docs/reference/REPO_FACTS.md` ("Locale coverage" section) by `scripts/generate/repo_facts.mjs`; regenerate with `npm run docs:repo-facts`. Use that table to prioritize which non-strict locale to top up next.

## PR Copy Checklist

- If user-facing text changed, verify wording in both `en.json` and `zh.json`.
- Ensure Chinese text uses `AI 助理` instead of raw `assistant`.
- If introducing a new concept term, update this glossary in the same PR.
- If terminology changes affect docs/pitch/setup guides, update those docs in the same PR.
- If old phrasing is intentionally retained, document why in PR notes.
- If copy touches network/security/update behavior, verify wording against each active distribution channel.

## Release Copy Gate

Before a release cut, run a quick pass on:

1. Settings setup instructions (`Assistant MCP`) in EN/ZH.
2. Empty-state hints that mention the assistant role.
3. Any new high-traffic labels in dashboard and settings.
4. Distribution metadata and README wording if core terminology changed this cycle.
