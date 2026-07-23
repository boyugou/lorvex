# App Privacy — App Store Connect answer sheet

The exact answers to enter in the App Store Connect **App Privacy** questionnaire
(the public "nutrition label") for Lorvex 1.0. This is the operational form of
the privacy posture; the narrative policy is `../../PRIVACY.md` and the release
process/rationale lives in `docs/finalization/RELEASE_ACCOUNT_CHECKLIST.md`
(repo root) §7. Keep all three consistent.

App Privacy answers are **app-level** and must describe the most inclusive
behavior across every platform (macOS, iOS, iPadOS, visionOS, watchOS).

## What the answers are grounded in

Verify these still hold for the exact submitted build before answering — the
answers below are only correct while they do:

- **No analytics/tracking/ads SDKs.** No Firebase, Sentry, Crashlytics,
  Amplitude, Mixpanel, AppsFlyer, Segment, or similar in `apps/apple/Sources` or
  `Package.swift`.
- **No first-party network egress.** No `URLSession`/`URLRequest`/`dataTask`
  network client and no `Network`-framework socket in the app sources; Lorvex
  operates no backend server of its own.
- **CloudKit private database only.** Optional iCloud sync writes to the user's
  own CloudKit **private** database via `CKRecord.encryptedValues`. Per Apple's
  own guidance, data a developer never receives on a server of its own — and data
  processed only on device — is **not** "collected" for the privacy label.
- **MetricKit stays local.** Crash/hang/CPU/disk diagnostics are captured via
  Apple's on-device MetricKit and written only to the local `error_logs` table
  (capped, pruned); Lorvex's own code never transmits them anywhere.
- **The MCP client is user-configured, not embedded.** The external AI assistant
  is chosen and wired up by the user over a local (stdio) connection; it is not
  an SDK integrated into the Lorvex binary, so it is not a Lorvex data collector.
- **Privacy manifests** (`Config/PrivacyInfo.xcprivacy` and the shared app-resource
  copy `Sources/LorvexApple/Resources/PrivacyInfo.xcprivacy`) declare
  `NSPrivacyTracking=false`, empty tracking domains, empty collected data types,
  and only the required-reason APIs UserDefaults (`CA92.1`) and file-timestamp
  (`C617.1`). The widget and MCP-helper bundles carry byte-identical build-time
  copies.

## Answers to enter

### Data Collection

- **"Do you or your third-party partners collect data from this app?"** → **No.**

Selecting **No** ends the data-type questionnaire: because Lorvex collects no
data, there are no data-type categories, purposes, linkage, or tracking sub-
questions to answer. The resulting nutrition label reads **"Data Not
Collected."**

### Tracking

- **Does the app track users** (link data collected here with third-party data,
  or share it with data brokers, for advertising/measurement)? → **No.**
- Tracking domains in the privacy manifest: **none** (`NSPrivacyTrackingDomains`
  is empty).

### Net result on the product page

> **Data Not Collected** — The developer does not collect any data from this app.

## Why on-device diagnostics and iCloud sync do not change the answer

- **MetricKit diagnostics** are processed and stored on device only; nothing is
  transmitted by Lorvex, so there is nothing "collected" to declare.
- **iCloud/CloudKit sync** moves the user's own content between the user's own
  devices through Apple's iCloud, which the **user** controls and Apple operates.
  Lorvex has no server that receives a copy. Apple's App Privacy guidance is
  explicit that developers do not declare data Apple itself handles through Apple
  services, and that private-database CloudKit content the developer cannot read
  is not developer "collection."
- **Apple OS / TestFlight channels** (system analytics sharing; TestFlight's
  automatic crash sharing) are Apple-operated and user/Apple-controlled, not
  Lorvex data collection. They are disclosed in `../../PRIVACY.md` for honesty
  but are not answers on Lorvex's nutrition label.

## What would flip these answers (re-check every release)

Any of the following would make **"Data Not Collected"** false and require
re-answering the questionnaire (and updating `../../PRIVACY.md` and the
manifests):

- Adding a crash/analytics/telemetry SDK or any first-party diagnostic **upload**.
- Adding a support flow that uploads logs, diagnostics, or user content off
  device.
- Embedding a hosted AI feature (a first-party call to a remote model), which
  would collect and transmit user content.
- Any first-party account, sign-in, or server that receives user data.

## Do not ship the answers unverified

Do not infer the questionnaire answers from `PrivacyInfo.xcprivacy` alone.
Generate Xcode's privacy report from the exact signed archive, diff it against
these answers and against `../../PRIVACY.md`, and save it with the release
evidence (see `docs/finalization/RELEASE_ACCOUNT_CHECKLIST.md` §7). Final
submission of these answers is an owner account action in App Store Connect.
