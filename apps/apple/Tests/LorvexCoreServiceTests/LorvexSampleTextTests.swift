#if DEBUG
  import Foundation
  import Testing

  @testable import LorvexCore

  /// Pins the sample-content translation behind localized captures: English is
  /// the identity, a language or string without a translation falls back to
  /// English, every shipped language has a table with the same keys as every
  /// other and translates each string (apart from a short list of words a
  /// language spells as English does), a translation writes its digits as its
  /// locale writes numbers, and a preview store seeded in a translated
  /// language holds none of the English sample content, so a localized
  /// screenshot never mixes the two.
  @Suite("Sample text — localized preview content")
  struct LorvexSampleTextTests {
    /// Table entries whose value is legitimately the English key itself,
    /// because the language spells the word the same way.
    private static let spelledAsInEnglish: [AppLanguage: Set<String>] = [
      .es: ["Personal"],
      .fr: ["urgent", "Studio"],
      .it: ["Studio"],
      .pl: ["Studio"],
    ]

    /// The registered tables in a stable order, so a failure message names
    /// languages the same way on every run.
    private static var orderedTables: [(language: AppLanguage, table: [String: String])] {
      LorvexSampleText.tables
        .sorted { $0.key.rawValue < $1.key.rawValue }
        .map { (language: $0.key, table: $0.value) }
    }

    @Test("English returns every string as written")
    func englishIsIdentity() {
      let text = LorvexSampleText.english
      #expect(text("Draft the team offsite agenda") == "Draft the team offsite agenda")
      #expect(text(["work", "home"]) == ["work", "home"])
    }

    @Test("a string missing from a table returns the English string")
    func missingEntryFallsBack() {
      let text = LorvexSampleText(language: .fr)
      #expect(text("Renew the passport tomorrow") == "Renew the passport tomorrow")
      let mixed = text(["work", "Renew the passport tomorrow"])
      #expect(mixed == ["travail", "Renew the passport tomorrow"])
    }

    @Test("a language without a table returns the English strings")
    func untranslatedLanguageFallsBack() {
      #expect(LorvexSampleText.tables[.system] == nil)
      #expect(LorvexSampleText(language: .system)("Renew passport") == "Renew passport")
    }

    @Test("every shipped language except English has a table")
    func everyShippedLanguageHasATable() {
      let shipped = Set(AppLanguage.selectable).subtracting([.en])
      #expect(Set(LorvexSampleText.tables.keys) == shipped)
    }

    @Test("every table has exactly the keys of the Simplified Chinese table")
    func tablesShareOneKeySet() {
      let reference = Set(LorvexSampleText.simplifiedChinese.keys)
      for (language, table) in Self.orderedTables {
        let keys = Set(table.keys)
        let missing = reference.subtracting(keys).sorted()
        let extra = keys.subtracting(reference).sorted()
        #expect(missing.isEmpty, "\(language.rawValue) is missing \(missing)")
        #expect(extra.isEmpty, "\(language.rawValue) has keys no other table has: \(extra)")
      }
    }

    @Test("every table translates each string, apart from words the language spells as English does")
    func valuesDifferFromTheirKeys() {
      for (language, table) in Self.orderedTables {
        let allowed = Self.spelledAsInEnglish[language] ?? []
        let identical = Set(table.filter { $0.key == $0.value }.keys)
        let untranslated = identical.subtracting(allowed).sorted()
        let staleAllowances = allowed.subtracting(identical).sorted()
        #expect(untranslated.isEmpty, "\(language.rawValue) leaves \(untranslated) in English")
        #expect(
          staleAllowances.isEmpty,
          "\(language.rawValue) allows \(staleAllowances) to match English, but translates it")
      }
    }

    @Test("a translation writes its digits as the locale writes numbers")
    func digitsFollowTheLocale() {
      let arabicDigits = LorvexSampleText(
        language: .ar, locale: Locale(identifier: "ar_SA@numbers=arab"))
      #expect(arabicDigits("Read 30 minutes") == "القراءة ٣٠ دقيقة")
      let asciiDigits = LorvexSampleText(
        language: .ar, locale: Locale(identifier: "ar_SA@numbers=latn"))
      #expect(asciiDigits("Read 30 minutes") == "القراءة 30 دقيقة")
      let persianDigits = LorvexSampleText(language: .ar, locale: Locale(identifier: "fa_IR"))
      #expect(persianDigits("Read 30 minutes") == "القراءة ۳۰ دقيقة")
      // English and a string without a translation come back as written.
      let english = LorvexSampleText(
        language: .en, locale: Locale(identifier: "ar_SA@numbers=arab"))
      #expect(english("Read 30 minutes") == "Read 30 minutes")
      #expect(arabicDigits("Call 2 vendors") == "Call 2 vendors")
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
        #expect(Self.isChinese(entry.displayTitle), "memory title: \(entry.key)")
      }
    }

    /// Whether `text` is written in Chinese: it has Han characters and no
    /// English word longer than an acronym or a product name the tables keep
    /// (AI, Apple, GRPO, Swift, UI).
    private static func isChinese(_ text: String) -> Bool {
      let hasHan = text.unicodeScalars.contains { $0.properties.isIdeographic }
      let englishWords = text.split { !$0.isLetter || !$0.isASCII }
        .filter { word in word.count > 1 && !["AI", "GRPO", "Swift", "UI", "Apple", "B"].contains(word) }
      return hasHan && englishWords.isEmpty
    }
  }
#endif
