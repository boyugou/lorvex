import Foundation
import LorvexCore

/// Activity type string constants for NSUserActivity Handoff on the mobile surface.
///
/// These re-export the canonical constants from `LorvexActivityType` in LorvexCore
/// so that activities published on macOS can be continued on iOS/iPadOS/visionOS
/// and vice versa.
public enum MobileActivityType {
  public static let openTask = LorvexActivityType.openTask
  public static let openDestination = LorvexActivityType.openDestination
  public static let openList = LorvexActivityType.openList
}
