#if DEBUG
  import AppKit
  import ApplicationServices

  /// Dev/QA only: when `-uiPreviewDumpAX` is passed to a `--ui-preview` tour,
  /// every stop prints the accessibility tree of the app's windows between
  /// `AXDUMP STOP <name>` and `AXDUMP END <name>`. Each window starts with an
  /// `AXDUMP WINDOW` line; one `AXDUMP E` line per element follows, carrying its
  /// nesting depth, its frame in points from the window's top-left corner, role,
  /// subrole, selected and disabled flags, label (`AXDescription`), title,
  /// value, value description (`valueDesc`, the spoken form of a value),
  /// help text, identifier, placeholder, the name of the element that titles
  /// it (`titleUI`), and its actions. `AXDUMP SUMMARY` closes a window
  /// with the number of elements and of interactive ones that VoiceOver would
  /// read without a name. The tour script copies the lines into its log.
  ///
  /// The walk is an accessibility client of the app's own process, the same
  /// view VoiceOver and Accessibility Inspector get, and having a client
  /// attached makes SwiftUI build its whole tree. macOS grants that to a
  /// process only when its responsible application is trusted for
  /// Accessibility, which a terminal that was granted it passes on to the tour;
  /// otherwise the dump prints one `AXDUMP SKIPPED` line. A client inside the
  /// process is served by the thread that calls it, and SwiftUI builds its tree
  /// for the first query on that thread, so the walk runs on the main thread,
  /// where the app's own views expect to be evaluated.
  @MainActor
  enum MacAccessibilityDump {
    static var isRequested: Bool {
      CommandLine.arguments.contains("-uiPreviewDumpAX")
    }

    static func dump(stop: String) {
      guard isRequested else { return }
      let lines = MacAccessibilityTree.lines(process: ProcessInfo.processInfo.processIdentifier)
      print("AXDUMP STOP \(stop)")
      for line in lines { print("AXDUMP \(line)") }
      print("AXDUMP END \(stop)")
      fflush(stdout)
    }
  }

  /// The accessibility tree of one process, read through the `AXUIElement` API.
  enum MacAccessibilityTree {
    /// The roles whose elements a person acts on, and so must carry a name.
    /// For these the value is state or typed content, never the name.
    private static let interactiveRoles: Set<String> = [
      "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
      "AXTextField", "AXTextArea", "AXComboBox", "AXSlider", "AXIncrementor",
      "AXDisclosureTriangle", "AXLink", "AXSegmentedControl", "AXDateField", "AXColorWell",
    ]

    private static let maxDepth = 40
    private static let maxChildren = 250

    private static let attributeNames: [String] = [
      kAXRoleAttribute, kAXSubroleAttribute, kAXDescriptionAttribute, kAXTitleAttribute,
      kAXValueAttribute, kAXValueDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute,
      kAXPositionAttribute, kAXSizeAttribute, kAXEnabledAttribute, kAXSelectedAttribute,
      kAXChildrenAttribute, kAXTitleUIElementAttribute, kAXPlaceholderValueAttribute,
    ]

    private struct Counts {
      var elements = 0
      var unnamed = 0
    }

    /// The dump lines for every window of `process`, or one `SKIPPED` line when
    /// the process may not read accessibility trees.
    static func lines(process: pid_t) -> [String] {
      guard AXIsProcessTrusted() else {
        return ["SKIPPED the process is not trusted for Accessibility"]
      }
      let application = AXUIElementCreateApplication(process)
      AXUIElementSetMessagingTimeout(application, 3)
      var windows: CFTypeRef?
      let status = AXUIElementCopyAttributeValue(
        application, kAXWindowsAttribute as CFString, &windows)
      guard status == .success, let windows = windows as? [AXUIElement] else {
        return ["SKIPPED the window list could not be read (\(status.rawValue))"]
      }
      var lines: [String] = []
      for window in windows {
        let values = read(window)
        let origin = point(values[kAXPositionAttribute]) ?? .zero
        let size = point(values[kAXSizeAttribute]) ?? .zero
        let title = text(values[kAXTitleAttribute])
        lines.append("WINDOW title='\(title)' size=\(Int(size.x))x\(Int(size.y))")
        var counts = Counts()
        visit(window, depth: 0, origin: origin, counts: &counts, into: &lines)
        lines.append("SUMMARY elements=\(counts.elements) unnamed=\(counts.unnamed)")
      }
      return lines
    }

    private static func visit(
      _ element: AXUIElement, depth: Int, origin: CGPoint, counts: inout Counts,
      into lines: inout [String]
    ) {
      let values = read(element)
      lines.append(
        describe(values, actions: actions(of: element), depth: depth, origin: origin, counts: &counts))
      guard depth < maxDepth, let children = values[kAXChildrenAttribute] as? [AXUIElement] else {
        return
      }
      for child in children.prefix(maxChildren) {
        visit(child, depth: depth + 1, origin: origin, counts: &counts, into: &lines)
      }
    }

    /// The attributes of `element` by name; an attribute the element lacks is
    /// absent from the result.
    private static func read(_ element: AXUIElement) -> [String: CFTypeRef] {
      AXUIElementSetMessagingTimeout(element, 3)
      var raw: CFArray?
      let status = AXUIElementCopyMultipleAttributeValues(
        element, attributeNames as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw)
      guard status == .success, let raw = raw as? [CFTypeRef] else { return [:] }
      var values: [String: CFTypeRef] = [:]
      for (name, value) in zip(attributeNames, raw) where !isMissing(value) {
        values[name] = value
      }
      return values
    }

    /// Whether `value` is the placeholder a multi-attribute read returns for an
    /// attribute the element does not have.
    private static func isMissing(_ value: CFTypeRef) -> Bool {
      guard CFGetTypeID(value) == AXValueGetTypeID() else { return false }
      return AXValueGetType(unsafeDowncast(value, to: AXValue.self)) == .axError
    }

    /// The names of the actions `element` offers, standard ones without their
    /// `AX` prefix and custom ones as `custom:<name>`.
    private static func actions(of element: AXUIElement) -> String {
      var names: CFArray?
      guard AXUIElementCopyActionNames(element, &names) == .success,
        let names = names as? [String]
      else { return "" }
      return names.map { name in
        guard name.hasPrefix("Name:") else { return name.replacingOccurrences(of: "AX", with: "", options: .anchored) }
        let custom = name.dropFirst("Name:".count).prefix { $0 != "\n" }
        return "custom:\(custom)"
      }.joined(separator: "|")
    }

    private static func describe(
      _ values: [String: CFTypeRef], actions: String, depth: Int, origin: CGPoint,
      counts: inout Counts
    ) -> String {
      let role = text(values[kAXRoleAttribute])
      let subrole = text(values[kAXSubroleAttribute])
      let label = text(values[kAXDescriptionAttribute])
      let title = text(values[kAXTitleAttribute])
      let value = text(values[kAXValueAttribute])
      let placeholder = text(values[kAXPlaceholderValueAttribute])
      let titleElement = elementName(values[kAXTitleUIElementAttribute])
      let position = point(values[kAXPositionAttribute]) ?? .zero
      let size = point(values[kAXSizeAttribute]) ?? .zero
      counts.elements += 1
      if interactiveRoles.contains(role), label.isEmpty, title.isEmpty, placeholder.isEmpty,
        titleElement.isEmpty
      {
        counts.unnamed += 1
      }
      var kind = "role=\(role)"
      if !subrole.isEmpty { kind += "/\(subrole)" }
      if flag(values[kAXSelectedAttribute]) == true { kind += " selected" }
      if flag(values[kAXEnabledAttribute]) == false { kind += " disabled" }
      let frame =
        "[\(Int(position.x - origin.x)),\(Int(position.y - origin.y)) \(Int(size.x))x\(Int(size.y))]"
      let names =
        "label='\(label)' title='\(title)' value='\(value)' "
        + "valueDesc='\(text(values[kAXValueDescriptionAttribute]))' "
        + "help='\(text(values[kAXHelpAttribute]))' id='\(text(values[kAXIdentifierAttribute]))' "
        + "placeholder='\(placeholder)' titleUI='\(titleElement)' actions='\(actions)'"
      return "E \(depth) \(frame) \(kind) \(names)"
    }

    /// The spoken name of the element an element is titled by: its label, title,
    /// or text value, or an empty string when there is none.
    private static func elementName(_ value: CFTypeRef?) -> String {
      guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return "" }
      let element = unsafeDowncast(value, to: AXUIElement.self)
      let names = [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute]
      for name in names {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success else {
          continue
        }
        let found = text(raw)
        if !found.isEmpty { return found }
      }
      return ""
    }

    private static func text(_ value: CFTypeRef?) -> String {
      guard let value else { return "" }
      let type = CFGetTypeID(value)
      var result = ""
      if type == CFStringGetTypeID() {
        result = (value as? String) ?? ""
      } else if type == CFNumberGetTypeID() || type == CFBooleanGetTypeID() {
        result = String(describing: value)
      }
      return result.replacingOccurrences(of: "\n", with: "⏎")
    }

    private static func flag(_ value: CFTypeRef?) -> Bool? {
      guard let value, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
      return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
    }

    /// A point or a size read from an `AXValue`, as a point (a size's width and
    /// height in `x` and `y`).
    private static func point(_ value: CFTypeRef?) -> CGPoint? {
      guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
      let axValue = unsafeDowncast(value, to: AXValue.self)
      var result = CGPoint.zero
      switch AXValueGetType(axValue) {
      case .cgPoint:
        guard AXValueGetValue(axValue, .cgPoint, &result) else { return nil }
        return result
      case .cgSize:
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return CGPoint(x: size.width, y: size.height)
      default:
        return nil
      }
    }
  }
#endif
