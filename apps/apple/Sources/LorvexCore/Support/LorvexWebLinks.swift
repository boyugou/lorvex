import Foundation

/// Public lorvex.app destinations for the app's website and user support/contact.
///
/// These are the canonical App Store entry points. The shipped app links to the
/// live lorvex.app static pages, so the source repository's visibility or name
/// never affects the app's website or support surface. No email address is used;
/// support and contact route through the support page.
public enum LorvexWebLinks {
  /// The marketing / website home page.
  public static let websiteURL = "https://lorvex.app/"

  /// The user-facing support and feedback/contact page.
  public static let supportURL = "https://lorvex.app/support/"
}
