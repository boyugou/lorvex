# WWDC26 Intelligence Product Opportunities for Lorvex

Last verified: 2026-07-10  
Code snapshot: `b9acca441c0a72325f2bcd9764a81e98294fc91e`

This note maps Apple's WWDC26 intelligence announcements to Lorvex's current
iPhone/iPad and Apple-silicon Mac architecture. It is a product/architecture
assessment, not an implementation request. The OS 27 SDKs and several APIs are
beta, and Siri AI is announced for a user beta later in 2026, initially in
English. None of these capabilities should become a 1.0 data-schema dependency.

## Primary Apple Sources

- [WWDC26 Apple Intelligence guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/)
- [Apple's WWDC26 Siri AI announcement and availability](https://www.apple.com/newsroom/2026/06/apple-unveils-next-generation-of-apple-intelligence-siri-ai-and-more/)
- [What's new in the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)
- [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels)
- [Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
- [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute/)
- [Build agentic app experiences with Foundation Models](https://developer.apple.com/videos/play/wwdc2026/242/)
- [LLM search using Core Spotlight](https://developer.apple.com/videos/play/wwdc2026/246/)
- [Meet the Evaluations framework](https://developer.apple.com/videos/play/wwdc2026/298/)
- [Build intelligent Siri experiences with App Schemas](https://developer.apple.com/videos/play/wwdc2026/240/)
- [Reminders App Schema domain](https://developer.apple.com/documentation/appintents/app-schema-domain-reminders)
- [Providing contextual cues to Apple Intelligence and Siri](https://developer.apple.com/documentation/appintents/providing-contextual-cues-to-apple-intelligence-and-siri)
- [Validate App Intents with AppIntentsTesting](https://developer.apple.com/videos/play/wwdc2026/295/)
- [Acceptable-use requirements for Foundation Models](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/)
- [iOS and iPadOS 27 beta release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)

## Executive Recommendation

WWDC26 is highly relevant to Lorvex, but it suggests an additive intelligence
layer rather than a rewrite of the app:

1. **App Schemas and AppIntentsTesting are the highest-return work.** Lorvex
   already has a broad App Intent and App Entity surface. Mapping its exact task,
   list, calendar, and search semantics into Apple's schemas can make Siri
   understand natural-language requests without creating another planner API.
2. **View annotations are the most compelling iPhone-native enhancement.** They
   can let a user say “complete this,” “move this to Work,” or “when is this
   due?” while looking at a task. This is more useful than adding a generic chat
   tab.
3. **Foundation Models should first power structured proposals.** Free-form or
   image capture can propose tasks, dates, tags, checklists, and focus plans;
   deterministic validation and user confirmation should perform the write.
4. **Spotlight-grounded local search is a strong second-stage feature.** It can
   answer questions about the user's own planner without uploading the corpus,
   but Lorvex must first make indexing incremental, protected, and available on
   mobile.
5. **Private Cloud Compute and third-party models are optional escalation
   paths, not the foundation.** They add longer context and reasoning but also
   quotas, network dependence, beta APIs, entitlement review, and more product
   states.

Keep iOS 18 and macOS 15 as the minimum generation. Use OS 26/27 capabilities
only when the API, device, language, region, model download, user setting, and
quota all permit them. The complete planner must remain usable without Apple
Intelligence.

## What Actually Changed in 2026

### Foundation Models

The original OS 26 framework exposes Apple's on-device language model through a
native Swift API. WWDC26 adds or substantially expands:

- a rebuilt OS 27 on-device model with image input;
- Vision-backed `OCRTool` and `BarcodeReaderTool`;
- `SpotlightSearchTool` for locally grounded retrieval-augmented generation;
- `DynamicProfile` for switching model, instructions, tools, context, and
  reasoning behavior during a session;
- a common `LanguageModel` protocol for Apple's on-device model, Private Cloud
  Compute, Core AI, MLX, and third-party providers;
- a Private Cloud Compute model with stronger reasoning and a 32K context window
  versus the on-device model's documented 4K context;
- token/usage reporting, improved errors, and Foundation Models Instruments;
- a new Evaluations framework for repeatable quality and safety evaluation.

PCC is OS 27+ and requires a managed entitlement. It requires network access and
has a per-user daily quota. Apple recommends starting with and evaluating the
on-device model, then using PCC only when the task genuinely needs its context
or reasoning. Eligible small developers can currently receive PCC access with
no cloud API charge, but that does not make capacity unlimited or a permanent
business-model guarantee.

### Siri AI and App Intents

The developer integration point for Siri AI is App Intents, not a separate Siri
LLM API. The important OS 27 additions are:

- App Schemas that identify entities and actions using system-known semantics;
- contribution of typed entities to the Spotlight semantic index;
- view annotations that tell Siri which entity or entities are currently on
  screen;
- transfer of explicitly requested content between apps;
- natural-language execution without a developer-maintained list of exact
  invocation phrases;
- `AppIntentsTesting`, which executes through the same infrastructure used by
  Siri, Shortcuts, and Spotlight and can inspect indexing and view annotations.

Siri AI remains a preview, not a universal September assumption. Apple says its
user beta begins later in 2026, initially for supported devices set to English.
It is not initially available on iPhone/iPad in the EU and is unavailable in
China while regulatory work continues. Build the integration now, but do not
make a shipping workflow depend on Siri AI availability.

## Platform Reality

| Capability | iPhone/iPad | Apple-silicon Mac | Required fallback |
| --- | --- | --- | --- |
| Existing App Intents/Shortcuts | Available on Lorvex's deployment floor | Available | in-app controls |
| OS 26 on-device Foundation Models | Only Apple-Intelligence-eligible hardware, setting, language, and region | M1 or later, subject to setting/language/region | deterministic non-AI workflow |
| OS 27 App Schemas/View Annotations/AppIntentsTesting | OS 27 beta/current supported hardware | macOS 27 beta/current supported hardware | existing custom intents and navigation |
| OS 27 image prompts/OCR/Spotlight tool/Dynamic Profiles | eligible OS 27 device | eligible macOS 27 Mac | text/manual capture and ordinary search |
| Private Cloud Compute | eligible OS 27 device, network, entitlement, quota | same | on-device model, then deterministic path |
| Core AI/custom local model | possible but model-size/energy constrained | stronger fit on Apple silicon | system model or no AI |
| MLX local model | not the primary iPhone path | power-user/developer Mac fit | Foundation Models system model |

Apple's OS 27 announcement lists iPhone 15 Pro/Pro Max and iPhone 16 or later as
eligible, while all M1-or-later Macs are eligible. Lorvex's Apple-silicon-only
Mac direction therefore aligns well with Apple Intelligence; the iPhone install
base will remain materially broader than the model-eligible subset.

## Current Lorvex Position

The repository already has unusually strong prerequisites:

- current platform declarations are macOS 15, iOS 18, watchOS 11, and visionOS
  2, so OS 27 can be an availability-gated enhancement;
- tasks, lists, habits, calendar events, and memory already have stable App
  Entity identities;
- the system-intent package exposes a broad set of reads and mutations;
- `LorvexIntentSecurity` centralizes locked-device authentication tiers and
  explicit destructive confirmation;
- Mac tasks, lists, habits, reviews, and calendar content already have a Core
  Spotlight indexing path;
- core operations are typed and deterministic, making them suitable model tools
  after authorization and confirmation;
- the app already distinguishes proposal-style focus scheduling from committing
  a plan.

Important missing pieces:

- no entity or intent currently adopts an OS 27 App Schema;
- no entity adopts `IndexedEntity`, and no view provides OS 27 entity
  annotations;
- no `AppIntentsTesting` integration suite exists;
- Foundation Models is not linked or used;
- the production Spotlight index is Mac-only;
- current broad refresh replaces large Spotlight domains unconditionally, which
  should be fixed before turning the index into an LLM knowledge source;
- the existing index/privacy policy must be narrowed before task notes, memory,
  or review text becomes model-readable.

## Ranked Product Opportunities

### 1. Reminders and Calendar App Schemas — highest priority

The OS 27 Reminders domain is an unusually direct fit:

| Lorvex type/action | Candidate schema | Decision boundary |
| --- | --- | --- |
| `LorvexTaskEntity` | `.reminders.reminder` | map only fields with the same meaning |
| `LorvexListEntity` | `.reminders.list` | strong fit |
| capture/create task | `.reminders.createReminder` | structured title/list/note/tags/due/recurrence |
| create list | `.reminders.createList` | strong fit |
| complete/reschedule/edit task | `.reminders.updateReminder` | strong after result/error semantics are verified |
| permanent delete | `.reminders.deleteReminders` | do not map until Lorvex's archive/delete contract exactly matches |
| Lorvex calendar entity/actions | Calendar domain | keep provider EventKit versus Lorvex event semantics explicit |
| task/calendar search | System and in-app search domain | expose bounded, authorized results only |

Do not force habits, memory, reviews, or focus sessions into the Reminders schema
merely to gain Siri visibility. A wrong schema is worse than a well-described
custom intent because Siri will infer system semantics Lorvex does not honor.

Expected iPhone value:

- “Create a reminder in Lorvex called renew passport next Friday.”
- “Complete the Lorvex reminder about the hotel.”
- “Move this reminder to Travel.”
- “Show my overdue Lorvex reminders.”

Expected Mac value is similar, especially for hands-free capture and cross-app
workflows while another document is active.

### 2. Onscreen task awareness — highest differentiated iPhone value

Annotate the selected task, visible task rows, current list, and calendar event
with their existing entity identifiers. Then Siri can resolve pronouns such as
“this” and “that” against what the user is looking at.

Start narrowly:

- selected task detail;
- current focus task;
- selected list;
- one opened calendar event.

Avoid attaching every cached entity to a root view. Apple instructs apps to
annotate content that the view actually represents. Only expose properties
needed for the requested action, and test that navigation transitions do not
leave a stale entity annotation onscreen.

### 3. Intelligent capture with typed, reviewable proposals

This is the best first in-app Foundation Models feature:

- paste or dictate unstructured text;
- optionally select a screenshot/photo on OS 27;
- use image input and/or OCR to extract candidate tasks;
- generate a typed result containing title, notes, due date, list, tags,
  checklist candidates, recurrence, estimated duration, and confidence/warnings;
- render an editable review sheet;
- validate every entity ID, date, recurrence, and field length deterministically;
- write ordinary Lorvex tasks only after explicit acceptance.

Useful mobile examples include a whiteboard, handwritten checklist, event flyer,
travel itinerary, or screenshot of a message. Mac can offer the same flow for
selected text, pasted documents, and dragged files.

Do not let the model directly call create/update tools in the first version.
Guided generation into a proposal makes hallucinations visible and keeps the
database mutation path deterministic.

### 4. Private planner search grounded in Core Spotlight

`SpotlightSearchTool` can turn Lorvex's index into local RAG for questions such
as:

- “Which travel tasks are blocked?”
- “What did I defer this week?”
- “Summarize tomorrow's tasks and calendar conflicts.”
- “Find the task where I mentioned the passport number.”

Adoption prerequisites:

1. build a protected mobile Spotlight index with the same stable identities;
2. make indexing incremental and domain-dirty rather than a full refresh fan-out;
3. implement the new index delegate hydration method for complete model-readable
   items;
4. define an allowlist of indexed/model-readable fields;
5. exclude secrets, diagnostics, audit logs, and memory by default;
6. provide attribution links back to the exact Lorvex entity;
7. evaluate retrieval and answer faithfulness separately.

The model should answer from retrieved Lorvex facts and say when the index has
insufficient evidence. It must not substitute world knowledge for missing task
data.

### 5. Daily brief, review assistance, and focus-plan proposals

Good bounded uses include:

- a morning brief from today's tasks, current focus, and calendar;
- a weekly review summary from already computed metrics and selected notes;
- grouping an inbox into candidate lists/tags;
- proposing a focus schedule around deterministic calendar constraints;
- identifying likely duplicate or stale tasks for user review.

These features should cite/link the source entities, preserve the deterministic
underlying metrics, and never silently mark tasks complete, delete data, or
replace a user-authored review.

### 6. Private Cloud Compute “Deep Plan” — later opt-in

PCC's 32K context and reasoning levels can help with a large backlog or longer
planning horizon. It is appropriate only after evaluations show the on-device
4K model is materially insufficient.

The UI must represent these states honestly:

- network unavailable;
- model unavailable for device/region/settings;
- quota approaching or exhausted;
- entitlement unavailable;
- fallback to on-device result with potentially different quality;
- user cancellation and partial streaming response.

Do not promise unlimited “free cloud AI.” The current program removes developer
API charges for eligible apps, but the user still has daily quotas and Apple can
evolve program terms.

### 7. Live Activity for an active focus block — useful, but not an AI feature

WWDC26 revisited Live Activities. Lorvex could show the current focus task,
remaining block time, and safe Complete/Defer/Stop controls on the Lock Screen,
Dynamic Island, and paired Watch. This is a better mobile enhancement than
placing a persistent generic AI assistant on the home screen.

It requires its own privacy/redaction and stale-state audit. A Live Activity is
not a general task list and should not reveal notes or sensitive titles while
locked unless the user opts in.

## Mac-Specific Opportunities

- A larger “Planning Studio” can combine local Spotlight RAG with the current
  multi-window UI while keeping sources visible beside the generated proposal.
- M1-or-later eligibility matches Lorvex's supported Mac architecture, so the
  on-device availability rate should be better than on iPhone.
- MLX or Core AI could eventually support a downloadable specialist model for
  advanced offline users, but model distribution, memory, energy, licensing,
  and evaluation make this a later feature.
- The existing MCP helper remains valuable: it lets a user's chosen external
  assistant operate Lorvex. Foundation Models is the reverse direction — Lorvex
  invokes a model. They should share typed core operations and authorization
  policy, not be conflated into one trust boundary.

## Architecture to Freeze Before Any AI Feature

### Capability resolution

Use one application service to resolve:

- compile-time API availability;
- OS version;
- eligible device;
- Apple Intelligence enabled/disabled;
- model ready/downloading;
- supported locale;
- network and PCC quota;
- allowed feature and privacy setting.

Views should consume a product capability such as “structured capture
available,” not infer it from `if #available` alone.

### Read tools, proposal tools, and commit tools

Separate three layers:

1. privacy-bounded reads returning typed facts;
2. model generation returning typed proposals;
3. deterministic commands that authenticate, validate, confirm, and commit.

The model is never an authorization principal. Task text, calendar text,
Spotlight results, imported files, and web/server-model responses are untrusted
input and may contain prompt injection. Tool access must be allowlisted by
feature and state, with no hidden path from a read-only assistant to mutation.

### Data and sync contract

- Accepted model proposals should write ordinary existing domain fields.
- Raw transcripts, hidden reasoning, prompts, embeddings, and provider response
  objects must not enter CloudKit or the canonical SQLite schema by default.
- If provenance is needed, keep a small local/versioned record containing the
  feature, model family/version, prompt/evaluation version, timestamp, and user
  acceptance — never the model's private reasoning.
- Do not introduce strict synced enum values that an iOS 18/macOS 15 build
  cannot parse.
- A model update is an evaluation event, not a schema migration.

### Evaluation

Create fixtures before UI polish:

- supported Lorvex locales and mixed-language input;
- every Apple on-device model generation (26.0–26.3, 26.4, 27);
- ambiguous dates, time zones, recurrence, and destructive requests;
- prompt injection in task notes/calendar/imported text;
- unavailable/disabled/not-ready/quota/network cases;
- false retrieval and unsupported-answer refusal;
- typed-output validation and confirmation cancellation.

Measure task extraction precision, field-level accuracy, invalid proposal rate,
retrieval recall, groundedness, tool-call policy violations, latency, tokens,
memory, and energy. A few hand-tested prompts are not a release gate.

## Recommended Sequence

1. Keep the iOS 18/macOS 15 floor and build an Xcode 27 experimental lane.
2. Add `AppIntentsTesting` around the existing entities, queries, authentication,
   confirmation, Spotlight identity, and deep-link results.
3. Prototype Reminders `createReminder`, `updateReminder`, `reminder`, and `list`
   schemas; add Calendar/search schemas only where semantics match exactly.
4. Add view annotations for one selected task and verify them through the system
   test framework.
5. Build an evaluation-only structured text-capture prototype using the
   on-device model; do not persist new schema.
6. Add OS 27 image/OCR input and an editable proposal sheet.
7. Fix and extend protected incremental Spotlight indexing to mobile, then
   evaluate local RAG.
8. Consider PCC only when measured quality justifies its additional states.
9. Consider Live Activity and Mac Planning Studio independently of the AI
   rollout.

## Explicit Non-Recommendations

- Do not raise the deployment target to iOS/macOS 27 for these features.
- Do not redesign the core database around a model, prompt, or provider.
- Do not ship a generic chat tab without a bounded product task.
- Do not give a model silent write/delete/export tools.
- Do not expose all task notes, memory, reviews, or diagnostics to Spotlight or
  Siri by default.
- Do not pretend a habit is a system reminder or a memory is a note merely to
  satisfy a schema macro.
- Do not rely on Siri AI for onboarding, capture, search, or editing; it is an
  optional system surface with hardware, language, region, and beta limits.
- Do not treat passing unit tests as AI quality evidence; use system integration
  tests plus repeatable evaluations and physical-device testing.

The best WWDC26 outcome for Lorvex is not “more AI everywhere.” It is a more
native planner: Siri understands real Lorvex entities, the current screen
provides safe context, local models turn messy input into reviewable structured
work, and every accepted result remains ordinary durable Lorvex data.
