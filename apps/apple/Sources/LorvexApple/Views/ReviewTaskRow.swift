import LorvexCore
import SwiftUI

struct ReviewTaskRow: View {
  let task: ReviewTaskSummary
  let systemImage: String

  var body: some View {
    Label {
      VStack(alignment: .leading, spacing: 3) {
        Text(task.title)
          .lineLimit(1)
        Text(ReviewTaskRowText.subtitle(for: task))
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
      }
    } icon: {
      Image(systemName: systemImage)
        .foregroundStyle(.secondary)
    }
  }
}

enum ReviewTaskRowText {
  static func subtitle(for task: ReviewTaskSummary) -> String {
    let status = localizedStatus(task.status)
    guard task.deferCount > 0 else { return status }
    return String(
      format: String(
        localized:
          "reviews.weekly.task.deferred_count",
          defaultValue: "%@ · deferred %lldx",
          table: "Localizable",
          bundle: LorvexL10n.bundle),
      status,
      task.deferCount
    )
  }

  private static func localizedStatus(_ rawStatus: String) -> String {
    guard let status = LorvexTask.Status(rawValue: rawStatus) else { return rawStatus }
    return TaskDisplayText.status(status)
  }
}
