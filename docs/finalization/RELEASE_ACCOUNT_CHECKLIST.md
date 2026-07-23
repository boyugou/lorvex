# Release — Account-Only Actions Checklist

The consolidated runbook of release steps that genuinely require the Apple
Developer account or another human decision, and therefore cannot be done from
the repo alone. Everything code-fixable is tracked separately in
`FINDINGS_BACKLOG.md` (same directory); this file is the owner-facing
action list for the publish cut.

Like the rest of `docs/finalization/`, this is dev-process state and is deleted
as the last step of the public repo cut. Work through it before deleting it.

Cross-references (repo-side detail behind each item):

- Packaging / signing flows: `apps/apple/docs/DISTRIBUTION.md`
- Release / schema-freeze arming: `apps/apple/docs/release.md`
- Listing copy to paste: `apps/apple/docs/APP_STORE_METADATA.md`
- Privacy posture: `../../PRIVACY.md`, both `PrivacyInfo.xcprivacy` manifests
- Apple contract references (last verified 2026-07-10):
  `apps/apple/docs/reference/apple-official/APP_STORE_SUPPORT_URL.md`,
  `APP_PRIVACY_DETAILS.md`, `APP_STORE_UPCOMING_REQUIREMENTS.md`

---

## 1. Pre-cut repo actions (owner runs locally, then commits)

- [ ] Create the public repo `github.com/boyugou/lorvex` for the publish cut.
- [ ] Confirm `.gitignore` still excludes `secrets/`, `docs/APPLE_DEVELOPER.md`,
  `apps/apple/docs/APPLE_DEVELOPER.md`, `*.p12`, `*.cer`, `*.certSigningRequest`,
  `*.p8`, `*.provisionprofile`, `*.mobileprovision`, `.env`, and `.env.build`
  (with `.env.build.example` still tracked). Verified in this repo; re-check
  after any merge.
- [ ] Delete `docs/finalization/` (this whole tree) before the cut.
- [ ] Arm the schema-freeze tripwire once the first public build is final:
  `./script/verify_schema_freeze.py --arm` (flips `schema/migration_policy.json`
  `launched` to `true` and freezes the shipped baseline checksums). Release
  packaging must not set `LORVEX_ALLOW_UNFROZEN=1`. See `apps/apple/docs/release.md`.

## 2. Apple Developer portal — identifiers & capabilities

Register every App ID and enable its capabilities (from
`DISTRIBUTION.md` §8–§9). Bundle IDs:

- [ ] `com.lorvex.apple` — macOS app
- [ ] `com.lorvex.apple.mobile` — iOS/iPadOS app
- [ ] `com.lorvex.apple.vision` — visionOS app
- [ ] `com.lorvex.apple.mobile.watchkitapp` — watchOS app (prefixed by the iOS host per Apple TN3157)
- [ ] `com.lorvex.apple.mobile.watchkitapp.widgets` — watch complication
- [ ] `com.lorvex.apple.mobile.widget.focus` — WidgetKit extension (shared id)
- [ ] `com.lorvex.apple.mcp-host` — macOS MCP helper app
- [ ] App Group `group.com.lorvex.apple` — enabled on every target that needs it
  (app, MCP helper, widget must all authorize it).
- [ ] iCloud/CloudKit container `iCloud.com.lorvex.apple` — enabled on the app
  targets that ship the CloudKit entitlement variant.
- [ ] Do **not** add the CarPlay capability (`com.apple.developer.carplay-communication`)
  until Apple approves it for the iOS App ID. The template stays out of the
  shipped entitlements until then.

## 3. Certificates & provisioning profiles

- [ ] Distribution certificates: Apple Distribution (app), 3rd Party Mac
  Developer Installer (MAS `.pkg`), and, for the notarized non-App-Store macOS
  path, Developer ID Application.
- [ ] Distribution provisioning profiles for each bundle ID above. For MAS
  `archive_mas.sh --package`, the **app, MCP-helper, and widget profiles are all
  mandatory** (packaging hard-fails if any of the three is missing); place them
  at the `secrets/profiles/` default paths or point the
  `MAS_*_PROVISIONING_PROFILE` env vars at them.
- [ ] The MCP-helper profile must additionally authorize `group.com.lorvex.apple`.
- [ ] notarytool keychain profile for the Developer ID path
  (`xcrun notarytool store-credentials`).

## 4. CloudKit production schema promotion

- [ ] In CloudKit Console, promote the development schema for
  `iCloud.com.lorvex.apple` to Production (after the schema freeze is armed).
- [ ] Confirm the promoted production schema carries the encrypted record fields
  the app writes, and that the app's production entitlement
  (`com.apple.developer.icloud-container-environment=['Production']`) selects the
  intended container before exposing Live iCloud Sync in a submitted build.
- [ ] On-device production proof: DB subscription
  installs, a silent peer push arrives, token fetch converges, and deletion stays
  paused until explicit re-enable.

## 5. Toolchain / upload gates (from APP_STORE_UPCOMING_REQUIREMENTS.md)

- [ ] Build the submitted archive with Xcode 26 / SDK 26 or later (mandatory for
  iOS/iPadOS/visionOS/watchOS submissions). The current CI selects and verifies
  Xcode 26, but a green source build does not prove the submitted artifact;
  capture `xcodebuild -version` + resolved SDK versions from the exact archive.
- [ ] Ensure no `com.apple.quarantine` xattr exists anywhere inside the macOS
  app bundle before signing/upload (strip before signing, not after — stripping
  after signing changes the submitted artifact). Current `dist/` bundles were
  clean on 2026-07-10. `sign_app_bundle.sh` rejects quarantine recursively before
  signing; repeat the check against the exact submitted artifact as release
  evidence.
- [ ] Confirm `ITSAppUsesNonExemptEncryption=false` holds for the exact submitted
  build (Lorvex uses only exempt SHA-256 hashing). Already declared in every
  checked-in Info.plist and gated by `verify_app_metadata.py`.

## 6. App Store Connect — app record, listing & metadata

- [ ] Create the app record(s) for each platform.
- [ ] Paste listing copy from `apps/apple/docs/APP_STORE_METADATA.md` (name,
  subtitle, keywords, promotional text, description, what's-new, category,
  copyright, URLs).
- [ ] Set the Privacy Policy URL to `https://lorvex.app/privacy/`.
- [ ] Set the Support URL to `https://lorvex.app/support/` (see §10 for the
  policy analysis).
- [ ] Paste the App Review notes draft from the metadata file into App Review
  Information, and provide the **private** reviewer contact (first/last name,
  phone, email) — Apple-facing only, not published (see §10).

## 7. App Privacy answers (the public "nutrition label")

The privacy manifests, `PRIVACY.md`, and the in-app `PRIVACY_SUMMARY.md` are
mutually consistent today: no tracking, no tracking domains, no collected data,
and only the UserDefaults (`CA92.1`) and file-timestamp (`C617.1`)
required-reason APIs. Verified in this pass — no repo change was needed.

- [ ] Answer the App Store Connect App Privacy questionnaire as **no data
  collected / no tracking**, consistent with the above. The exact click-path
  answers to enter are in `apps/apple/docs/APP_STORE_PRIVACY_ANSWERS.md`.
- [ ] Rationale to keep on file (per `APP_PRIVACY_DETAILS.md`): planner content
  is processed on device and, when sync is on, stored in the user's own CloudKit
  private database operated by Apple — it is not "collected" by a Lorvex server
  (there is none). MetricKit diagnostics stay in a local log Lorvex never
  transmits. The external MCP client is user-configured, not an SDK embedded in
  the binary.
- [ ] Do not infer the answers from `PrivacyInfo.xcprivacy` alone. Generate
  Xcode's privacy report from the exact signed archive, compare it to the App
  Privacy answers and to `PRIVACY.md`, and save it with release evidence. Any
  future crash uploader, analytics SDK, support-upload, or hosted-AI feature
  would invalidate the "no collection" answer.

## 8. Age rating

- [ ] Complete the current age-rating questionnaire (mandatory since 2026-01-31)
  for **every** platform record. Lorvex has no mature content; the expected
  result is the lowest rating, but the questionnaire itself is required.

## 9. EU Digital Services Act (DSA) trader status

- [ ] Decide and declare the developer's DSA status in App Store Connect (see
  §10 for how this interacts with the lorvex.app contact policy). This is a
  required gate for distributing to EU storefronts and is distinct from the
  Support URL.

## 10. Support URL & developer-contact boundary

The repo's contact policy routes all public contact through the lorvex.app
support and privacy pages, no email/phone/address. App Store distribution
touches contact information in **three separate places**, and they do not all
behave the same way. macOS App Store and iOS App Store have **identical**
requirements here (both go through the same App Store Connect record); the real
variable is EU distribution, not the platform.

| Contact surface | Visibility | What Apple requires | How Lorvex satisfies it |
|---|---|---|---|
| **Support URL** (per version) | Public | A page giving users a way to get support / reach the developer (Guideline 1.5). | The public `https://lorvex.app/support/` page is the actionable support channel; no email is needed there. |
| **App Review contact** (App Review Information) | Private — Apple reviewers only | First/last name, phone, email so a reviewer can reach the developer. | A mandatory Apple-facing input; it needs a real phone + email. It is never published, so it does **not** conflict with the public no-email policy, but the owner must still supply real details to Apple. |
| **DSA trader disclosure** (EU) | Public on the EU product page | For a "trader," Apple publicly displays name, address, phone, and email. A verified non-trader can decline, but Apple may then restrict EU availability. | If the owner distributes to the EU as a trader, the lorvex.app pages do not replace the required public address/phone/email. |

Precise reading (confirm against the live App Store Connect flow and Apple's
current DSA guidance at submission — Apple updates both independently of this
repo; `APP_STORE_SUPPORT_URL.md` was last verified 2026-07-10):

- The **Support URL field** is `https://lorvex.app/support/`, and the Privacy
  Policy URL is `https://lorvex.app/privacy/`. Both are live public pages and
  the macOS Help menu points to the same support page. No email is needed there;
  this part of the contact policy holds.
- The **App Review private contact** requires a real name/phone/email given only
  to Apple. This does not break the public no-email policy (it is not
  published), but it is an unavoidable account-level input — the owner provides
  their own contact to Apple. This checklist does not invent one.
- The **DSA trader decision** is the genuine tension. Options for the owner:
  1. Declare **non-trader** if Lorvex is genuinely non-commercial (e.g. free,
     no monetization). Then no public address/phone/email is forced, but confirm
     the current EU-availability consequence of a non-trader declaration.
  2. If **trader**, the public no-email policy cannot hold for the EU storefront:
     Apple publishes trader address/phone/email. The owner must either provide
     public contact info or not distribute in the EU.
- Net: the lorvex.app contact policy is sufficient for the **public listing**
  (Support URL, privacy policy, marketing) and for the app's in-app contact
  routes. It is **not** sufficient on its own for the **private** App Review
  contact or for a **trader** DSA disclosure. Both are account-level inputs the
  owner supplies directly to Apple; neither requires inventing a public email in
  the repo.

Decision to record before filling App Store Connect metadata:

- [ ] Support URL set to `https://lorvex.app/support/`.
- [ ] App Review private contact details ready (owner's own name/phone/email).
- [ ] DSA trader vs non-trader status decided, with EU-availability implications
  understood.

## 11. Screenshots & previews

- [ ] Capture required screenshots for each platform/device class (macOS,
  iPhone, iPad, and visionOS if submitted) at Apple's current required sizes.
  The sizes, capture method, and per-surface shot list are in
  `apps/apple/docs/APP_STORE_SCREENSHOTS.md`. `_shots/` is gitignored;
  deliverables are produced for review, not tracked.
- [ ] Optional app preview videos.

## 12. Signed release candidates, on-device validation, TestFlight

- [ ] Build signed RC artifacts: macOS App Store `.pkg` via
  `archive_mas.sh --package`, the direct-distribution production Developer ID
  DMG via `package_dmg.sh`, and iPhone IPA via `archive_ios.sh --export`.
- [ ] Validate a real MAS export in Transporter / App Store Connect; the
  app-sandbox + App-Group helper model must pass upload validation.
- [ ] Nested signature/profile/entitlement audits on the real signed archive
  (the credentialed halves the offline verifiers cannot cover).
- [ ] Live multi-device iCloud smoke tests: account switch, zone deletion,
  offline conflict, helper-first upgrade, concurrent reset, real sandboxed
  two-process flock/cutover.
- [ ] A TestFlight round (note: TestFlight shares crash reports with the
  developer automatically — already disclosed in `PRIVACY.md`).
- [ ] Release evidence: install + launch the exact signed IPA / MAS `.pkg` on
  real hardware. For direct distribution, retain the versioned
  `Lorvex-macOS-<version>+<build>-arm64.dmg`, its checksum, and the
  `package_dmg.sh` evidence directory proving the app copied from that mounted
  final DMG was the app cold-launched and helper-smoked after destructive reset.
  Capture signed-Release launch/memory metrics.
- [ ] macOS route decision: Mac App Store vs. Developer ID notarized (they are
  distinct pipelines — do not submit the notarized zip/DMG to the Mac App Store).

## 13. Cross-repo reference reconciliation (Tauri updater & links)

The Tauri app still points several URLs at the old `ai-native-todo` repository;
the monorepo publishes as `lorvex`. Reconcile these at the publish cut. **Do not
change Tauri code as part of the Apple release work** — this is a note so the
owner does not forget when the Tauri line is cut. Occurrences found:

- `apps/tauri/app/src-tauri/tauri.conf.json:61` — updater endpoint
  `https://github.com/boyugou/ai-native-todo/releases/latest/download/latest.json`
  (the functional one: an unreconciled endpoint checks the wrong repo's releases).
- `apps/tauri/app/src-tauri/src/desktop_shell/app_menu.rs:76,82,89,103` — Help
  menu links (repo, Getting Started, MCP setup, new issue).
- `apps/tauri/app/src-tauri/src/calendar_subscription_sync/fetch.rs:88` and
  `apps/tauri/lorvex-cli/src/commands/mutate/subscriptions.rs:66` — HTTP
  user-agent strings embedding the old repo URL.

- [ ] Reconcile the updater endpoint and the links/user-agents to the published
  `lorvex` repo (or the Tauri app's own release location) when the Tauri line is
  published.

## 14. Trademark check

- [ ] Trademark clearance (mostly cleared): no productivity-space "Lorvex"
  conflict was found, and nothing blocks. A formal USPTO / EUIPO Class 9/42
  search before heavy branding spend is prudent.
