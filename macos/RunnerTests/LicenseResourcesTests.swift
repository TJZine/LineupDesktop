import Foundation
import Darwin

@main
struct LicenseResourcesTests {
  static func tryCount(_ reader: LicenseResources) -> Int { (try? reader.list().count) ?? -1 }
  static func main() throws {
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let root = temporary.appendingPathComponent("resources")
    func write(_ path: String, _ bytes: Data = Data("License\n\nCopyright © test\n".utf8)) throws {
      let target = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: target)
    }
    try write("BUILD-INFO.txt")
    try write("licenses/NOTICES-SUMMARY.txt")
    try write("licenses/mpv/LICENSE.LGPL")
    try write("licenses/new component/nested/notice.txt")
    try write("patches/mpv/change.patch")
    let reader = LicenseResources(root: root)
    let entries = try reader.list()
    precondition(entries.count == 5)
    let extra = entries.first { $0["path"] as? String == "licenses/new component/nested/notice.txt" }!
    let content = try reader.read(id: extra["id"] as! String)
    precondition(content == "License\n\nCopyright © test\n")
    func rejects(_ body: () throws -> Void) {
      do { try body(); fatalError("Unsafe resource accepted") }
      catch { precondition(error is LicenseResources.Failure) }
    }
    for id in ["../BUILD-INFO.txt", "/etc/passwd", "licenses/mpv/LICENSE.LGPL", "native-999999"] {
      rejects { _ = try reader.read(id: id) }
    }
    let extraPath = root.appendingPathComponent("licenses/new component/nested/notice.txt")
    try FileManager.default.removeItem(at: extraPath)
    try FileManager.default.createSymbolicLink(at: extraPath, withDestinationURL: temporary)
    rejects { _ = try reader.read(id: extra["id"] as! String) }
    rejects { _ = try reader.list() }
    try FileManager.default.removeItem(at: extraPath)
    try write("licenses/new component/nested/notice.txt", Data([0xff, 0xfe]))
    rejects { _ = try reader.list() }
    try write("licenses/new component/nested/notice.txt", Data(repeating: 65, count: 2 * 1024 * 1024 + 1))
    rejects { _ = try reader.list() }
    try write("licenses/new component/nested/notice.txt", Data())
    rejects { _ = try reader.list() }
    try FileManager.default.removeItem(at: extraPath)
    precondition(mkfifo(extraPath.path, 0o600) == 0)
    rejects { _ = try reader.list() }
    try FileManager.default.removeItem(at: extraPath)
    try write("licenses/new component/nested/notice.txt")
    let link = temporary.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
    rejects { _ = try LicenseResources(root: link).list() }
    let bundle = temporary.appendingPathComponent("Fixture.app")
    let contents = bundle.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let outside = temporary.appendingPathComponent("outside-resources")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: root, to: outside.appendingPathComponent("LineupNativeRuntime"))
    try FileManager.default.createSymbolicLink(at: contents.appendingPathComponent("Resources"), withDestinationURL: outside)
    rejects { _ = try LicenseResources(bundle: bundle).list() }
    try FileManager.default.removeItem(at: contents.appendingPathComponent("Resources"))
    try FileManager.default.copyItem(at: outside, to: contents.appendingPathComponent("Resources"))
    let bundled = LicenseResources(bundle: bundle)
    precondition(tryCount(bundled) == 5)
    try FileManager.default.removeItem(at: root.appendingPathComponent("licenses/NOTICES-SUMMARY.txt"))
    rejects { _ = try reader.list() }
    rejects { _ = try LicenseResources(root: temporary.appendingPathComponent("absent")).list() }
    if CommandLine.arguments.count == 2 {
      let realRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
      let real = LicenseResources(root: realRoot)
      let documents = try real.list()
      precondition(documents.count >= 53)
      for document in documents {
        let text = try real.read(id: document["id"] as! String)
        let expected = try String(contentsOf: realRoot.appendingPathComponent(document["path"] as! String), encoding: .utf8)
        precondition(text == expected)
      }
      print("PASS: \(documents.count) actual prepared-runtime documents, exact text")
    }
    print("PASS: resource containment, opaque IDs, nested files, UTF-8, bounds, special files, missing inputs")
  }
}
