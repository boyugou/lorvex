import SwiftUI

/// "What moved forward" on a review page: the finished tasks it names, each
/// behind a done mark. When the list is a capped slice of a count the page's
/// sentence states, `hiddenCount` is how many it leaves out, and a last line
/// says so ("1 more"), as ``LorvexReviewTaskList`` does, so the sentence and
/// the list never seem to disagree.
///
/// A title takes up to two lines, and all of its lines at the accessibility
/// text sizes. The list's identifier names the section, and the count line
/// appends "more".
public struct LorvexReviewMovedList: View {
  private let label: String
  private let tasks: [ReviewTaskSummary]
  private let hiddenCount: Int
  private let moreLine: (Int) -> String
  private let identifier: String

  /// - Parameters:
  ///   - label: the section's label.
  ///   - tasks: the finished tasks to list.
  ///   - hiddenCount: how many finished tasks the page's count includes
  ///     beyond `tasks`; zero or less shows no count line.
  ///   - moreLine: the count line for a positive `hiddenCount` ("2 more").
  ///   - identifier: the accessibility identifier of the section.
  public init(
    label: String, tasks: [ReviewTaskSummary], hiddenCount: Int,
    moreLine: @escaping (Int) -> String, identifier: String
  ) {
    self.label = label
    self.tasks = tasks
    self.hiddenCount = hiddenCount
    self.moreLine = moreLine
    self.identifier = identifier
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
      LorvexPageLabel(label)
      ForEach(tasks) { task in
        HStack(alignment: .firstTextBaseline, spacing: LorvexDesign.Spacing.s) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(LorvexDesign.Palette.done)
          Text(userContent: task.title)
            .lineLimitUnlessAccessibilitySize(2)
        }
        .font(LorvexDesign.Typography.primaryText)
      }
      if hiddenCount > 0 {
        Text(moreLine(hiddenCount))
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("\(identifier).more")
      }
    }
    .accessibilityIdentifier(identifier)
  }
}
