import Foundation
import Testing

@testable import LorvexCore

@Test
func seededInboxShowsTheInterfaceLanguageNameUntilRenamed() {
  #expect(LorvexListNaming.displayName(id: "inbox", name: "Inbox", inboxName: "收件箱") == "收件箱")
  // A rename by the user or an assistant is shown as chosen, in every language.
  #expect(LorvexListNaming.displayName(id: "inbox", name: "Triage", inboxName: "收件箱") == "Triage")
  // Only the seeded list is special: another list named "Inbox" keeps its name.
  #expect(LorvexListNaming.displayName(id: "list-1", name: "Inbox", inboxName: "收件箱") == "Inbox")
}

@Test
func seededInboxAnswersToBothItsShownAndStoredNames() {
  #expect(
    LorvexListNaming.matchNames(id: "inbox", name: "Inbox", inboxName: "收件箱") == ["收件箱", "Inbox"])
  #expect(LorvexListNaming.matchNames(id: "inbox", name: "Inbox", inboxName: "Inbox") == ["Inbox"])
  #expect(LorvexListNaming.matchNames(id: "list-1", name: "Work", inboxName: "收件箱") == ["Work"])
}

@Test
func savingTheShownInboxNameUnchangedKeepsTheSeededName() {
  // The editor opened on "收件箱"; saving without renaming stores nothing new.
  #expect(
    LorvexListNaming.nameToStore(
      id: "inbox", storedName: "Inbox", editedName: "收件箱", inboxName: "收件箱") == "Inbox")
  #expect(
    LorvexListNaming.nameToStore(
      id: "inbox", storedName: "Inbox", editedName: "Triage", inboxName: "收件箱") == "Triage")
  // Once renamed, typing the localized word is a deliberate choice and is stored.
  #expect(
    LorvexListNaming.nameToStore(
      id: "inbox", storedName: "Triage", editedName: "收件箱", inboxName: "收件箱") == "收件箱")
  #expect(
    LorvexListNaming.nameToStore(
      id: "list-1", storedName: "Work", editedName: "收件箱", inboxName: "收件箱") == "收件箱")
}

@Test
func coreCatalogTranslatesTheInboxName() throws {
  let english = try #require(CoreL10n.bundle.url(forResource: "en", withExtension: "lproj"))
  let chinese = try #require(CoreL10n.bundle.url(forResource: "zh-Hans", withExtension: "lproj"))
  func inboxName(in lproj: URL) throws -> String? {
    let bundle = try #require(Bundle(url: lproj))
    return bundle.localizedString(forKey: "list.inbox.name", value: nil, table: "Localizable")
  }
  #expect(try inboxName(in: english) == "Inbox")
  #expect(try inboxName(in: chinese) == "收件箱")
}
