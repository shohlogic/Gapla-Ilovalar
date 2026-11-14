import Foundation
import os

/// Gapla (G64): one line per dictation step, so a slow dictation shows which step took the time.
/// A line is the job, the step, the wall-clock time in ms and a few numbers (length, bytes, type),
/// never the text. It goes to the device log (notice, public: readable over USB without a Mac,
/// `syslog live -m gapla-vaqt`) and to a small file in the App Group (`gapla-vaqt.log`, about the
/// last 500 lines). The keyboard writes the same lines into the same file
/// (KeyboardViewController.swift, KeyboardHandoffProvider.gaplaVaqt).
enum GaplaVaqt {
  static let fileName = "gapla-vaqt.log"
  private static let keptLines = 500
  /// Trimmed back to `keptLines` once past this size (~500 lines of ~120 bytes).
  private static let trimAtBytes = 64_000
  private static let logger = Logger(subsystem: "com.gizmolabs.openwhispr", category: "GaplaVaqt")
  private static let queue = DispatchQueue(label: "uz.gapla.vaqt", qos: .utility)

  static func nowMs() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }

  static func yoz(_ qadam: String, job: String?, extra: String = "", appGroupId: String) {
    let jobPart = (job?.isEmpty == false) ? job! : "-"
    let extraPart = extra.isEmpty ? "" : " \(extra)"
    let line = "gapla-vaqt job=\(jobPart) qadam=\(qadam) ms=\(nowMs())\(extraPart)"
    logger.notice("\(line, privacy: .public)")
    queue.async { append(line, appGroupId: appGroupId) }
  }

  private static func append(_ line: String, appGroupId: String) {
    guard let directory = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupId
    ) else { return }
    let url = directory.appendingPathComponent(fileName)
    let data = Data((line + "\n").utf8)
    if let handle = try? FileHandle(forWritingTo: url) {
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
      try? handle.close()
    } else {
      try? data.write(to: url, options: .atomic)
    }
    trimIfLong(url)
  }

  private static func trimIfLong(_ url: URL) {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? Int, size > trimAtBytes,
          let text = try? String(contentsOf: url, encoding: .utf8) else { return }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
    guard lines.count > keptLines else { return }
    let kept = lines.suffix(keptLines).joined(separator: "\n") + "\n"
    try? kept.write(to: url, atomically: true, encoding: .utf8)
  }
}
