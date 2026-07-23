import Foundation
import LorvexCore

enum MobileListDetailFormatters {
  static func summary(for detail: ListDetailSnapshot) -> String {
    summary(totalMatching: detail.totalMatching, returned: detail.returned)
  }

  static func summary(totalMatching: Int, returned: Int) -> String {
    String(
      format: String(
        localized: "list_detail.summary.matching_shown",
        defaultValue: "%1$lld matching, %2$lld shown", table: "Localizable",
        bundle: MobileL10n.bundle),
      totalMatching,
      returned
    )
  }
}
