import Foundation
import LorvexCore
import SwiftUI

private enum MobileReviewMode: String, CaseIterable, Identifiable {
  case daily
  case weekly

  var id: String { rawValue }

  var title: String {
    switch self {
    case .daily:
      String(
        localized: "review.mode.daily", defaultValue: "Day", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .weekly:
      String(
        localized: "review.mode.weekly", defaultValue: "Week", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }
}

public struct MobileStoreReviewView: View {
  @Bindable private var store: MobileStore
  @State private var mode: MobileReviewMode = .daily
  @FocusState private var focusedField: ReviewField?

  public init(store: MobileStore) {
    self.store = store
  }

  private enum ReviewField {
    case summary
    case wins
    case blockers
    case learnings
  }

  public var body: some View {
    List {
      Picker(
        String(
          localized: "review.mode.picker", defaultValue: "Review Mode", table: "Localizable",
          bundle: MobileL10n.bundle), selection: $mode
      ) {
        ForEach(MobileReviewMode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("review.mode.picker")

      switch mode {
      case .daily:
        dailyReviewSection
        MobileReviewDayEvidenceSection(summary: store.dayReviewEvidence)
      case .weekly:
        if let review = store.snapshot.weeklyReview {
          MobileWeeklyReviewSection(review: review)
        } else {
          weeklyEmptySection
        }
        MobileReviewDigestSection(reviews: store.weekReviewDigest) { date in
          Task {
            await store.selectReviewDay(date)
            mode = .daily
          }
        }
      }
    }
    .task {
      await store.loadDailyReviewDraft()
      await store.loadWeekReviewDigest(weekOf: store.weeklyReviewAnchor)
    }
    .task(id: mode) {
      if mode == .weekly {
        await store.loadWeekReviewDigest(weekOf: store.weeklyReviewAnchor)
      }
    }
    .refreshable { await store.refreshResettingCloudSyncPacing() }
    // `scrollDismissesKeyboard` is unavailable on visionOS.
    #if !os(visionOS)
      .scrollDismissesKeyboard(.interactively)
    #endif
    .toolbar {
      if let review = store.dailyReview {
        ToolbarItem(placement: .automatic) {
          ShareLink(item: LorvexDailyReviewMarkdownExport.render(review)) {
            Label(
              String(
                localized: "review.share_daily", defaultValue: "Share Daily", table: "Localizable",
                bundle: MobileL10n.bundle),
              systemImage: "square.and.arrow.up"
            )
          }
          .accessibilityLabel(
            String(
              localized: "review.share_daily.a11y", defaultValue: "Share daily review",
              table: "Localizable", bundle: MobileL10n.bundle)
          )
          .lorvexToolbarHoverEffect()
          .accessibilityIdentifier("review.toolbar.shareDaily")
        }
      }
      if let review = store.snapshot.weeklyReview {
        ToolbarItem(placement: .automatic) {
          ShareLink(item: LorvexWeeklyReviewMarkdownExport.render(review)) {
            Label(
              String(
                localized: "review.share_weekly", defaultValue: "Share Weekly",
                table: "Localizable", bundle: MobileL10n.bundle),
              systemImage: "calendar.badge.clock"
            )
          }
          .accessibilityLabel(
            String(
              localized: "review.share_weekly.a11y", defaultValue: "Share weekly review",
              table: "Localizable", bundle: MobileL10n.bundle)
          )
          .lorvexToolbarHoverEffect()
          .accessibilityIdentifier("review.toolbar.shareWeekly")
        }
      }
    }
  }

  private var dailyReviewSection: some View {
    Section {
      if store.isLoadingDailyReviewDraft {
        MobileSkeletonRows(count: 5)
        .accessibilityIdentifier("mobileReview.loadingDaily")
      } else {
        dailyReviewFields
      }
    } header: {
      HStack {
        Text(
          String(
            localized: "review.section.daily", defaultValue: "Daily Review", table: "Localizable",
            bundle: MobileL10n.bundle))
        Spacer()
        Text(store.selectedReviewDate)
          .font(LorvexDesign.Typography.tertiaryText)
          .foregroundStyle(.secondary)
      }
    } footer: {
      if !store.selectedReviewDayIsEditable {
        Text(
          String(
            localized: "review.daily.read_only.footer",
            defaultValue: "Past daily reviews are read-only on mobile. Return to today to write.",
            table: "Localizable", bundle: MobileL10n.bundle))
      }
    }
  }

  @ViewBuilder
  private var dailyReviewFields: some View {
    if !store.selectedReviewDayIsEditable {
      Button {
        Task { await store.returnReviewToToday() }
      } label: {
        Label(
          String(
            localized: "review.daily.return_today", defaultValue: "Return to Today",
            table: "Localizable", bundle: MobileL10n.bundle), systemImage: "calendar")
      }
      .accessibilityIdentifier("review.day.returnToday")
    }

    labeledField(
      String(
        localized: "review.field.summary", defaultValue: "Summary", table: "Localizable",
        bundle: MobileL10n.bundle),
      text: $store.dailyReviewDraft.summary,
      lineLimit: 3...6,
      field: .summary,
      submit: .next,
      identifier: "review.daily.summary"
    ) { focusedField = .wins }

    MobileReviewRatingPicker(
      title: String(
        localized: "review.field.mood", defaultValue: "Mood", table: "Localizable",
        bundle: MobileL10n.bundle),
      symbol: "heart",
      filledSymbol: "heart.fill",
      tint: .pink,
      identifierPrefix: "review.daily.mood",
      value: $store.dailyReviewDraft.mood,
      isEnabled: store.selectedReviewDayIsEditable,
      canClear: store.dailyReview?.mood == nil
    )

    MobileReviewRatingPicker(
      title: String(
        localized: "review.field.energy", defaultValue: "Energy", table: "Localizable",
        bundle: MobileL10n.bundle),
      symbol: "bolt",
      filledSymbol: "bolt.fill",
      tint: .orange,
      identifierPrefix: "review.daily.energy",
      value: $store.dailyReviewDraft.energy,
      isEnabled: store.selectedReviewDayIsEditable,
      canClear: store.dailyReview?.energyLevel == nil
    )

    labeledField(
      String(
        localized: "review.field.wins", defaultValue: "Wins", table: "Localizable",
        bundle: MobileL10n.bundle),
      text: $store.dailyReviewDraft.wins,
      lineLimit: 1...4,
      field: .wins,
      submit: .next,
      identifier: "review.daily.wins"
    ) { focusedField = .blockers }
    labeledField(
      String(
        localized: "review.field.blockers", defaultValue: "Blockers", table: "Localizable",
        bundle: MobileL10n.bundle),
      text: $store.dailyReviewDraft.blockers,
      lineLimit: 1...4,
      field: .blockers,
      submit: .next,
      identifier: "review.daily.blockers"
    ) { focusedField = .learnings }
    labeledField(
      String(
        localized: "review.field.learnings", defaultValue: "Learnings", table: "Localizable",
        bundle: MobileL10n.bundle),
      text: $store.dailyReviewDraft.learnings,
      lineLimit: 1...4,
      field: .learnings,
      submit: .done,
      identifier: "review.daily.learnings"
    ) { Task { await store.saveDailyReviewDraft() } }

    Button {
      Task { await store.saveDailyReviewDraft() }
    } label: {
      if store.isSavingReview {
        Label {
          Text(
            String(
              localized: "review.saving_daily", defaultValue: "Saving Daily Review",
              table: "Localizable", bundle: MobileL10n.bundle))
        } icon: {
          ProgressView()
        }
      } else {
        Label(
          String(
            localized: "review.save_daily", defaultValue: "Save Daily Review", table: "Localizable",
            bundle: MobileL10n.bundle), systemImage: "square.and.arrow.down")
      }
    }
    .disabled(
      !store.selectedReviewDayIsEditable || !store.dailyReviewDraft.canSave
        || store.isSavingReview || store.isLoadingDailyReviewDraft
    )
    .accessibilityIdentifier("review.daily.save")
  }

  /// A free-text review field with a persistent caption label above it, so each
  /// field stays identifiable once filled (a bare placeholder vanishes on input).
  /// Keeps the field's own focus / submit-chain wiring intact.
  private func labeledField(
    _ label: String,
    text: Binding<String>,
    lineLimit: ClosedRange<Int>,
    field: ReviewField,
    submit: SubmitLabel,
    identifier: String,
    onSubmit: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label)
        .font(LorvexDesign.Typography.tertiaryText)
        .foregroundStyle(.secondary)
      TextField("", text: text, axis: .vertical)
        .lineLimit(lineLimit)
        .focused($focusedField, equals: field)
        .submitLabel(submit)
        .onSubmit(onSubmit)
        .disabled(!store.selectedReviewDayIsEditable)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
  }

  private var weeklyEmptySection: some View {
    Section {
      // Bounded inline empty-state (matches the rest of the app); a
      // ContentUnavailableView in a List Section inflates the row height.
      MobileEmptyState(
        icon: "chart.line.uptrend.xyaxis",
        tint: .indigo,
        title: String(
          localized: "review.empty.not_loaded", defaultValue: "No Review Loaded",
          table: "Localizable", bundle: MobileL10n.bundle),
        message: String(
          localized: "review.empty.not_loaded.message",
          defaultValue:
            "Weekly patterns appear after Lorvex has enough recent task activity to summarize.",
          table: "Localizable", bundle: MobileL10n.bundle)
      )
    }
  }
}
