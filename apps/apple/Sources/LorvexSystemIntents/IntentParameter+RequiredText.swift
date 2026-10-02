import AppIntents
import Foundation

extension IntentParameter where Value == String {
  /// The parameter's text without surrounding whitespace.
  ///
  /// When nothing is left, throws the parameter's needs-value error instead,
  /// so Siri and Shortcuts ask the person for the value — under the
  /// parameter's own title, in their language — rather than failing the
  /// action with a validation message.
  func requiredText() throws -> String {
    let text = wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw needsValueError() }
    return text
  }
}
