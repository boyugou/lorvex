# Create an App Store Connect Provisioning Profile

Source: [Create an App Store Connect provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)

Last verified: 2026-07-10

## Apple Contract

- Upload requires an App Store Connect app record and an explicit App ID matching
  the bundle ID.
- iOS/iPadOS/visionOS/watchOS and macOS use their corresponding App Store Connect
  distribution profile types.
- A manually managed profile binds one explicit App ID and one distribution
  certificate.
- Automatic signing can manage distribution profiles, but the resulting archive
  still needs verification.

## Lorvex Mapping

Lorvex ships several independently signed bundle identifiers: the macOS app, MCP
helper app, widget/complication extensions, mobile app, Watch app, and visionOS
app. A top-level app profile cannot stand in for nested targets. Each signed
bundle must have a matching explicit identifier, capabilities, and profile where
the platform/package format requires one.

The release scripts already verify many structural properties. The remaining
portal state is external and must be evidenced from the final archive/package,
not inferred from entitlement templates in Git.
