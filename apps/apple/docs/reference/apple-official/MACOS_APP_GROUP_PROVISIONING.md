# macOS App Group Provisioning and Final Signed Entitlements

Primary sources:

- [Accessing app group containers in your existing macOS app](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)
- [App Groups entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)
- [TN3125: Inside Code Signing: Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
- [TN2415: Entitlements Troubleshooting](https://developer.apple.com/library/archive/technotes/tn2415/)
- [Entitlements](https://developer.apple.com/documentation/bundleresources/entitlements)
- [Distribution provisioning profile](https://developer.apple.com/help/glossary/distribution-provisioning-profile/)
- [macOS 15 release notes — App Group container protection](https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes)
- [Apple DTS: App group broken on Sequoia](https://developer.apple.com/forums/thread/817268)

Last verified: 2026-07-21

## Apple Contract

An entitlement used at runtime is part of an executable's code signature. A
provisioning profile separately authorizes restricted entitlements; embedding a
profile does not by itself add those values to the code signature. Apple's
normal Xcode signing flow combines the target entitlement file, developer-
account information, and project information into the final signed
entitlements.

The prefix in `application-identifier` is an App ID prefix, not necessarily the
Team ID. TN2415 explicitly notes that the two are often equal but are not
guaranteed to be. A release verifier must therefore check the App ID prefix
against `ApplicationIdentifierPrefix` and independently check the signed team
entitlement against `TeamIdentifier`; equating the two can reject a legitimate
older developer account.

For a registered macOS App Group such as `group.com.lorvex.apple`, every
participating process needs the restricted entitlement in its signature and an
authorizing provisioning profile. The values must match the profile, including
any wildcard rules. Apple's current macOS guidance recommends checking the
running process with `launchctl procinfo` and looking for `entitlements
validated`; a plist/profile comparison alone is not equivalent runtime proof.

macOS 15 protects Group Containers with System Integrity Protection. Outside
the Mac App Store, an iOS-style `group.*` identifier must be authorized by an
embedded profile; otherwise the main app may prompt for temporary access and an
extension is denied without a prompt. Apple DTS additionally calls out the
signed `com.apple.application-identifier` as the association between the
program and that profile.

The alternative macOS-only App Group form, `<TeamIdentifier>.<group>`, does not
require registration or a provisioning profile, but it is not supported on
iOS-family platforms and is therefore not a drop-in replacement for Lorvex's
cross-platform group.

## Lorvex Mapping

`script/sign_app_bundle.sh` manually signs the main app, MCP helper, and widget
with caller-selected entitlement plists, then embeds the three provisioning
profiles. The generic local path uses the checked-in plists directly. The
production Developer ID DMG first runs
`script/prepare_profile_entitlements.py`, which reads each explicit profile and
adds its exact `com.apple.application-identifier` and
`com.apple.developer.team-identifier` to a temporary signing plist. This
recreates the profile-aware identifiers Xcode normally synthesizes without
changing the checked-in entitlement templates.

`script/verify_mas_provisioning.py` checks that each MAS profile has the expected
bundle identifier and authorizes the App Group/CloudKit/push values present in
the signed entitlements. It does not currently require the signed executable's
own application/team identifier to match the profile. Consequently, the
source-only checks cannot prove that macOS accepted the profile-backed
restricted entitlements for all three processes.

The production Developer ID path does not inherit the generic signer's soft
skip. `package_dmg.sh` requires explicit Developer ID profiles for the app,
helper and widget. `verify_developer_id_provisioning.py` decodes all three and
requires `ProvisionsAllDevices`, Developer ID Application certificates, the
expected team/bundle identifiers, production CloudKit/push authorization where
used, the App Group, valid expiry, and exact agreement with the final signed
entitlements. It also requires Developer ID authority, hardened runtime and
secure timestamps. Missing or unverifiable data is a hard release failure.

The exact app mounted from the final DMG is installed at the production install
path. A deterministic bundle-tree digest ties the installed file and symlink
content to that mounted source; LaunchServices registers that path; the main app
cold-launches only after the release harness permanently resets the real App
Group under its storage-generation lock and clears the app's defaults/private
CloudSync state; its PID is tied to the installed executable; and PlugInKit
must resolve the widget to the installed `.appex`.
The mounted/installed helper then
performs a write round-trip against the real App Group after stopping Lorvex
processes and resetting it again before and after the smoke. Neither phase
backs up or restores prior data. That proves the helper's runtime access. The
release harness also retains `launchctl procinfo`
output for the main app: when the noninteractive caller is authorized, the
output must say `entitlements validated`; when macOS requires root, that
unsupported result is recorded explicitly and a privileged operator record is
still required. Actual widget-process launch/procinfo remains an on-device
release record.

## Required Release Evidence

For a real Developer ID or Mac App Store release candidate, retain all of the
following for the main app, MCP helper, and widget extension:

1. Decoded embedded profile, including App ID, Team ID, distribution type,
   expiry, App Group, iCloud, and push authorization.
2. `codesign --display --entitlements - --xml` output from the final artifact.
3. A comparison proving the signed application/team identifiers and every
   restricted entitlement are authorized by that target's profile.
4. `codesign --verify --deep --strict` and App Store validation results.
5. On-device launch of each process and `launchctl procinfo` evidence showing
   validated entitlements.
6. A real shared-container read/write test between the main app, helper, and
   widget under the release profiles.

Treat failure to obtain this evidence as a packaging blocker. Do not infer
success merely because the profile files are embedded or because ad-hoc signing
passes structural tests.
