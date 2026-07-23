# Foundation Models, 2025–2026

Primary sources:

- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels)
- [Meet the Foundation Models framework — WWDC25](https://developer.apple.com/videos/play/wwdc2025/286/)
- [Acceptable use requirements](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/)

Last verified: 2026-07-10

## Apple Direction

Foundation Models provides Swift access to the on-device model behind Apple
Intelligence. Input and output stay on device and the model can work offline.
Apple positions the device-scale model for summarization, extraction,
classification, structured generation, and tool calling, not for broad world
knowledge or advanced server-scale reasoning.

Availability is not implied by the OS version. The app must check model
availability because the device, region, Apple Intelligence setting, supported
language, and model download/readiness can all make it unavailable.

The model is also not a permanently frozen implementation. Apple documents
distinct model generations for OS 26.0–26.3, 26.4, and 27, and explicitly asks
developers to retest prompts when an OS update changes the model. June 2026
also introduced a general `LanguageModel` protocol and revised error types.

Use of the framework is subject to Apple's separate acceptable-use requirements
and program-license terms. High-impact decisions require human supervision;
model output must not silently become authoritative user data.

## Lorvex Fit

Good optional, on-device candidates include:

- summarizing a selected daily review or bounded task set;
- extracting structured candidate tasks/tags for user confirmation;
- classifying or clustering local planner text;
- generating a private briefing when the system model is available.

It should not be treated as a full replacement for Lorvex's external MCP
assistant or as a guaranteed capability on every supported Apple-silicon Mac
or iPhone. A deterministic non-AI path remains necessary.

The feature does not require a database or CloudKit schema change if generated
results remain ephemeral until the user accepts them. If results are persisted,
store explicit provenance, user confirmation, and enough model/prompt version
information to explain behavior across OS model updates; do not persist an
opaque model transcript as a new compatibility contract by accident.

## Adoption Gate

1. Availability-gate the entire feature and provide a complete fallback.
2. Use guided generation for typed proposals rather than parsing unconstrained
   text.
3. Require confirmation before any tool or proposal mutates planner data.
4. Keep sensitive source data local and minimize prompt context.
5. Build prompt/evaluation fixtures for every documented model generation.
6. Review the acceptable-use requirements and user-facing AI disclosure before
   shipping.

This is an OS-26 enhancement, not a reason to set the minimum deployment target
to OS 26.

The WWDC26 model-provider, multimodal, Dynamic Profile, PCC, Spotlight RAG, and
product-roadmap analysis is expanded in
[WWDC26_INTELLIGENCE_PRODUCT_OPPORTUNITIES.md](WWDC26_INTELLIGENCE_PRODUCT_OPPORTUNITIES.md).
