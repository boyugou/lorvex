# App Review Guidelines

Source: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

Last verified: 2026-07-10

## Apple Contract

- Submission must be a final, functional build with accurate metadata, working
  URLs, live services, and enough review information to exercise non-obvious
  features.
- Mac App Store apps must be sandboxed and self-contained. They must not use an
  external update mechanism or leave continuing processes after quit without
  user consent.
- Background services may be used only for their intended purposes.
- A privacy policy must be available in App Store Connect and easily accessible
  inside the app.
- Guideline 5.1.2 requires clear disclosure and explicit permission before
  personal data is shared with a third party, expressly including third-party
  AI.

## Lorvex Mapping

- macOS and mobile both expose the bundled privacy summary and full-policy link.
- The macOS Assistant settings explain that the selected AI client can read and
  modify tasks, lists, habits, memory, reviews, and calendar entries. Copying the
  setup prompt/config and installing it in a chosen client is an affirmative,
  user-directed setup sequence.
- `LorvexMCPHost.app` is a bundled, separately signed sandboxed helper. A user's
  external assistant launches it over stdio; Lorvex does not install an updater
  or a resident daemon.
- The helper and the external-AI data flow are non-obvious to a reviewer and
  should be described explicitly in Review Notes, including how to open Settings
  and inspect the disclosure without requiring a third-party account.

## Review Risk

The UI disclosure is materially stronger than a generic privacy-policy link,
but the policy repeatedly says Lorvex “never transmits” data. Apple's rule is
framed in terms of sharing/providing access, not transport topology. Review Notes
and future policy wording should say plainly that user-authorized MCP access
shares Lorvex content with the chosen third-party AI client, even though the
handoff begins locally over stdio and Lorvex operates no server.

This is a wording/review-evidence risk, not a demonstrated code violation.

## Release Evidence

- Screenshot the Assistant disclosure and the privacy-policy entry point.
- Explain that MCP is off until the user configures an external client.
- Explain that the helper exits with its stdio client and is not an updater or
  daemon.
- Provide a reviewer path that does not depend on Claude, Codex, or another
  third-party login.
