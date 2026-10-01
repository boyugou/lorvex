import Foundation
import LorvexCloudSync
import LorvexCore
import Testing

@testable import LorvexApple

/// The shape CloudKit delivers for a database subscription: the container in
/// `ck.cid`, the subscription metadata under `ck.met`.
private func databasePush(container: String) -> [String: Any] {
  [
    "aps": ["content-available": 1],
    "ck": [
      "ce": 2,
      "cid": container,
      "nid": "6f0b9c1e-2d3a-4b5c-8d7e-9f0a1b2c3d4e",
      "ckuserid": "_0123456789abcdef0123456789abcdef",
      "met": [
        "dbs": 1,
        "sid": "sync-engine-chosen-subscription-id",
        "zid": "Lorvex",
        "zoid": "_defaultOwner",
      ],
    ],
  ]
}

@Test
func cloudKitPushParserRecognisesADatabasePushForLorvexsContainer() {
  let userInfo = databasePush(container: LorvexProductMetadata.cloudKitContainerIdentifier)
  #expect(CloudKitPushParser.isLorvexCloudKitNotification(userInfo) == true)
}

@Test
func cloudKitPushParserRejectsAnotherContainersPush() {
  let foreign = databasePush(container: "iCloud.com.example.other")
  #expect(CloudKitPushParser.isLorvexCloudKitNotification(foreign) == false)
}

@Test
func cloudKitPushParserRejectsAPayloadThatIsNotCloudKit() {
  let plain: [String: Any] = ["aps": ["alert": "Reminder"]]
  #expect(CloudKitPushParser.isLorvexCloudKitNotification(plain) == false)
  #expect(CloudKitPushParser.isLorvexCloudKitNotification([:]) == false)
}
