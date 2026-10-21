import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var appMenuChannel: FlutterMethodChannel?
  private var platformChannel: FlutterMethodChannel?
  private let licenseQueue = DispatchQueue(label: "lineup.licenses", qos: .userInitiated)
  private lazy var licenseResources = LicenseResources(bundle: Bundle.main.bundleURL)

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Flutter first asks Dart through System.requestAppExit and can cancel.
    // Only its approved reinvocation may stop native playback.
    let approval = super.applicationShouldTerminate(sender)
    guard let window = mainFlutterWindow as? MainFlutterWindow else { return approval }
    return window.applicationShouldTerminate(after: approval) { accepted in
      sender.reply(toApplicationShouldTerminate: accepted)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    configureChannels()
  }

  /// Wired from the app menu's Settings… item (Command-comma).
  @IBAction func openSettings(_ sender: Any?) {
    configureChannels()
    appMenuChannel?.invokeMethod("openSettings", arguments: nil)
  }

  private func configureChannels() {
    guard appMenuChannel == nil,
      let controller = findFlutterViewController()
    else { return }
    let messenger = controller.engine.binaryMessenger
    appMenuChannel = FlutterMethodChannel(name: "lineup/app_menu", binaryMessenger: messenger)
    let platform = FlutterMethodChannel(name: "lineup/platform", binaryMessenger: messenger)
    platform.setMethodCallHandler { [self] call, result in
      switch call.method {
      case "openPlexLink":
        // Only this fixed URL is ever opened; Dart supplies none.
        result(NSWorkspace.shared.open(URL(string: "https://plex.tv/link")!))
      case "listLicenseDocuments", "readLicenseDocument":
        let resources = licenseResources
        let method = call.method
        let id = (call.arguments as? [String: Any])?["id"] as? String
        licenseQueue.async {
          do {
            let value: Any
            if method == "listLicenseDocuments" { value = try resources.list() }
            else {
              value = try resources.read(id: id)
            }
            DispatchQueue.main.async { result(value) }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: "license_resources_unavailable",
                message: "License resources could not be loaded.", details: nil))
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    platformChannel = platform
  }

  /// The main window may host the FlutterViewController directly or inside a
  /// container view controller.
  private func findFlutterViewController() -> FlutterViewController? {
    var windows: [NSWindow] = []
    if let main = mainFlutterWindow { windows.append(main) }
    windows.append(contentsOf: NSApp.windows)
    for window in windows {
      if let found = Self.flutterViewController(in: window.contentViewController) {
        return found
      }
    }
    return nil
  }

  private static func flutterViewController(in controller: NSViewController?)
    -> FlutterViewController?
  {
    guard let controller else { return nil }
    if let flutter = controller as? FlutterViewController { return flutter }
    for child in controller.children {
      if let found = flutterViewController(in: child) { return found }
    }
    return nil
  }
}
