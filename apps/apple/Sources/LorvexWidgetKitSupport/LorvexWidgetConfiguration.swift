import Foundation
import LorvexCore

public struct LorvexWidgetConfiguration: Equatable, Sendable {
  public static let appGroupInfoPlistKey = "LorvexWidgetAppGroupID"

  public let kind: String
  public let appGroupID: String?
  public let snapshotFileName: String

  public init(
    kind: String = LorvexProductMetadata.widgetKind,
    appGroupID: String? = LorvexWidgetConfiguration.defaultAppGroupID(),
    snapshotFileName: String = WidgetSnapshotLoader.defaultSnapshotFileName
  ) {
    self.kind = kind
    self.appGroupID = appGroupID
    self.snapshotFileName = snapshotFileName
  }

  public static func defaultAppGroupID(bundle: Bundle = .main) -> String? {
    let value = bundle.object(forInfoDictionaryKey: appGroupInfoPlistKey) as? String
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed
  }

  public func snapshotURL(in containerURL: URL) -> URL {
    WidgetSnapshotLoader().snapshotURL(
      inAppGroupContainer: containerURL,
      fileName: snapshotFileName
    )
  }

  public func resolvedSnapshotURL(fileManager: FileManager = .default) -> URL? {
    guard let appGroupID,
      let containerURL = fileManager.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupID
      )
    else {
      return nil
    }
    return snapshotURL(in: containerURL)
  }
}
