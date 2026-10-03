#if DEBUG && os(iOS)
  import UIKit

  /// Dev/QA only: when `-lorvexPreviewOrientation landscape` is passed, the
  /// window scene asks to be laid out in landscape at launch, so the headless
  /// capture script (`script/ios_sim_screenshots.sh`) can screenshot iPhone and
  /// iPad layouts in landscape without Simulator.app's rotate command.
  @MainActor
  enum DebugLaunchOrientation {
    static func applyIfRequested() {
      let args = CommandLine.arguments
      guard let index = args.firstIndex(of: "-lorvexPreviewOrientation"), index + 1 < args.count,
        args[index + 1] == "landscape",
        let scene = UIApplication.shared.connectedScenes.lazy.compactMap({ $0 as? UIWindowScene }).first
      else { return }
      scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
    }
  }
#endif
