# App Store Upcoming Requirements

Source: [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)

Last verified: 2026-07-15

## Current Apple Gates

- Since 2026-04-28, iOS, iPadOS, tvOS, visionOS, and watchOS submissions must be
  built with Xcode 26 or later and the corresponding version 26 SDK or later.
- The updated age-rating questionnaire has been mandatory since 2026-01-31.
- Since 2025-02-18, macOS apps uploaded to App Store Connect must not contain the
  `com.apple.quarantine` extended attribute anywhere inside the app.
- Approved reasons for required-reason APIs remain an upload requirement.

These are upload/account gates in addition to App Review behavior rules.

## Lorvex Mapping

The current developer machine reports Xcode 26.6, which satisfies the SDK gate.
The GitHub Apple workflow runs on `macos-15`, explicitly selects the newest
installed Xcode 26.x, exports that `DEVELOPER_DIR`, and fails if Xcode 26 is not
available. Its evidence step prints the selected Xcode version and requires the
macOS, iOS, xrOS, and watchOS 26 SDKs. The iOS archive script independently
rejects an iPhoneOS SDK older than version 26 before a device archive.

The repository verifies privacy manifests and recursively rejects a
`com.apple.quarantine` attribute anywhere in the staged app before signing.
That ordering prevents a contaminated file from entering a signed artifact and
avoids silently mutating the artifact after signing.

## Release Gates

- Keep the CI Xcode-26 selection and multi-platform SDK evidence current when
  GitHub changes the `macos-15` runner inventory.
- Complete the current age-rating questionnaire in App Store Connect for every
  platform record.
- Keep the pre-sign recursive quarantine rejection in every path that stages a
  distributable app; never strip quarantine after signing.
- Re-run the page before each submission because Apple updates it independently
  of the repository.

GitHub runner mapping source: [GitHub Actions macOS 15 image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)
