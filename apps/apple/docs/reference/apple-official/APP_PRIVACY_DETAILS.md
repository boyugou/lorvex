# App Privacy Details on the App Store

Source: [App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/)

Last verified: 2026-07-10

## Apple Contract

- App Store Connect answers must cover data collected by the developer and by
  integrated third-party partners.
- “Collect” generally means transmitting data off device in a form accessible
  for longer than needed to service a real-time request.
- Data processed only on device is not collected for the privacy label.
- Free-form planner content maps to “Other User Content” when it is collected;
  the developer does not enumerate every possible fact a user may type.
- Apple says developers are not responsible for declaring data Apple itself
  collects through Apple services. Developers must still disclose data they
  themselves obtain from those services.
- Answers are app-level and must represent the most inclusive behavior across
  platforms.

## Lorvex Mapping

- The first-party privacy manifests declare no collection/tracking, matching the
  current architecture: no Lorvex backend, analytics, ads, or telemetry upload.
- Optional CloudKit private-database storage is operated by Apple and is not
  accessible through a Lorvex server.
- MetricKit payloads are retained only in the local database according to the
  product policy.
- The external MCP client is selected and configured by the user and is not an
  SDK integrated into the Lorvex binary. Nevertheless, the third-party-AI
  disclosure and permission requirement in App Review Guideline 5.1.2 still
  deserves explicit treatment in Review Notes.

## Release Check

Do not infer App Store Connect answers from `PrivacyInfo.xcprivacy` alone. Before
each release, compare the signed archive's privacy report, the App Store Connect
questionnaire, `PRIVACY.md`, and both in-app privacy screens. A future crash
uploader, support upload, analytics SDK, or hosted AI feature would invalidate
the current “no collection” answer even if the manifest did not change.
