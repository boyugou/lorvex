# Acquiring Crash Reports and Diagnostic Logs

Source: [Acquiring crash reports and diagnostic logs](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)

Last verified: 2026-07-10

## Apple Contract

- App Store crash reports can appear in Xcode Organizer for customers who
  share diagnostic and usage information.
- TestFlight users automatically share crash reports with the developer even
  when their ordinary device diagnostic-sharing setting is off.
- This operating-system/App Store channel is separate from an app-defined
  analytics or crash-upload SDK.

## Lorvex Mapping

Lorvex's own MetricKit subscriber writes selected diagnostics only to the local
database, and the app contains no custom upload path. That supports a “Lorvex
does not upload its local diagnostic log” statement.

It does not support a categorical guarantee that diagnostics are never sent to
Apple or the developer by the operating system and App Store/TestFlight
infrastructure. Privacy copy should separate Lorvex's local MetricKit storage
from Apple's user-controlled (and TestFlight-specific) crash-report channel.

