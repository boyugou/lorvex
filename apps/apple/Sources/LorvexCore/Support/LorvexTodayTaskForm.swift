#if os(iOS) || os(macOS)
  import SwiftUI

  /// One literal task title, planned for the user's Today. The welcome sheet
  /// also offers the existing-plan and skip paths below the local action.
  public struct LorvexTodayTaskForm: View {
    public struct Welcome {
      let context: String
      let sync: () -> Void
      let skip: () -> Void

      public init(context: String, sync: @escaping () -> Void, skip: @escaping () -> Void) {
        self.context = context
        self.sync = sync
        self.skip = skip
      }
    }

    private let welcome: Welcome?
    private let create: (String) async throws -> Void
    @State private var title = ""
    @State private var saving = false
    @State private var errorMessage: String?

    public init(welcome: Welcome? = nil, create: @escaping (String) async throws -> Void) {
      self.welcome = welcome
      self.create = create
    }

    public var body: some View {
      VStack(alignment: .leading, spacing: LorvexDesign.Spacing.l) {
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.xs) {
          if let welcome {
            HStack {
              LorvexPageLabel(welcome.context)
              Spacer()
              skipButton(welcome)
            }
          }
          Text(String(localized: "setup.first_task.question", defaultValue: "What would you like to do today?", bundle: CoreL10n.bundle), serifVoice: .pageSentence)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        }
        VStack(alignment: .leading, spacing: LorvexDesign.Spacing.s) {
          TextField(String(localized: "capture.title.a11y", defaultValue: "Task title", bundle: CoreL10n.bundle), text: $title)
            .textFieldStyle(.plain)
            .font(LorvexDesign.Typography.primaryText)
            .padding(LorvexDesign.Spacing.m)
            .background(LorvexDesign.Palette.insetFill, in: RoundedRectangle(cornerRadius: LorvexDesign.Radius.m))
            .submitLabel(.done)
            .onSubmit(save)
            .accessibilityIdentifier("today.firstTask.title")
          if let errorMessage {
            Text(errorMessage)
              .font(LorvexDesign.Typography.secondaryText)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("today.firstTask.error")
          }
          Button(action: save) {
            Label(String(localized: "setup.first_task.add", defaultValue: "Add to Today", bundle: CoreL10n.bundle), systemImage: "plus")
              .frame(maxWidth: .infinity)
          }
          .controlSize(.large)
          .buttonStyle(.borderedProminent)
          .disabled(title.trimmedNilIfEmpty == nil)
          .accessibilityIdentifier("today.firstTask.add")
        }
        if let welcome {
          Divider()
          Button(action: welcome.sync) {
            Label(String(localized: "setup.sync.title", defaultValue: "Sync with iCloud", bundle: CoreL10n.bundle), systemImage: "icloud")
              .frame(minHeight: 44)
              .contentShape(Rectangle())
          }
          .buttonStyle(.borderless)
          .accessibilityIdentifier("setup.firstTask.sync")
        }
      }
      .disabled(saving)
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func skipButton(_ welcome: Welcome) -> some View {
      Button(action: welcome.skip) {
        Text(String(localized: "setup.skip", defaultValue: "Skip", bundle: CoreL10n.bundle))
          .frame(minHeight: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
      .accessibilityIdentifier("setup.firstTask.skip")
    }

    private func save() {
      guard !saving, let submitted = title.trimmedNilIfEmpty else { return }
      saving = true
      errorMessage = nil
      Task {
        defer { saving = false }
        do {
          try await create(submitted)
          title = ""
        } catch {
          errorMessage = UserFacingError.message(for: UserFacingError.classify(error), copy: .standard)
        }
      }
    }
  }
#endif
