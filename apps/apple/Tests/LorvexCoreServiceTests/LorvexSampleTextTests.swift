#if DEBUG
  import Foundation
  import Testing

  @testable import LorvexCore

  /// Pins the sample-content translation behind localized captures: English is
  /// the identity, a language without a table falls back to English, and a
  /// preview store seeded in a translated language holds none of the English
  /// sample content, so a localized screenshot never mixes the two.
  @Suite("Sample text — localized preview content")
  struct LorvexSampleTextTests {
    @Test("English returns every string as written")
    func englishIsIdentity() {
      let text = LorvexSampleText.english
      #expect(text("Draft the team offsite agenda") == "Draft the team offsite agenda")
      #expect(text(["work", "home"]) == ["work", "home"])
    }

    @Test("a language without a table returns the English strings")
    func untranslatedLanguageFallsBack() {
      #expect(LorvexSampleText(language: .fr)("Renew passport") == "Renew passport")
    }

    @Test("Simplified Chinese translates titles and tags and keeps product names")
    func simplifiedChinese() {
      let text = LorvexSampleText(language: .zhHans)
      #expect(text("Draft the team offsite agenda") == "起草团建议程")
      #expect(text(["work", "planning"]) == ["工作", "规划"])
      #expect(text("Zoom") == "Zoom")
    }

    @Test("a preview store seeded in Simplified Chinese holds no English sample content")
    func chineseSeededStore() async throws {
      let core = try await LorvexPreviewCoreFactory.makeUIPreviewSeeded(
        todaySchedule: true, plannedDay: true, dayState: .overbooked,
        text: LorvexSampleText(language: .zhHans))
      let today = try await core.loadToday()
      let day = try #require(today.logicalDay)

      #expect(Self.isChinese(today.briefing ?? ""), "briefing: \(today.briefing ?? "nil")")
      let tasks = try await core.listTasks(
        status: "all", listID: nil, priority: nil, text: nil, limit: 200, offset: 0
      ).tasks
      #expect(!tasks.isEmpty)
      for task in tasks {
        #expect(Self.isChinese(task.title), "task title: \(task.title)")
        for tag in task.tags {
          #expect(Self.isChinese(tag), "tag: \(tag)")
        }
        if !task.notes.isEmpty {
          #expect(Self.isChinese(task.notes), "task notes: \(task.notes)")
        }
        let checklist = try await core.loadTask(id: task.id).checklistItems
        for item in checklist {
          #expect(Self.isChinese(item.text), "checklist item: \(item.text)")
        }
      }
      // The Inbox is the schema's own row, named by the interface, not the seed.
      for list in try await core.loadLists().lists where list.id != LorvexPreviewSeedID.inboxList {
        #expect(Self.isChinese(list.name), "list: \(list.name)")
      }
      for habit in try await core.loadHabits(date: day).habits {
        #expect(Self.isChinese(habit.name), "habit: \(habit.name)")
        #expect(Self.isChinese(habit.cue ?? ""), "habit cue: \(habit.cue ?? "nil")")
      }
      let events =
        try await core.loadCalendarTimeline(from: day, to: day).events
        + core.loadCalendarTimeline(from: "2026-05-22", to: "2026-05-22").events
      #expect(!events.isEmpty)
      for event in events {
        #expect(Self.isChinese(event.title), "event: \(event.title)")
      }
      for entry in try await core.loadMemory().entries {
        #expect(Self.isChinese(entry.content), "memory: \(entry.content)")
      }
    }

    /// Whether `text` is written in Chinese: it has Han characters and no
    /// English word longer than an acronym or a product name the tables keep
    /// (GRPO, Swift, UI).
    private static func isChinese(_ text: String) -> Bool {
      let hasHan = text.unicodeScalars.contains { $0.properties.isIdeographic }
      let englishWords = text.split { !$0.isLetter || !$0.isASCII }
        .filter { word in word.count > 1 && !["GRPO", "Swift", "UI", "Apple", "B"].contains(word) }
      return hasHan && englishWords.isEmpty
    }
  }
#endif
