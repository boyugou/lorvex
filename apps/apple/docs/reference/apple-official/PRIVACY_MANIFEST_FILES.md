# Privacy Manifest Files

Source: [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)

Last verified: 2026-07-10

## Apple Contract

Privacy manifests describe tracking, collected-data declarations, tracking
domains, and approved reasons for required-reason APIs. An app archive combines
the app's declarations with manifests contributed by embedded SDKs and packages.

## Lorvex Mapping

- The two first-party manifests currently agree on no tracking, no tracking
  domains, no collected data, and required reasons for UserDefaults and file
  timestamp access.
- The `C617.1` file-metadata reason matches the shipping `stat(2)` access used
  to identify the selected database file inside an app/app-group-managed
  storage location. The audit found no first-party timestamp/metadata access to
  arbitrary user-selected files. Keep this scope true; `C617.1` is not a
  blanket reason to inspect unrelated files.
- `script/verify_privacy_manifests.py` performs useful source-tree drift checks.
- A source-only scan cannot prove what every resolved Swift package contributes
  to the final archive.

## Release Check

Treat Xcode's privacy report from the exact signed archive as the final artifact.
The source verifier is necessary but not sufficient. Save the generated report
with release evidence and compare it to the App Store Connect privacy answers.
