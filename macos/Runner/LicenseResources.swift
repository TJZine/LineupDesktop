import Foundation
import Darwin

/// Reads only immutable notice resources. No path supplied by Dart is resolved.
/// Directory descriptors and O_NOFOLLOW keep reads inside the originally opened tree.
final class LicenseResources {
  enum Stage: String {
    case rootOpen = "root_open", bundleChildOpen = "bundle_child_open"
    case treeOpen = "tree_open", traversalDuplicate = "traversal_duplicate"
    case traversalOpen = "traversal_open", traversalRead = "traversal_read"
    case entryName = "entry_name", entryStat = "entry_stat"
    case entryDirectoryOpen = "entry_directory_open", entryKind = "entry_kind"
    case fileSize = "file_size", entryCount = "entry_count", filePath = "file_path"
    case fileDuplicate = "file_duplicate", fileOpen = "file_open", fileStat = "file_stat"
    case fileRead = "file_read", fileEncoding = "file_encoding", treeBounds = "tree_bounds"
    case requiredIndex = "required_index", documentID = "document_id", depthBounds = "depth_bounds"
  }
  enum Category: String { case system, invalid, bounds, missing, encoding }
  struct Failure: Error {
    let stage: Stage
    let category: Category
    let systemError: Int32?
    init(_ stage: Stage, _ category: Category, _ systemError: Int32? = nil) {
      self.stage = stage
      self.category = category
      self.systemError = systemError
    }
  }
  private enum Operation: String { case list, read }
  private let diagnosticsEnabled =
    ProcessInfo.processInfo.environment["LINEUP_LICENSE_DIAGNOSTICS"] == "1"

  // One failure-only record at the operation boundary. No raw input is accepted
  // by the sink; all string fields originate in these finite enums.
  private func report(_ operation: Operation, _ failure: Failure) {
    guard diagnosticsEnabled else { return }
    var line = "[lineup-license-native] operation=\(operation.rawValue) stage=\(failure.stage.rawValue) category=\(failure.category.rawValue)"
    if let code = failure.systemError, code > 0, code <= 4095 {
      line += " errno=\(code)"
    }
    line += "\n"
    line.withCString { _ = Darwin.write(STDERR_FILENO, $0, strlen($0)) }
  }
  private let root: URL
  private let components: [String]
  private var documents: [String: String] = [:]
  private let fileLimit = 2 * 1024 * 1024
  private let treeLimit = 16 * 1024 * 1024

  init(root: URL) { self.root = root; self.components = [] }

  init(bundle: URL) {
    self.root = bundle
    self.components = ["Contents", "Resources", "LineupNativeRuntime"]
  }

  private func directory() throws -> Int32 {
    var fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw Failure(.rootOpen, .system, errno) }
    for component in components {
      let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      let openError = errno
      close(fd)
      guard next >= 0 else { throw Failure(.bundleChildOpen, .system, openError) }
      fd = next
    }
    return fd
  }

  func list() throws -> [[String: Any]] {
    do { return try index() }
    catch let failure as Failure { report(.list, failure); throw failure }
  }

  private func index() throws -> [[String: Any]] {
    documents = [:]
    let fd = try directory()
    defer { close(fd) }
    var files: [(String, Int)] = []
    var total = 0
    for name in ["licenses", "patches"] {
      let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard child >= 0 else { throw Failure(.treeOpen, .system, errno) }
      defer { close(child) }
      try walk(child, prefix: name, depth: 0, files: &files, total: &total)
      guard files.contains(where: { $0.0.hasPrefix(name + "/") }) else {
        throw Failure(.requiredIndex, .missing)
      }
    }
    let info = try readFile(fd, path: "BUILD-INFO.txt")
    guard String(data: info, encoding: .utf8) != nil else { throw Failure(.fileEncoding, .encoding) }
    guard total + info.count <= treeLimit else { throw Failure(.treeBounds, .bounds) }
    files.append(("BUILD-INFO.txt", info.count))
    guard files.contains(where: { $0.0 == "licenses/NOTICES-SUMMARY.txt" }),
      files.contains(where: { $0.0 == "licenses/mpv/LICENSE.LGPL" }) else {
      throw Failure(.requiredIndex, .missing)
    }
    guard files.count <= 4096 else { throw Failure(.entryCount, .bounds) }
    let sorted = files.sorted { $0.0 < $1.0 }
    var result: [[String: Any]] = []
    for (index, file) in sorted.enumerated() {
      let id = "native-\(index)"
      documents[id] = file.0
      result.append(["id": id, "path": file.0, "bytes": file.1])
    }
    return result
  }

  func read(id: String?) throws -> String {
    do {
      guard let id, let path = documents[id] else { throw Failure(.documentID, .invalid) }
      let fd = try directory()
      defer { close(fd) }
      let data = try readFile(fd, path: path)
      guard let text = String(data: data, encoding: .utf8) else { throw Failure(.fileEncoding, .encoding) }
      return text
    } catch let failure as Failure { report(.read, failure); throw failure }
  }

  private func walk(_ fd: Int32, prefix: String, depth: Int,
                    files: inout [(String, Int)], total: inout Int) throws {
    guard depth < 16 else { throw Failure(.depthBounds, .bounds) }
    let duplicate = dup(fd)
    guard duplicate >= 0 else { throw Failure(.traversalDuplicate, .system, errno) }
    guard let stream = fdopendir(duplicate) else {
      let openError = errno
      close(duplicate)
      throw Failure(.traversalOpen, .system, openError)
    }
    defer { closedir(stream) }
    while true {
      errno = 0
      guard let entry = readdir(stream) else {
        guard errno == 0 else { throw Failure(.traversalRead, .system, errno) }
        break
      }
      let name = withUnsafePointer(to: &entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(validatingCString: $0) }
      }
      guard let name else { throw Failure(.entryName, .encoding) }
      if name == "." || name == ".." { continue }
      guard !name.contains("/"), !name.isEmpty else { throw Failure(.entryName, .invalid) }
      var status = stat()
      guard fstatat(fd, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else { throw Failure(.entryStat, .system, errno) }
      let path = prefix + "/" + name
      if status.st_mode & S_IFMT == S_IFDIR {
        let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard child >= 0 else { throw Failure(.entryDirectoryOpen, .system, errno) }
        defer { close(child) }
        try walk(child, prefix: path, depth: depth + 1, files: &files, total: &total)
      } else {
        guard status.st_mode & S_IFMT == S_IFREG else { throw Failure(.entryKind, .invalid) }
        guard status.st_size > 0, status.st_size <= fileLimit else { throw Failure(.fileSize, .bounds) }
        guard files.count < 4096 else { throw Failure(.entryCount, .bounds) }
        // Validate encoding and bounds now, so a corrupt document cannot be silently omitted.
        let data = try readFile(fd, path: name)
        guard String(data: data, encoding: .utf8) != nil else { throw Failure(.fileEncoding, .encoding) }
        total += data.count
        guard total <= treeLimit else { throw Failure(.treeBounds, .bounds) }
        files.append((path, data.count))
      }
    }
  }

  private func readFile(_ rootFD: Int32, path: String) throws -> Data {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw Failure(.filePath, .invalid)
    }
    var fd = dup(rootFD)
    guard fd >= 0 else { throw Failure(.fileDuplicate, .system, errno) }
    defer { close(fd) }
    for (index, part) in parts.enumerated() {
      let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK |
        (index < parts.count - 1 ? O_DIRECTORY : 0)
      let next = openat(fd, part, flags)
      guard next >= 0 else { throw Failure(.fileOpen, .system, errno) }
      close(fd)
      fd = next
    }
    var status = stat()
    guard fstat(fd, &status) == 0 else { throw Failure(.fileStat, .system, errno) }
    guard status.st_mode & S_IFMT == S_IFREG else { throw Failure(.entryKind, .invalid) }
    guard status.st_size > 0, status.st_size <= fileLimit else { throw Failure(.fileSize, .bounds) }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 32768)
    while true {
      let count = Darwin.read(fd, &buffer, buffer.count)
      if count < 0 {
        if errno == EINTR { continue }
        throw Failure(.fileRead, .system, errno)
      }
      if count == 0 { break }
      guard data.count + count <= fileLimit else { throw Failure(.fileSize, .bounds) }
      data.append(contentsOf: buffer.prefix(count))
    }
    guard !data.isEmpty else { throw Failure(.fileSize, .bounds) }
    return data
  }
}
