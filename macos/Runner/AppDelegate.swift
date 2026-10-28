import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
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

  /// Wired from the app menu's Settings… item (Command-comma).
  @IBAction func openSettings(_ sender: Any?) {
    (mainFlutterWindow as? MainFlutterWindow)?.openSettings()
  }
}
