import LorvexCore
import SwiftUI

/// Persistence state of the daily-review draft, rendered by the form's footer
/// so the user always knows whether their reflection is on disk.
enum DailyReviewSaveState: Equatable {
  /// The draft is empty and nothing is persisted yet — there is nothing to
  /// save. The footer shows a starting prompt instead of silently disabling the
  /// button. (A summary is not required: any edit, body-only included, becomes
  /// `.unsaved` and autosaves.)
  case needsSummary
  /// The draft matches the persisted review.
  case saved
  /// Edits exist that have not been persisted yet (autosave is armed).
  case unsaved
}

struct DailyReviewForm: View {
  @Bindable var store: AppStore
  var scrollsInternally = true
  var saveState: DailyReviewSaveState = .needsSummary
  var onSave: () -> Void = {}
  /// Past day (`YYYY-MM-DD`) the editor is anchored to; `nil` = today.
  var editingDate: String? = nil
  var onReturnToToday: () -> Void = {}
  /// When true the day is outside the interactive write window: the saved
  /// review (if any) renders read-only, with no editors and no save footer.
  var isReadOnly = false
  var onEditorFocusChange: @MainActor @Sendable (Bool) -> Void = { _ in }

  var body: some View {
    Group {
      if scrollsInternally {
        ScrollView {
          content
        }
      } else {
        content
      }
    }
    .background(.background)
  }

  @ViewBuilder
  private var content: some View {
    if isReadOnly {
      DailyReviewReadOnlyView(review: store.dailyReview)
    } else {
      editableContent
    }
  }

  private var editableContent: some View {
    VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
      if let editingDate {
        editingBanner(editingDate)
      }

      ReviewPromptPanel(
        title: String(localized: "reviews.daily.title", defaultValue: "Daily Review", table: "Localizable", bundle: LorvexL10n.bundle),
        subtitle: String(
          localized:
            "reviews.daily.summary_prompt",
            defaultValue: "One honest paragraph is enough.",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
        systemImage: "square.and.pencil",
        tint: .blue
      ) {
        LorvexPlainTextEditor(
          text: $store.dailyReviewSummaryDraft,
          placeholder: String(
            localized:
              "reviews.daily.summary.placeholder",
              defaultValue: "What changed today?",
              table: "Localizable",
              bundle: LorvexL10n.bundle
            ),
          minHeight: 90,
          fontSize: 14,
          onFocusChange: onEditorFocusChange
        )
        .accessibilityLabel(String(localized: "reviews.daily.summary", defaultValue: "Summary", table: "Localizable", bundle: LorvexL10n.bundle))
        .accessibilityIdentifier("review.summary")

        Divider()

        HStack(spacing: LorvexDesign.Spacing.m) {
          ReviewRatingPicker(
            title: String(localized: "reviews.daily.mood", defaultValue: "Mood", table: "Localizable", bundle: LorvexL10n.bundle),
            symbol: "heart",
            filledSymbol: "heart.fill",
            tint: .pink,
            value: $store.dailyReviewMood
          )
          .accessibilityIdentifier("review.mood")

          Divider()
            .frame(height: 34)

          ReviewRatingPicker(
            title: String(localized: "reviews.daily.energy", defaultValue: "Energy", table: "Localizable", bundle: LorvexL10n.bundle),
            symbol: "bolt",
            filledSymbol: "bolt.fill",
            tint: .orange,
            value: $store.dailyReviewEnergy
          )
          .accessibilityIdentifier("review.energy")
        }
      }

      ReviewPromptPanel(
        title: String(localized: "reviews.daily.wins", defaultValue: "Wins", table: "Localizable", bundle: LorvexL10n.bundle),
        subtitle: String(
          localized:
            "reviews.daily.wins_prompt",
            defaultValue: "What moved forward?",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
        systemImage: "trophy.fill",
        tint: .yellow
      ) {
        markdownEditor(
          title: String(localized: "reviews.daily.wins", defaultValue: "Wins", table: "Localizable", bundle: LorvexL10n.bundle),
          draft: $store.dailyReviewWinsDraft,
          editingID: "review.wins"
        )
        .accessibilityIdentifier("review.wins")
      }

      ReviewPromptPanel(
        title: String(localized: "reviews.daily.blockers", defaultValue: "Blockers", table: "Localizable", bundle: LorvexL10n.bundle),
        subtitle: String(
          localized:
            "reviews.daily.blockers_prompt",
            defaultValue: "What should be removed or clarified?",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
        systemImage: "exclamationmark.triangle.fill",
        tint: .red
      ) {
        markdownEditor(
          title: String(localized: "reviews.daily.blockers", defaultValue: "Blockers", table: "Localizable", bundle: LorvexL10n.bundle),
          draft: $store.dailyReviewBlockersDraft,
          editingID: "review.blockers"
        )
        .accessibilityIdentifier("review.blockers")
      }

      ReviewPromptPanel(
        title: String(localized: "reviews.daily.learnings", defaultValue: "Learnings", table: "Localizable", bundle: LorvexL10n.bundle),
        subtitle: String(
          localized:
            "reviews.daily.learnings_prompt",
            defaultValue: "What should tomorrow remember?",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
        systemImage: "lightbulb.fill",
        tint: .teal
      ) {
        markdownEditor(
          title: String(localized: "reviews.daily.learnings", defaultValue: "Learnings", table: "Localizable", bundle: LorvexL10n.bundle),
          draft: $store.dailyReviewLearningsDraft,
          editingID: "review.learnings"
        )
        .accessibilityIdentifier("review.learnings")
      }

      saveFooter
    }
    .padding(LorvexDesign.Spacing.l)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Names the unusual state plainly: the editor is anchored to a past day
  /// (still inside the write window), with the way home one click away.
  private func editingBanner(_ date: String) -> some View {
    HStack(spacing: LorvexDesign.Spacing.s) {
      Image(systemName: "pencil.circle")
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.orange)
      Text(
        String(
          format: String(
            localized: "reviews.daily.editing_banner",
            defaultValue: "Editing the review for %@",
            table: "Localizable",
            bundle: LorvexL10n.bundle
          ),
          date
        )
      )
      .font(LorvexDesign.Typography.secondaryText)

      Spacer(minLength: LorvexDesign.Spacing.m)

      Button(action: onReturnToToday) {
        Text(LocalizedStringResource("reviews.daily.back_to_today", defaultValue: "Back to Today", table: "Localizable", bundle: LorvexL10n.bundle))
      }
      .buttonStyle(.link)
      .controlSize(.small)
      .accessibilityIdentifier("reviews.daily.backToToday")
    }
    .padding(.horizontal, LorvexDesign.Spacing.m)
    .padding(.vertical, LorvexDesign.Spacing.s)
    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.s))
    .accessibilityIdentifier("reviews.daily.editingBanner")
  }

  /// The explicit confirm + live persistence status. Autosave does the real
  /// work; this row makes the contract visible — what is saved, what isn't,
  /// and what's missing before anything can be.
  private var saveFooter: some View {
    HStack(spacing: LorvexDesign.Spacing.m) {
      // Keyed by state so the icon/label/color crossfade instead of snapping as
      // autosave flips saved ↔ unsaved.
      statusLabel
        .id(saveState)
        .transition(.opacity)

      Spacer(minLength: LorvexDesign.Spacing.m)

      Button(action: onSave) {
        Text(saveCtaText)
      }
      .buttonStyle(.lorvexPrimary)
      .disabled(saveState != .unsaved)
      .accessibilityIdentifier("reviews.save")
    }
    .animation(.smooth(duration: 0.2), value: saveState)
    .accessibilityIdentifier("reviews.save.footer")
  }

  @ViewBuilder
  private var statusLabel: some View {
    switch saveState {
    case .needsSummary:
      Label(String(localized: needsSummaryText), systemImage: "info.circle")
        .font(LorvexDesign.Typography.secondaryText)
        .foregroundStyle(.secondary)
    case .saved:
      Label(
        String(localized: "reviews.daily.status.saved", defaultValue: "Saved", table: "Localizable", bundle: LorvexL10n.bundle),
        systemImage: "checkmark.circle.fill"
      )
      .font(LorvexDesign.Typography.secondaryText)
      .foregroundStyle(.green)
    case .unsaved:
      Label(
        String(
          localized: "reviews.daily.status.unsaved",
          defaultValue: "Unsaved changes — saves automatically as you write",
          table: "Localizable",
          bundle: LorvexL10n.bundle
        ),
        systemImage: "clock"
      )
      .font(LorvexDesign.Typography.secondaryText)
      .foregroundStyle(.secondary)
    }
  }

  /// Save-action copy: a past-day editor must not claim to save "today's"
  /// review.
  private var saveCtaText: LocalizedStringResource {
    editingDate == nil
      ? LocalizedStringResource("reviews.daily.save_cta", defaultValue: "Save Today's Review", table: "Localizable", bundle: LorvexL10n.bundle)
      : LocalizedStringResource("reviews.daily.save_cta.dated", defaultValue: "Save Review", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  private var needsSummaryText: LocalizedStringResource {
    editingDate == nil
      ? LocalizedStringResource(
        "reviews.daily.status.needs_summary",
        defaultValue: "Write a sentence in the summary to save today's review",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
      : LocalizedStringResource(
        "reviews.daily.status.needs_summary.dated",
        defaultValue: "Write a sentence in the summary to save this review",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
  }

  private func markdownEditor(
    title: String,
    draft: Binding<String>,
    editingID: String
  ) -> some View {
    LorvexPlainTextEditor(
      text: draft,
      placeholder: title,
      minHeight: 88,
      fontSize: 14,
      onFocusChange: onEditorFocusChange
    )
      .accessibilityLabel(title)
      .accessibilityIdentifier(editingID)
  }
}

private struct ReviewPromptPanel<Content: View>: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let tint: Color
  @ViewBuilder let content: Content

  var body: some View {
    HStack(alignment: .top, spacing: LorvexDesign.Spacing.m) {
      // A colored accent rail keys each prompt to its theme (wins, blockers,
      // learnings) and echoes the task inspector's section rails for cohesion.
      Capsule()
        .fill(tint.opacity(0.7))
        .frame(width: 3)

      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
        HStack(spacing: LorvexDesign.Spacing.s) {
          Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .font(LorvexDesign.Typography.secondaryText)
          VStack(alignment: .leading, spacing: 1) {
            Text(title)
              .font(LorvexDesign.Typography.primaryEmphasis)
            Text(subtitle)
              .font(LorvexDesign.Typography.tertiaryText)
              .foregroundStyle(.secondary)
          }
        }

        content
      }
    }
    .padding(LorvexDesign.Spacing.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.06), in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
    .overlay {
      RoundedRectangle(cornerRadius: LorvexDesign.Radius.m)
        .stroke(.separator.opacity(0.10), lineWidth: 0.5)
    }
  }
}
