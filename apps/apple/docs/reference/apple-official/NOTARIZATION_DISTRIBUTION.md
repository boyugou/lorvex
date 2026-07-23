# Notarization, Stapling, and the Distributed Artifact

Primary sources:

- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
- [TN3147: Migrating to the latest notarization tool](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)

Last verified: 2026-07-21

## Apple Contract

The notary service publishes a ticket online and also lets the developer staple
the ticket to the distributed software. Online lookup can make an unstapled app
work when Gatekeeper has network access, but stapling supplies the ticket with
the artifact and enables the intended offline evidence.

Apple's packaging guidance says to notarize the file intended for distribution
and then staple the resulting ticket to the file intended for distribution.
For ZIP delivery, the practical workflow is to submit a ZIP containing the
signed app, staple the accepted ticket to the app, and create the final ZIP from
that stapled app. DMG and installer-package formats can themselves be stapled.

## Lorvex Mapping

`script/package_dmg.sh` implements Apple's nested-container workflow for the
supported direct-distribution artifact. It submits a ZIP of the final signed
app, staples and verifies the app, builds and signs a DMG containing that exact
stapled payload, then submits and staples the outer DMG. This deliberate two-
round flow matches Apple's guidance for a payload that must remain independently
offline-verifiable after it is copied out of the outer container.

The command then runs `hdiutil verify`, assesses the DMG with Gatekeeper,
mounts it read-only, compares the mounted app to the staged payload, copies it
to a clean install location, and repeats strict signature, entitlement,
profile, staple, and Gatekeeper checks. App and DMG notary submission JSON and
logs, final signed-entitlement/profile dumps, a post-staple SHA-256, and a
machine-readable evidence manifest are retained under `dist/release-evidence`.

`script/notarize_archive.sh` remains a standalone ZIP diagnostic utility. Its
preflight and submit path are not the public DMG release workflow.

## Release Check

After notarization acceptance:

1. Staple and validate the app.
2. Recreate the final distribution ZIP from that exact stapled app, or use a
   directly stapled outer DMG/package.
3. Extract the final downloadable artifact into a clean location.
4. Run `stapler validate`, strict code-sign verification, and Gatekeeper checks
   against the extracted/downloaded copy.
5. Retain the notary log, final-artifact digest, and validation output together.

The final digest must be computed after stapling/repackaging. A digest of the
submitted pre-staple ZIP is not the digest of the final offline-verifiable
distribution.
