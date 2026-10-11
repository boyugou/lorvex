import Foundation

/// Removes the markdown punctuation from a note so a one-line quote of it reads
/// the way the rendered note does: heading, quote, list and checkbox markers at
/// the start of a line; `**`/`~~` runs and backticks; and the `[label](address)`
/// syntax of a link, which leaves its label.
///
/// One linear pass over the text with no recursion, so a note that nests
/// quotes or emphasis thousands of levels deep costs the same as any other.
/// Single `*` and `_` stay: they are as often a multiplication sign or part of
/// an identifier as emphasis. Line breaks are kept; the caller collapses them.
enum LorvexMarkdownMarks {
  /// A link label longer than this is not read as a link.
  private static let maxLabelLength = 200
  /// A link address longer than this is not read as a link.
  private static let maxAddressLength = 2_000

  static func removed(from source: String) -> String {
    source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .map { inlineText(of: withoutBlockMarker($0)) }
      .joined(separator: "\n")
  }

  private static func withoutBlockMarker(_ line: Substring) -> Substring {
    var rest = line.drop(while: { $0 == " " || $0 == "\t" })
    while rest.first == ">" { rest = rest.dropFirst().drop(while: { $0 == " " }) }
    let hashes = rest.prefix(while: { $0 == "#" }).count
    if (1...6).contains(hashes), rest.dropFirst(hashes).first == " " {
      return rest.dropFirst(hashes).drop(while: { $0 == " " })
    }
    if let marker = rest.first, "-*+".contains(marker), rest.dropFirst().first == " " {
      return withoutCheckbox(rest.dropFirst(2).drop(while: { $0 == " " }))
    }
    let digits = rest.prefix(while: { ("0"..."9").contains($0) }).count
    let afterDigits = rest.dropFirst(digits)
    if (1...9).contains(digits), let dot = afterDigits.first, dot == "." || dot == ")",
      afterDigits.dropFirst().first == " "
    {
      return withoutCheckbox(afterDigits.dropFirst(2).drop(while: { $0 == " " }))
    }
    return rest
  }

  private static func withoutCheckbox(_ text: Substring) -> Substring {
    for box in ["[ ] ", "[x] ", "[X] "] where text.hasPrefix(box) { return text.dropFirst(box.count) }
    return text
  }

  private static func inlineText(of line: Substring) -> String {
    var text = ""
    var index = line.startIndex
    while index < line.endIndex {
      let character = line[index]
      if character == "[", let link = link(in: line, openingAt: index) {
        text += inlineText(of: link.label)
        index = link.end
      } else if character == "`" || character == "*" || character == "~" {
        let run = line[index...].prefix(while: { $0 == character })
        if character == "`" || run.count >= 2 {
          index = line.index(index, offsetBy: run.count)
        } else {
          text.append(character)
          index = line.index(after: index)
        }
      } else {
        text.append(character)
        index = line.index(after: index)
      }
    }
    return text
  }

  /// The link whose label opens at `open`: the text up to the first `]`, then a
  /// parenthesized address. `nil` when the brackets are not followed by one.
  private static func link(
    in line: Substring, openingAt open: Substring.Index
  ) -> (label: Substring, end: Substring.Index)? {
    let labelStart = line.index(after: open)
    guard let labelEnd = line[labelStart...].prefix(maxLabelLength).firstIndex(of: "]") else {
      return nil
    }
    let addressOpen = line.index(after: labelEnd)
    guard addressOpen < line.endIndex, line[addressOpen] == "(",
      let addressEnd = line[line.index(after: addressOpen)...].prefix(maxAddressLength)
        .firstIndex(of: ")")
    else { return nil }
    return (line[labelStart..<labelEnd], line.index(after: addressEnd))
  }
}
