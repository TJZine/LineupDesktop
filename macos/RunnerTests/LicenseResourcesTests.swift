import Foundation
import Darwin

@main
struct LicenseResourcesTests {
  // Capture the real stderr descriptor used by the native diagnostic sink.
  static func captureStderr(_ body: () throws -> Void) rethrows -> String {
    let file = tmpfile()!
    let saved = dup(STDERR_FILENO)
    precondition(saved >= 0)
    fflush(stderr)
    precondition(dup2(fileno(file), STDERR_FILENO) >= 0)
    defer {
      fflush(stderr)
      _ = dup2(saved, STDERR_FILENO)
      close(saved)
      fclose(file)
    }
    try body()
    fflush(stderr)
    _ = lseek(fileno(file), 0, SEEK_SET)
    let data = FileHandle(fileDescriptor: fileno(file), closeOnDealloc: false).readDataToEndOfFile()
    return String(data: data, encoding: .utf8)!
  }

  static func withDiagnostics(_ value: String?, _ body: () throws -> String) rethrows -> String {
    let previous = getenv("LINEUP_LICENSE_DIAGNOSTICS").map { String(cString: $0) }
    if let value { setenv("LINEUP_LICENSE_DIAGNOSTICS", value, 1) }
    else { unsetenv("LINEUP_LICENSE_DIAGNOSTICS") }
    defer {
      if let previous { setenv("LINEUP_LICENSE_DIAGNOSTICS", previous, 1) }
      else { unsetenv("LINEUP_LICENSE_DIAGNOSTICS") }
    }
    return try body()
  }

  static func safeOutput(_ output: String) -> Bool {
    let stages: Set<String> = [
      "root_open", "bundle_child_open", "tree_open", "traversal_duplicate",
      "traversal_open", "traversal_read", "entry_name", "entry_stat",
      "entry_directory_open", "entry_kind", "file_size", "entry_count", "file_path",
      "file_duplicate", "file_open", "file_stat", "file_read", "file_encoding",
      "tree_bounds", "required_index", "document_id", "depth_bounds",
    ]
    let categories: Set<String> = ["system", "invalid", "bounds", "missing", "encoding"]
    for line in output.split(separator: "\n") {
      let fields = line.split(separator: " ").map(String.init)
      guard fields.count == 4 || fields.count == 5,
        fields[0] == "[lineup-license-native]",
        fields[1] == "operation=list" || fields[1] == "operation=read",
        fields[2].hasPrefix("stage="), stages.contains(String(fields[2].dropFirst(6))),
        fields[3].hasPrefix("category="), categories.contains(String(fields[3].dropFirst(9))) else { return false }
      if fields.count == 5 {
        guard fields[4].hasPrefix("errno="),
          let code = Int(fields[4].dropFirst(6)), code > 0, code <= 4095 else { return false }
      }
    }
    return true
  }

  static func probeContract(_ root: URL, _ absent: URL) throws {
    for value in [nil, "1-SENTINEL", "1"] as [String?] {
      let output = withDiagnostics(value) {
        captureStderr {
          do { _ = try LicenseResources(root: absent).list(); preconditionFailure("Missing tree accepted") }
          catch { precondition(error is LicenseResources.Failure) }
        }
      }
      if value == "1" {
        precondition(output == "[lineup-license-native] operation=list stage=root_open category=system errno=2\n")
      } else { precondition(output.isEmpty) }
    }
    let success = try withDiagnostics("1") {
      try captureStderr {
        let reader = LicenseResources(root: root)
        let documents = try reader.list()
        _ = try reader.read(id: documents.first!["id"] as? String)
      }
    }
    precondition(success.isEmpty)
    let invalid = withDiagnostics("1") {
      captureStderr {
        let reader = LicenseResources(root: root)
        for id in [nil, "SENTINEL /private/path token=secret"] as [String?] {
          do { _ = try reader.read(id: id); preconditionFailure("Unknown ID accepted") }
          catch { precondition(error is LicenseResources.Failure) }
        }
      }
    }
    precondition(invalid == String(repeating:
      "[lineup-license-native] operation=read stage=document_id category=invalid\n", count: 2))
    // An absent child has its own stage, independently of the bundle root.
    let child = withDiagnostics("1") {
      captureStderr {
        do { _ = try LicenseResources(bundle: root).list(); preconditionFailure("Missing child accepted") }
        catch { precondition(error is LicenseResources.Failure) }
      }
    }
    precondition(child == "[lineup-license-native] operation=list stage=bundle_child_open category=system errno=2\n")
  }

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
    try probeContract(root, temporary.appendingPathComponent("absent-SENTINEL"))
    let diagnosticEnvironment = getenv("LINEUP_LICENSE_DIAGNOSTICS").map { String(cString: $0) }
    setenv("LINEUP_LICENSE_DIAGNOSTICS", "1", 1)
    let reader = LicenseResources(root: root)
    if let diagnosticEnvironment { setenv("LINEUP_LICENSE_DIAGNOSTICS", diagnosticEnvironment, 1) }
    else { unsetenv("LINEUP_LICENSE_DIAGNOSTICS") }
    let entries = try reader.list()
    precondition(entries.count == 5)
    let extra = entries.first { $0["path"] as? String == "licenses/new component/nested/notice.txt" }!
    let content = try reader.read(id: (extra["id"] as! String))
    precondition(content == "License\n\nCopyright © test\n")
    func rejects(stage: String? = nil, _ body: () throws -> Void) {
      let output = withDiagnostics("1") {
        captureStderr {
          do { try body(); fatalError("Unsafe resource accepted") }
          catch { precondition(error is LicenseResources.Failure) }
        }
      }
      precondition(safeOutput(output))
      if let stage {
        precondition(output.split(separator: "\n").count == 1)
        precondition(output.contains(" stage=\(stage) "))
        precondition(!output.contains("SENTINEL") && !output.contains("resources/") && !output.contains("notice.txt"))
      }
    }
    for id in ["../BUILD-INFO.txt", "/etc/passwd", "licenses/mpv/LICENSE.LGPL", "native-999999"] {
      rejects { _ = try reader.read(id: id) }
    }
    let extraPath = root.appendingPathComponent("licenses/new component/nested/notice.txt")
    try FileManager.default.removeItem(at: extraPath)
    try FileManager.default.createSymbolicLink(at: extraPath, withDestinationURL: temporary)
    rejects { _ = try reader.read(id: (extra["id"] as! String)) }
    rejects { _ = try reader.list() }
    try FileManager.default.removeItem(at: extraPath)
    try write("licenses/new component/nested/notice.txt", Data([0xff, 0xfe]))
    rejects(stage: "file_encoding") { _ = try reader.list() }
    try write("licenses/new component/nested/notice.txt", Data(repeating: 65, count: 2 * 1024 * 1024 + 1))
    rejects(stage: "file_size") { _ = try reader.list() }
    try write("licenses/new component/nested/notice.txt", Data())
    rejects(stage: "file_size") { _ = try reader.list() }
    try FileManager.default.removeItem(at: extraPath)
    precondition(mkfifo(extraPath.path, 0o600) == 0)
    rejects(stage: "entry_kind") { _ = try reader.list() }
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
    rejects(stage: "required_index") { _ = try reader.list() }
    rejects { _ = try LicenseResources(root: temporary.appendingPathComponent("absent")).list() }
    if CommandLine.arguments.count == 2 {
      let realRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
      let real = LicenseResources(root: realRoot)
      let documents = try real.list()
      precondition(documents.count >= 53)
      for document in documents {
        let text = try real.read(id: (document["id"] as! String))
        let expected = try String(contentsOf: realRoot.appendingPathComponent(document["path"] as! String), encoding: .utf8)
        precondition(text == expected)
      }
      print("PASS: \(documents.count) actual prepared-runtime documents, exact text")
    }
    print("PASS: resource containment, opaque IDs, nested files, UTF-8, bounds, special files, missing inputs")
  }
}
