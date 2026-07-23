import Foundation

public enum LorvexDeepLinkContract {
  public static let scheme = "lorvex"
  public static let openHost = "open"
  public static let taskHost = "task"
  public static let listHost = "list"
  public static let habitHost = "habit"
  public static let reviewHost = "review"

  public static func destinationURL(_ destination: SidebarSelection) -> URL {
    makeURL(host: openHost, pathComponent: destination.rawValue)
  }

  public static func destinationURLString(_ destination: SidebarSelection) -> String {
    destinationURL(destination).absoluteString
  }

  public static func destinationURL(rawDestination: String) -> URL {
    makeURL(host: openHost, pathComponent: rawDestination)
  }

  public static func destinationURLString(rawDestination: String) -> String {
    destinationURL(rawDestination: rawDestination).absoluteString
  }

  public static func taskURL(_ id: LorvexTask.ID) -> URL {
    makeURL(host: taskHost, pathComponent: id)
  }

  public static func taskURLString(_ id: LorvexTask.ID) -> String {
    taskURL(id).absoluteString
  }

  public static func listURL(_ id: String) -> URL {
    makeURL(host: listHost, pathComponent: id)
  }

  public static func habitURL(_ id: String) -> URL {
    makeURL(host: habitHost, pathComponent: id)
  }

  public static func reviewURL(date: String) -> URL {
    makeURL(host: reviewHost, pathComponent: date)
  }

  public static func encodedPathComponent(_ value: String) -> String {
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }

  /// Inverse of `encodedPathComponent` for the single-segment entity URLs produced
  /// by `makeURL` (`task` / `list` / `habit` / `review` / `open`).
  ///
  /// The contract encodes an entire identifier — including any embedded `/` — as one
  /// percent-encoded path segment, so decoding via `URL.pathComponents` would split
  /// on the decoded slash and truncate the id (e.g. `"a/b"` → `"a"`). This reads the
  /// raw percent-encoded path and decodes it as a single unit, round-tripping ids
  /// that contain `/`, spaces, or `%`. Returns nil when the path is empty.
  public static func decodedPathComponent(from url: URL) -> String? {
    let rawPath = url.path(percentEncoded: true)
    let trimmed = rawPath.hasPrefix("/") ? String(rawPath.dropFirst()) : rawPath
    guard !trimmed.isEmpty, let decoded = trimmed.removingPercentEncoding, !decoded.isEmpty
    else { return nil }
    return decoded
  }

  private static func makeURL(host: String, pathComponent: String) -> URL {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.percentEncodedPath = "/" + encodedPathComponent(pathComponent)
    return components.url ?? URL(fileURLWithPath: "/")
  }
}
