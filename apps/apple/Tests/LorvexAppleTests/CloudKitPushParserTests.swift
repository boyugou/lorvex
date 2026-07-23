import Foundation
import LorvexCloudSync
import LorvexCore
import Testing

@testable import LorvexApple

@Test
func cloudKitPushParserRecognisesLorvexSubscriptionPayload() {
  let userInfo: [String: Any] = ["ck": ["sub": "lorvex-private-db-changes"]]
  #expect(CloudKitPushParser.isLorvexCloudKitNotification(userInfo) == true)
}

@Test
func cloudKitPushParserRejectsNonLorvexSubscriptionPayload() {
  let foreign: [String: Any] = ["ck": ["sub": "other-app-subscription"]]
  #expect(CloudKitPushParser.isLorvexCloudKitNotification(foreign) == false)
}

@Test
func cloudKitPushParserRejectsPayloadMissingCKKey() {
  let empty: [String: Any] = [:]
  #expect(CloudKitPushParser.isLorvexCloudKitNotification(empty) == false)
}
