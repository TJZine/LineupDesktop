import Foundation
import Darwin

/// Reads only immutable notice resources. No path supplied by Dart is resolved.
/// Directory descriptors and O_NOFOLLOW keep reads inside the originally opened tree.
final class LicenseResources {
  enum Failure: Error { case unavailable }
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
    guard fd >= 0 else { throw Failure.unavailable }
    for component in components {
      let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      close(fd)
      guard next >= 0 else { throw Failure.unavailable }
      fd = next
    }
    return fd
  }

  func list() throws -> [[String: Any]] {
    documents = [:]
    let fd = try directory()
    defer { close(fd) }
    var files: [(String, Int)] = []
    var total = 0
    for name in ["licenses", "patches"] {
      let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard child >= 0 else { throw Failure.unavailable }
      defer { close(child) }
      try walk(child, prefix: name, depth: 0, files: &files, total: &total)
      guard files.contains(where: { $0.0.hasPrefix(name + "/") }) else {
        throw Failure.unavailable
      }
    }
    let info = try readFile(fd, path: "BUILD-INFO.txt")
    guard String(data: info, encoding: .utf8) != nil, total + info.count <= treeLimit else {
      throw Failure.unavailable
    }
    files.append(("BUILD-INFO.txt", info.count))
    guard files.contains(where: { $0.0 == "licenses/NOTICES-SUMMARY.txt" }),
      files.contains(where: { $0.0 == "licenses/mpv/LICENSE.LGPL" }) else {
      throw Failure.unavailable
    }
    guard files.count <= 4096 else { throw Failure.unavailable }
    let sorted = files.sorted { $0.0 < $1.0 }
    var result: [[String: Any]] = []
    for (index, file) in sorted.enumerated() {
      let id = "native-\(index)"
      documents[id] = file.0
      result.append(["id": id, "path": file.0, "bytes": file.1])
    }
    return result
  }

  func read(id: String) throws -> String {
    guard let path = documents[id] else { throw Failure.unavailable }
    let fd = try directory()
    defer { close(fd) }
    let data = try readFile(fd, path: path)
    guard let text = String(data: data, encoding: .utf8) else { throw Failure.unavailable }
    return text
  }

  private func walk(_ fd: Int32, prefix: String, depth: Int,
                    files: inout [(String, Int)], total: inout Int) throws {
    guard depth < 16 else { throw Failure.unavailable }
    let duplicate = dup(fd)
    guard duplicate >= 0 else { throw Failure.unavailable }
    guard let stream = fdopendir(duplicate) else {
      close(duplicate)
      throw Failure.unavailable
    }
    defer { closedir(stream) }
    while true {
      errno = 0
      guard let entry = readdir(stream) else {
        guard errno == 0 else { throw Failure.unavailable }
        break
      }
      let name = withUnsafePointer(to: &entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(validatingCString: $0) }
      }
      guard let name else { throw Failure.unavailable }
      if name == "." || name == ".." { continue }
      guard !name.contains("/"), !name.isEmpty else { throw Failure.unavailable }
      var status = stat()
      guard fstatat(fd, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else { throw Failure.unavailable }
      let path = prefix + "/" + name
      if status.st_mode & S_IFMT == S_IFDIR {
        let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard child >= 0 else { throw Failure.unavailable }
        defer { close(child) }
        try walk(child, prefix: path, depth: depth + 1, files: &files, total: &total)
      } else {
        guard status.st_mode & S_IFMT == S_IFREG, status.st_size > 0,
          status.st_size <= fileLimit, files.count < 4096 else { throw Failure.unavailable }
        // Validate encoding and bounds now, so a corrupt document cannot be silently omitted.
        let data = try readFile(fd, path: name)
        guard String(data: data, encoding: .utf8) != nil else { throw Failure.unavailable }
        total += data.count
        guard total <= treeLimit else { throw Failure.unavailable }
        files.append((path, data.count))
      }
    }
  }

  private func readFile(_ rootFD: Int32, path: String) throws -> Data {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw Failure.unavailable
    }
    var fd = dup(rootFD)
    guard fd >= 0 else { throw Failure.unavailable }
    defer { close(fd) }
    for (index, part) in parts.enumerated() {
      let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK |
        (index < parts.count - 1 ? O_DIRECTORY : 0)
      let next = openat(fd, part, flags)
      guard next >= 0 else { throw Failure.unavailable }
      close(fd)
      fd = next
    }
    var status = stat()
    guard fstat(fd, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
      status.st_size > 0, status.st_size <= fileLimit else { throw Failure.unavailable }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 32768)
    while true {
      let count = Darwin.read(fd, &buffer, buffer.count)
      if count < 0 {
        if errno == EINTR { continue }
        throw Failure.unavailable
      }
      if count == 0 { break }
      guard data.count + count <= fileLimit else { throw Failure.unavailable }
      data.append(contentsOf: buffer.prefix(count))
    }
    guard !data.isEmpty else { throw Failure.unavailable }
    return data
  }
}
