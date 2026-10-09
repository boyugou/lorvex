import SwiftUI

/// How the Today widget typesets its own text, so that a language whose script
/// has taller line metrics than Latin does not cost the widget a task row.
///
/// SwiftUI typesets text by the rules of the interface language, and under
/// Tamil, Thai, Arabic, Vietnamese (whose stacked tone marks need the room)
/// and the other languages in ``tallLineLanguages`` every line, Latin text
/// included, gets a taller line box. A medium widget fits its
/// second task row with a few points to spare and `ViewThatFits` takes the
/// first candidate that fits, so those points drop the row. Typesetting the
/// widget as English keeps its line boxes at Latin height. The text stays in
/// the interface language, and each script's glyphs are still chosen by the
/// script of the text, so they draw as before.
///
/// Languages whose glyph forms follow the typesetting language are not in the
/// list: Chinese, Japanese and Korean ideographs, and Urdu, which draws in a
/// Nastaliq face only under an Urdu typesetting language.
public enum WidgetTypesetting {
  /// The interface languages whose line metrics are taller than Latin's and
  /// whose scripts draw the same under English typesetting.
  public static let tallLineLanguages: Set<String> = [
    "ar", "bn", "fa", "hi", "mr", "ta", "te", "th", "vi",
  ]

  /// Whether the widget typesets as English under the interface language that
  /// `localization` names (the language its strings resolved to at launch).
  public static func typesetsAsLatin(localization: String?) -> Bool {
    guard let localization,
      let code = Locale.Language(identifier: localization).languageCode?.identifier
    else { return false }
    return tallLineLanguages.contains(code)
  }

  /// The language the widget's strings resolved to at launch.
  static let interfaceTypesetsAsLatin = typesetsAsLatin(
    localization: WidgetL10n.bundle.preferredLocalizations.first)

  static let latinLanguage = Locale.Language(identifier: "en")
}

extension View {
  /// This view typeset as English when the widget's interface language is
  /// one of ``WidgetTypesetting/tallLineLanguages``, and as the interface
  /// language otherwise.
  func widgetTypesetting() -> some View {
    typesettingLanguage(
      WidgetTypesetting.latinLanguage, isEnabled: WidgetTypesetting.interfaceTypesetsAsLatin)
  }
}
