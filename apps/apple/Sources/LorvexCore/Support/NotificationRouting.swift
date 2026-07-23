import Foundation

/// Notification userInfo key-based routing for Lorvex local notifications.
///
/// Extracts a deep-link URL from a notification's userInfo dictionary.
/// `taskIDUserInfoKey` is present on all task reminder notifications; it is
/// used to build a task deep-link when no explicit deep-link URL is stored.
public enum LorvexNotificationRoute: Equatable, Sendable {
  public static let taskIDUserInfoKey = "lorvex_task_id"
  public static let deepLinkUserInfoKey = "lorvex_deep_link"

  case deepLink(URL)

  public init?(userInfo: [AnyHashable: Any]) {
    if let rawDeepLink = userInfo[Self.deepLinkUserInfoKey] as? String,
      let url = URL(string: rawDeepLink),
      LorvexDeepLinkRoute(url: url) != nil
    {
      self = .deepLink(url)
      return
    }

    guard let taskID = userInfo[Self.taskIDUserInfoKey] as? String, !taskID.isEmpty else {
      return nil
    }
    self = .deepLink(LorvexDeepLinkRoute.task(taskID).url)
  }

  public var url: URL {
    switch self {
    case .deepLink(let url):
      url
    }
  }
}
