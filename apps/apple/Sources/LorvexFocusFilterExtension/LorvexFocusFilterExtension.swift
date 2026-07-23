import AppIntents
import ExtensionFoundation

/// Dedicated background host for `LorvexFocusFilterIntent`. The intent itself
/// has target membership only in this extension in the shipping iOS project,
/// allowing Focus transitions to run reliably without launching the app.
@main
struct LorvexFocusFilterExtension: AppIntentsExtension {}
