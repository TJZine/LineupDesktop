import Cocoa
import FlutterMacOS

/// Window-owned services registered against its explicit engine messenger.
/// The handler captures the serialized reader/queue, never this owner or window.
final class AppChannels {
  private let appMenuChannel: FlutterMethodChannel
  private let platformChannel: FlutterMethodChannel
  private let licenseQueue = DispatchQueue(label: "lineup.licenses", qos: .userInitiated)
  private let licenseResources = LicenseResources(bundle: Bundle.main.bundleURL)

  init(messenger: FlutterBinaryMessenger) {
    appMenuChannel = FlutterMethodChannel(name: "lineup/app_menu", binaryMessenger: messenger)
    platformChannel = FlutterMethodChannel(name: "lineup/platform", binaryMessenger: messenger)
    platformChannel.setMethodCallHandler { [licenseResources, licenseQueue] call, result in
      switch call.method {
      case "openPlexLink":
        // Only this fixed URL is ever opened; Dart supplies none.
        result(NSWorkspace.shared.open(URL(string: "https://plex.tv/link")!))
      case "listLicenseDocuments", "readLicenseDocument":
        let method = call.method
        let id = (call.arguments as? [String: Any])?["id"] as? String
        licenseQueue.async {
          do {
            let value: Any
            if method == "listLicenseDocuments" { value = try licenseResources.list() }
            else { value = try licenseResources.read(id: id) }
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
  }

  deinit {
    platformChannel.setMethodCallHandler(nil)
  }

  func openSettings() {
    appMenuChannel.invokeMethod("openSettings", arguments: nil)
  }
}
