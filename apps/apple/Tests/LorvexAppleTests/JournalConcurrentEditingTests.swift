import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

@MainActor @Test("Mac and phone journal edits keep other fields already saved by another writer")
func journalWritersPreserveIndependentChanges() async throws {
  let core = try SwiftLorvexCoreService.inMemory()
  let phone = MobileStore(core: core)
  let mac = AppStore(core: core)
  await phone.refresh()
  await mac.refresh()
  await phone.loadDailyReviewDraft()
  let today = phone.selectedReviewDate
  #expect(mac.dailyReviewEditorDate == today)

  phone.dailyReviewDraft.energy = 3
  mac.dailyReviewWinsDraft = "Booked the studio."
  await mac.saveDailyReviewDraft()
  #expect(await phone.flushDailyReviewDraftIfNeeded())
  let combined = try #require(try await core.loadDailyReview(date: today))
  #expect(combined.wins == "Booked the studio.")
  #expect(combined.energyLevel == 3)
  #expect(phone.dailyReviewDraft.wins == combined.wins)

  // Mac still has the older form without the energy rating. Change both
  // clients again, including an intentional clear.
  mac.dailyReviewBlockersDraft = "Need the door code."
  phone.dailyReviewDraft.wins = ""
  #expect(await phone.flushDailyReviewDraftIfNeeded())
  await mac.saveDailyReviewDraft()
  let latest = try #require(try await core.loadDailyReview(date: today))
  #expect(latest.wins == nil)
  #expect(latest.energyLevel == 3)
  #expect(latest.blockers == "Need the door code.")
  #expect(mac.dailyReviewWinsDraft.isEmpty)
  #expect(mac.dailyReviewEnergy == 3)
}

@MainActor @Test("A refresh applies other people's journal fields without replacing a live text edit")
func journalWritersKeepTheActiveFieldAcrossRefresh() async throws {
  let core = try SwiftLorvexCoreService.inMemory()
  let phone = MobileStore(core: core)
  await phone.refresh()
  await phone.loadDailyReviewDraft()
  let day = phone.selectedReviewDate
  phone.dailyReviewDraft.summary = "Still writing "
  let written = try await core.upsertDailyReviewPreservingLinks(date: day, summary: "",
    mood: nil, energyLevel: 4, wins: "Found the venue", blockers: nil, learnings: nil)
  phone.adoptLoadedDailyReview(written, readFor: day)
  #expect(phone.dailyReviewDraft.summary == "Still writing ")
  #expect(phone.dailyReviewDraft.energy == 4)
  #expect(phone.dailyReviewDraft.wins == "Found the venue")
  phone.dailyReviewDraft.energy = nil
  #expect(await phone.flushDailyReviewDraftIfNeeded())
  let stored = try #require(try await core.loadDailyReview(date: day))
  #expect(stored.energyLevel == nil)
  #expect(stored.wins == written.wins)
  #expect(stored.summary == "Still writing")
  #expect(phone.dailyReviewDraft.summary == "Still writing ")
}
