# Security Messaging Guide

This document defines the canonical security/trust messaging for Lorvex across docs, app copy, and distribution materials.

## Core Claims

1. User-owned by default
- User data is stored in local SQLite on the user's machine.
- Data leaves the device only when the user explicitly enables a sync/export path.

2. Source-backed trust claims
- The MCP server, schema/migrations, and major data-path logic are in the development repository.
- Until a public repository or public source package exists, public-facing copy must not describe the core as available for public source review.
- If a public repository or public source package is created later, public-facing docs must distinguish those public URLs from the private development repository.
- Security claims must be verifiable against source or documented runtime behavior, not marketing-only statements.

3. Explicit permission boundary
- The app itself has no built-in LLM.
- AI assistants operate through MCP and are session-invoked by the user.
- No hidden background autonomous agent should be implied in copy.

4. No telemetry by default
- No analytics SDKs, ad SDKs, or behavior tracking pipeline.
- If this changes in the future, docs and policy must be updated before release.

## Terminology

Use these canonical terms:

- `AI assistant` / `AI 助理`: generic term for Claude Desktop, Claude Code, Codex, and future MCP clients.
- `MCP client`: the external assistant app/process that invokes tools.
- `Local database`: SQLite file on device.
- `Optional sync`: user-enabled sync transport such as the filesystem bridge or a future cloud provider.

Avoid these anti-patterns:

- "Lorvex sends data to AI servers" (false for current architecture)
- "AI is always running in the background" (false for current operating mode)
- "Only Claude is supported" (false; architecture is multi-client)

## Reusable Paragraph Templates

### English (short)

Lorvex keeps your data on your device by default. Lorvex contains no built-in LLM. AI assistants connect through MCP when you invoke them on capable desktop runtimes, and all AI writes are auditable.

### Chinese (short)

Lorvex 默认本地优先：你的数据保存在设备本地 SQLite 数据库中。Lorvex 本体不内置大模型。AI 助理通过 MCP 在你主动调用时连接，所有 AI 写入都可审计。

### English (extended)

Lorvex is designed around local ownership and verifiable behavior. Your tasks, plans, and preferences are stored locally by default. The app does not ship with an embedded AI model; instead, external MCP-capable assistants operate it when you explicitly invoke them. This keeps authority and visibility with the user while preserving an auditable action trail.

### Chinese (extended)

Lorvex 以本地所有权和可验证行为为核心。任务、计划和偏好默认存储在本地。应用本体不内置 AI 模型，而是由支持 MCP 的外部 AI 助理在你明确调用时进行操作。这样既保留 AI 能力，也确保控制权和可见性在用户手中，并保留可审计的操作轨迹。

## Copy Review Checklist

- Does the text make user-owned local storage clear without overclaiming?
- Does it avoid implying built-in or always-on AI?
- Does it use assistant-agnostic wording unless naming a specific client example?
- Does it avoid claiming capabilities that are not implemented?
- Is the wording consistent with current distribution docs and actual architecture docs?
