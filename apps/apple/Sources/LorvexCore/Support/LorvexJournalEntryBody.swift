#if os(iOS) || os(macOS)
  import SwiftUI

  /// The saved entry in reading order. The surrounding page owns navigation,
  /// empty states and related activity.
  public struct LorvexJournalEntryBody: View {
    let review: DailyReviewEntry
    let feeling: (Int) -> String
    let energy: (Int) -> String

    public init(review: DailyReviewEntry, feeling: @escaping (Int) -> String, energy: @escaping (Int) -> String) {
      self.review = review
      self.feeling = feeling
      self.energy = energy
    }

    public var body: some View {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
        written(String(localized: "review.calm.note", defaultValue: "Note", bundle: CoreL10n.bundle), review.summary)
        written(WeekJournalCopy.wins, review.wins)
        written(WeekJournalCopy.blockers, review.blockers)
        written(WeekJournalCopy.learnings, review.learnings)
        if let mood = review.mood {
          rating(String(localized: "review.calm.feel", defaultValue: "How did it feel?", bundle: CoreL10n.bundle),
            word: feeling(mood), value: WeekJournalCopy.mood(mood), id: "reviews.readonly.mood")
        }
        if let level = review.energyLevel {
          rating(String(localized: "review.field.energy", defaultValue: "Energy", bundle: CoreL10n.bundle),
            word: energy(level), value: WeekJournalCopy.energy(level), id: "reviews.readonly.energy")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func written(_ label: String, _ text: String?) -> some View {
      if let text, text.trimmedNilIfEmpty != nil {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
          LorvexPageLabel(label).accessibilityAddTraits(.isHeader)
          Text(userContent: text)
            .font(LorvexDesign.Typography.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
      }
    }

    private func rating(_ label: String, word: String, value: String, id: String) -> some View {
      LabeledContent(label, value: word)
        .font(LorvexDesign.Typography.primaryText)
        .accessibilityValue("\(word), \(value)")
        .accessibilityIdentifier(id)
    }
  }
#endif
