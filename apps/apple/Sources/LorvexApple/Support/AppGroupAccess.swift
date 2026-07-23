import Foundation
import LorvexCore
import Security

enum AppGroupAccess {
  private static let entitlementKey = "com.apple.security.application-groups"

  static func isEntitled(
    to appGroupID: String = LorvexProductMetadata.appGroupIdentifier
  ) -> Bool {
    guard hasStableTeamIdentifier(signingTeamIdentifier()) else {
      return false
    }
    guard let task = SecTaskCreateFromSelf(nil),
      let value = SecTaskCopyValueForEntitlement(task, entitlementKey as CFString, nil)
    else {
      return false
    }
    return entitlementGroups(from: value).contains(appGroupID)
  }

  static func userDefaults(
    for appGroupID: String = LorvexProductMetadata.appGroupIdentifier
  ) -> UserDefaults? {
    guard isEntitled(to: appGroupID) else { return nil }
    return UserDefaults(suiteName: appGroupID)
  }

  static func containerURL(
    for appGroupID: String = LorvexProductMetadata.appGroupIdentifier,
    fileManager: FileManager = .default
  ) -> URL? {
    guard isEntitled(to: appGroupID) else { return nil }
    return fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
  }

  static func entitlementGroups(from value: Any?) -> [String] {
    if let groups = value as? [String] {
      return groups
    }
    if let group = value as? String {
      return [group]
    }
    return []
  }

  static func hasStableTeamIdentifier(_ teamIdentifier: String?) -> Bool {
    guard let teamIdentifier,
      !teamIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return false
    }
    return teamIdentifier.caseInsensitiveCompare("not set") != .orderedSame
  }

  private static func signingTeamIdentifier() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else {
      return nil
    }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
      let staticCode
    else {
      return nil
    }
    var information: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
      let information
    else {
      return nil
    }
    let info = information as NSDictionary
    return info[kSecCodeInfoTeamIdentifier] as? String
  }
}
