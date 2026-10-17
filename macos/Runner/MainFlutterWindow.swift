import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var nativePlayer: LineupNativePlayer?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Both must be clear for the FlutterView to composite over the video.
    flutterViewController.backgroundColor = .clear
    isOpaque = false
    backgroundColor = .clear

    let windowFrame = self.frame
    let container = PlayerContainerViewController(
      flutterViewController: flutterViewController,
      contentSize: contentRect(forFrameRect: windowFrame).size)
    self.contentViewController = container
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    nativePlayer = LineupNativePlayer(
      messenger: flutterViewController.engine.binaryMessenger,
      videoHost: container.videoHost,
      window: self)

    super.awakeFromNib()
  }
}

/// Hosts the video presentation view below the transparent FlutterView.
/// Both fill the window's content area, so Flutter's logical top-left
/// coordinates are the video host's flipped coordinates.
final class PlayerContainerViewController: NSViewController {
  let flutterViewController: FlutterViewController
  let videoHost = PassiveVideoHostView()
  private let contentSize: NSSize

  init(flutterViewController: FlutterViewController, contentSize: NSSize) {
    self.flutterViewController = flutterViewController
    self.contentSize = contentSize
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("PlayerContainerViewController is created in code.")
  }

  override func loadView() {
    // Start at the window's content size. Assigning this controller as the
    // window's contentViewController sizes the window to this view, so a
    // zero-sized view would shrink the window and the restored frame.
    let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
    container.autoresizesSubviews = true

    videoHost.frame = container.bounds
    videoHost.autoresizingMask = [.width, .height]
    container.addSubview(videoHost)

    addChild(flutterViewController)
    let flutterView = flutterViewController.view
    flutterView.frame = container.bounds
    flutterView.autoresizingMask = [.width, .height]
    container.addSubview(flutterView, positioned: .above, relativeTo: videoHost)

    view = container
  }
}

/// The flipped, passive host for the native video view. It is black so that
/// regions without video never show the desktop through the clear window.
final class PassiveVideoHostView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
  }

  required init?(coder: NSCoder) {
    fatalError("PassiveVideoHostView is created in code.")
  }

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override var acceptsFirstResponder: Bool { false }
  override func isAccessibilityElement() -> Bool { false }
  override func accessibilityChildren() -> [Any]? { [] }
}
