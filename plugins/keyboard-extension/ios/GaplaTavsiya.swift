import Foundation
import UIKit
import os

/// Gapla (G57, analysis finding 4): the list's cost in the extension's memory, in the device log — the same category and
/// «gapla-xotira» prefix as the keyboard's own lines (KeyboardViewController.logMemory), so one grep finds them all.
private let tavsiyaMemoryLog = Logger(subsystem: "com.gizmolabs.openwhispr.keyboard", category: "UI")

private func logTavsiyaMemory(_ moment: String, words: Int? = nil) {
  let footprint = String(format: "%.1f", RecordingOrbView.footprintMB())
  let count = words.map { " sozlar=\($0)" } ?? ""
  tavsiyaMemoryLog.notice("gapla-xotira \(moment, privacy: .public) footprintMB=\(footprint, privacy: .public)\(count, privacy: .public)")
}

// Gapla (G41, G55): word suggestions on the iPhone and iPad keyboard. Owner, 2026-11-11 and 2026-11-12:
// [so'zlari: bilim/gapla-goyalar-royxati.md, G41 va G55]. The words and word pairs he writes
// live on the Gapla server — built from his own messages and dictations, then from what he types — so every device he
// uses knows them. Server contract: bilim/gapla-matn-tavsiyasi-reja.md, «Server kelishuvi». The Android keyboard does
// the same (GaplaTavsiya.kt).
//
// While he types, the toolbar's place shows up to three words: the rest of the word being typed, or the next word after
// a space (owner: the keyboard does not grow). The list is kept in the App Group, so it works offline, and is fetched
// again at most every six hours, with the version this keyboard has. What goes to the server is only the count of
// words and word pairs typed on the keys or picked from the row, never a sentence; the caller never counts in
// password, e-mail, address or number fields. Dictation is not sent — the server learns from it itself. Holding a
// suggestion forgets the word, here and on the server.
//
// Everything here runs on the main queue; only reading, parsing and writing the files happen on `ioQueue`.

final class GaplaTavsiya {
  static let shared = GaplaTavsiya()

  /// The word being typed and the word before it, read from the text before the cursor.
  struct Context {
    /// The letters right before the cursor, as typed; empty right after a space.
    let partial: String
    /// The word before `partial` when only spaces stand between them; nil after punctuation or a line break.
    let previous: String?
    /// The text before `partial`.
    let textBefore: String

    /// Nil where nothing is to be suggested: no word is being typed and the text does not end with a word and a space.
    init?(before: String) {
      var start = before.endIndex
      while start > before.startIndex {
        let prior = before.index(before: start)
        guard GaplaTavsiya.isWordCharacter(before[prior]) else { break }
        start = prior
      }
      let word = before[start...]
      let rest = before[..<start]

      var end = rest.endIndex
      var spaces = 0
      while end > rest.startIndex {
        let prior = rest.index(before: end)
        guard rest[prior] == " " else { break }
        spaces += 1
        end = prior
      }
      var wordStart = end
      if spaces > 0 {
        while wordStart > rest.startIndex {
          let prior = rest.index(before: wordStart)
          guard GaplaTavsiya.isWordCharacter(rest[prior]) else { break }
          wordStart = prior
        }
      }
      let previousWord = rest[wordStart..<end]

      let wordHasLetter = word.contains(where: { $0.isLetter })
      // Only apostrophes typed: not a word yet.
      if !word.isEmpty && !wordHasLetter { return nil }
      partial = String(word)
      previous = spaces > 0 && previousWord.contains(where: { $0.isLetter }) ? String(previousWord) : nil
      textBefore = String(rest)
      if partial.isEmpty && previous == nil { return nil }
    }
  }

  // Server contract: limits per request and per word (rules 3 and 4).
  private static let baseURL = URL(string: "https://gapla.xaliljonov.uz/v1/tavsiya")!
  private static let device = "iOS"
  private static let maxWord = 40
  private static let maxCount = 1000
  private static let maxWordsPerPost = 5000
  private static let maxPairsPerPost = 10_000
  /// What is asked for. The plan's safe size for a keyboard extension is 20–30 thousand words in 1–2 MB.
  private static let wordsWanted = 20_000
  private static let pairsWanted = 20_000
  /// G57: the most the keyboard keeps from any list, whatever the server or a saved file holds — the extension's memory
  /// limit is near 48–70 MB and the list must stay a small part of it.
  private static let maxListWords = 20_000
  private static let maxListPairs = 40_000
  /// Every dictation changes the list on the server, so it is not worth fetching more often (contract rule 7).
  private static let syncInterval: TimeInterval = 6 * 60 * 60
  /// A failed or refused fetch is not tried again before this.
  private static let retryInterval: TimeInterval = 5 * 60
  /// Counts go out once this many words and pairs wait, or this long after the last send.
  private static let sendAt = 40
  private static let sendEvery: TimeInterval = 10 * 60
  private static let saveEvery = 10
  /// The keyboard keeps this many next words for each word, best first.
  private static let nextPerWord = 8
  /// How many of the list's best matches are weighed against what was typed here.
  private static let scanDepth = 12
  /// What one count typed here weighs against the server's score, until the server's list has it.
  private static let learnedWeight: Float = 3
  private static let learnedLimit = 3000

  private static let listFile = "lugat.json"
  private static let queueFile = "navbat.json"
  private static let syncedAtKey = "gapla_tavsiya_olingan"

  private static let apostropheVariants: [Character] = ["\u{02BC}", "\u{2019}", "\u{2018}", "`", "\u{02BB}"]

  private struct Entry {
    /// Lower case, apostrophes as ', for matching.
    let key: String
    /// As it is usually written (Toshkent, SGBF).
    let word: String
    let score: Float
  }

  /// The server's list as the keyboard uses it.
  private final class Model {
    let versiya: Int64?
    /// Best score first.
    let entries: [Entry]
    /// Indices into `entries` by the key's first character, best score first.
    let byFirst: [Character: [Int32]]
    /// Next words by the previous word's key, best first.
    let next: [String: [Entry]]

    init(versiya: Int64?, entries: [Entry], byFirst: [Character: [Int32]], next: [String: [Entry]]) {
      self.versiya = versiya
      self.entries = entries
      self.byFirst = byFirst
      self.next = next
    }
  }

  private enum Parsed {
    case unchanged
    case list(Model)
  }

  /// Called on the main queue when the list or what was learned here changes.
  var onChange: (() -> Void)?

  private let ioQueue = DispatchQueue(label: "uz.gapla.tavsiya", qos: .utility)
  private let session: URLSession
  private var accessGroup: String?
  private var keyReader: GaplaClipboardClient?
  private var folder: URL?
  private var model: Model?
  private var loading = false
  private var syncing = false
  private var sending = false
  private var lastSyncAttempt: Date?
  private var lastSend = Date.distantPast

  // What waits to be sent: word → count, "w1\tw2" → count, words to forget. Kept in navbat.json.
  private var queueLoaded = false
  private var words: [String: Int] = [:]
  private var pairs: [String: Int] = [:]
  private var forgets: [String] = []
  /// Forgotten words, hidden until a list that no longer has them arrives.
  private var hidden = Set<String>()
  private var sinceSave = 0

  // What was typed here, offered at once — the server's list has it only after the next fetch.
  private var learned: [String: Entry] = [:]
  private var learnedNext: [String: [String: Entry]] = [:]

  private init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration: configuration)
  }

  /// Whether anything can be suggested at all.
  var hasWords: Bool {
    !(model?.entries.isEmpty ?? true) || !learned.isEmpty
  }

  // MARK: Text rules

  static func isWordCharacter(_ character: Character) -> Bool {
    character.isLetter || character == "'" || apostropheVariants.contains(character)
  }

  /// A word opens a sentence when nothing stands before it, or a full stop, ?, ! or a line break.
  static func isSentenceStart(_ textBefore: String) -> Bool {
    guard let last = textBefore.last(where: { $0 != " " && $0 != "\t" }) else { return true }
    return last.isNewline || ".!?\u{2026}".contains(last)
  }

  static func capitalizedFirst(_ word: String) -> String {
    guard let first = word.first else { return word }
    return String(first).uppercased() + word.dropFirst()
  }

  /// The form words are matched in: lower case, apostrophes as '.
  static func fold(_ word: String) -> String {
    var folded = word.lowercased()
    for mark in apostropheVariants where folded.contains(mark) {
      folded = folded.replacingOccurrences(of: String(mark), with: "'")
    }
    return folded.precomposedStringWithCanonicalMapping
  }

  /// The server's rules for a word (contract rule 3): apostrophes as ', at most 40 characters, letters only — no
  /// digits, addresses, @name or #tag. A sentence's first word goes in lower case unless it is all capitals (rule 1).
  static func clean(_ word: String, sentenceStart: Bool) -> String? {
    var cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines)
    for mark in apostropheVariants where cleaned.contains(mark) {
      cleaned = cleaned.replacingOccurrences(of: String(mark), with: "'")
    }
    cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "'-"))
    guard !cleaned.isEmpty, cleaned.count <= maxWord else { return nil }
    guard cleaned.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" }),
          cleaned.contains(where: { $0.isLetter })
    else { return nil }
    let letters = cleaned.filter { $0.isLetter }
    let allCaps = cleaned.count > 1 && letters.allSatisfy { $0.isUppercase }
    if sentenceStart && !allCaps { cleaned = cleaned.lowercased() }
    return cleaned.precomposedStringWithCanonicalMapping
  }

  // MARK: Suggesting

  /// Up to `limit` words, best first: words that often follow `previous` (and begin with `partial`), then words that
  /// begin with `partial`. Returned as usually written; the caller matches the typed capitals.
  func suggest(partial: String, previous: String?, limit: Int = 3) -> [String] {
    let prefix = Self.fold(partial)
    var result: [String] = []
    var used = Set<String>()

    func take(_ ranked: [String: Entry]) {
      let sorted = ranked.values.sorted { $0.score != $1.score ? $0.score > $1.score : $0.key < $1.key }
      for entry in sorted {
        if result.count >= limit { return }
        if hidden.contains(entry.key) { continue }
        if used.insert(entry.key).inserted { result.append(entry.word) }
      }
    }

    func matches(_ key: String) -> Bool {
      prefix.isEmpty || key.utf8.starts(with: prefix.utf8)
    }

    if let previous {
      let previousKey = Self.fold(previous)
      if !hidden.contains(previousKey) {
        var ranked: [String: Entry] = [:]
        for entry in model?.next[previousKey] ?? [] where matches(entry.key) {
          ranked[entry.key] = entry
        }
        for entry in (learnedNext[previousKey] ?? [:]).values where matches(entry.key) {
          let listed = ranked[entry.key]
          ranked[entry.key] = Entry(
            key: entry.key,
            word: listed?.word ?? entry.word,
            score: (listed?.score ?? 0) + entry.score * Self.learnedWeight
          )
        }
        take(ranked)
      }
    }

    guard result.count < limit, !prefix.isEmpty else { return result }
    var ranked: [String: Entry] = [:]
    if let model, let first = prefix.first, let indices = model.byFirst[first] {
      var found = 0
      for index in indices {
        let entry = model.entries[Int(index)]
        guard entry.key.utf8.starts(with: prefix.utf8) else { continue }
        ranked[entry.key] = entry
        found += 1
        if found >= Self.scanDepth { break }
      }
    }
    for entry in learned.values where entry.key.utf8.starts(with: prefix.utf8) {
      let listed = ranked[entry.key]
      ranked[entry.key] = Entry(
        key: entry.key,
        word: listed?.word ?? entry.word,
        score: (listed?.score ?? 0) + entry.score * Self.learnedWeight
      )
    }
    take(ranked)
    return result
  }

  // MARK: Starting, learning, forgetting

  /// The keyboard came up with Full Access: the saved list is read once, then fetched again when it is due.
  func start(accessGroup: String) {
    if self.accessGroup == nil {
      self.accessGroup = accessGroup
      keyReader = GaplaClipboardClient(accessGroup: accessGroup)
      let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: accessGroup)
        ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      if let directory = base?.appendingPathComponent("GaplaTavsiya", isDirectory: true) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        folder = directory
      }
      loadQueue()
    }
    if model == nil {
      loadSavedList()
    } else {
      syncIfDue()
    }
  }

  /// The keyboard is going away: what waits is saved, and sent when it is due.
  func flush() {
    guard accessGroup != nil else { return }
    saveQueue()
    if sendIsDue || !forgets.isEmpty { sendPending() }
  }

  /// One finished word typed on the keys or picked from the row, with the word before it when that belongs to the
  /// same run. The caller has already ruled out fields that must not be learned from.
  func countTyped(_ word: String, previous: String?, sentenceStart: Bool) {
    guard accessGroup != nil, let cleaned = Self.clean(word, sentenceStart: sentenceStart) else { return }
    words[cleaned] = min((words[cleaned] ?? 0) + 1, Self.maxCount)
    noteLearned(cleaned, count: 1)
    if let previous, let first = Self.clean(previous, sentenceStart: true) {
      let key = first.lowercased() + "\t" + cleaned.lowercased()
      pairs[key] = min((pairs[key] ?? 0) + 1, Self.maxCount)
      noteLearnedPair(first: first, second: cleaned, count: 1)
    }
    sinceSave += 1
    if sinceSave >= Self.saveEvery { saveQueue() }
    if sendIsDue { sendPending() }
  }

  /// Holding a suggestion (owner's «unut»): the word leaves the row at once and the server forgets it and its pairs;
  /// offline, the forget waits in the queue.
  func forget(_ word: String) {
    let key = Self.fold(word.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !key.isEmpty else { return }
    hidden.insert(key)
    if !forgets.contains(key) { forgets.append(key) }
    words = words.filter { Self.fold($0.key) != key }
    pairs = pairs.filter { !$0.key.components(separatedBy: "\t").contains(key) }
    learned.removeValue(forKey: key)
    learnedNext.removeValue(forKey: key)
    for first in Array(learnedNext.keys) {
      learnedNext[first]?.removeValue(forKey: key)
    }
    saveQueue()
    sendPending()
    onChange?()
  }

  private var sendIsDue: Bool {
    let waiting = words.count + pairs.count
    return waiting >= Self.sendAt || (waiting > 0 && Date().timeIntervalSince(lastSend) >= Self.sendEvery)
  }

  private func noteLearned(_ word: String, count: Int) {
    let key = Self.fold(word)
    if let known = learned[key] {
      learned[key] = Entry(key: key, word: known.word, score: known.score + Float(count))
    } else if learned.count < Self.learnedLimit {
      learned[key] = Entry(key: key, word: word, score: Float(count))
    }
  }

  private func noteLearnedPair(first: String, second: String, count: Int) {
    let firstKey = Self.fold(first)
    let key = Self.fold(second)
    var list = learnedNext[firstKey] ?? [:]
    if let known = list[key] {
      list[key] = Entry(key: key, word: known.word, score: known.score + Float(count))
    } else if learnedNext.count < Self.learnedLimit {
      list[key] = Entry(key: key, word: second, score: Float(count))
    }
    if !list.isEmpty { learnedNext[firstKey] = list }
  }

  // MARK: The list

  private var defaults: UserDefaults? {
    accessGroup.flatMap { UserDefaults(suiteName: $0) }
  }

  private func loadSavedList() {
    guard !loading else { return }
    guard let url = folder?.appendingPathComponent(Self.listFile) else { return }
    loading = true
    logTavsiyaMemory("lugat-oldin")
    ioQueue.async {
      // G57: the file's bytes and the parser's temporary objects go as soon as the list is built.
      let parsed: Parsed? = autoreleasepool {
        (try? Data(contentsOf: url)).flatMap { Self.parse($0) }
      }
      DispatchQueue.main.async {
        self.loading = false
        if self.model == nil, case .list(let model)? = parsed {
          self.model = model
          self.onChange?()
        }
        logTavsiyaMemory("lugat-keyin", words: self.model?.entries.count)
        self.syncIfDue()
      }
    }
  }

  private func syncIfDue() {
    guard !syncing, !loading, folder != nil else { return }
    let now = Date()
    let age = now.timeIntervalSince1970 - (defaults?.double(forKey: Self.syncedAtKey) ?? 0)
    if model != nil, age >= 0, age < Self.syncInterval {
      if sendIsDue || !forgets.isEmpty { sendPending() }
      return
    }
    if let lastSyncAttempt, now.timeIntervalSince(lastSyncAttempt) < Self.retryInterval { return }
    lastSyncAttempt = now
    syncing = true
    // What waits goes out first, so the list that comes back already has it.
    sendPending { [weak self] in self?.fetch() }
  }

  private func fetch() {
    var query = [
      URLQueryItem(name: "sozlar", value: String(Self.wordsWanted)),
      URLQueryItem(name: "juftlar", value: String(Self.pairsWanted)),
    ]
    // A list that is not here any more is fetched whole, whatever version was seen before.
    if let versiya = model?.versiya {
      query.append(URLQueryItem(name: "versiya", value: String(versiya)))
    }
    request("GET", path: nil, query: query, body: nil) { [weak self] status, data in
      guard let self else { return }
      // 404 before the server had the route, 401 without a key, or offline: the saved list stays.
      guard (200..<300).contains(status), let data else {
        self.syncing = false
        return
      }
      let url = self.folder?.appendingPathComponent(Self.listFile)
      self.ioQueue.async {
        // G57: the parser's temporary objects go as soon as the list is built.
        let parsed: Parsed? = autoreleasepool { Self.parse(data) }
        if case .list(_)? = parsed, let url {
          try? data.write(to: url, options: .atomic)
        }
        DispatchQueue.main.async {
          self.syncing = false
          switch parsed {
          case .unchanged?:
            self.markSynced()
          case .list(let model)?:
            self.model = model
            // The new list no longer has what the server forgot; what it has not been told yet stays hidden.
            self.hidden = Set(self.forgets)
            self.saveQueue()
            self.markSynced()
            self.onChange?()
            logTavsiyaMemory("lugat-yangi", words: model.entries.count)
          case nil:
            break
          }
        }
      }
    }
  }

  private func markSynced() {
    defaults?.set(Date().timeIntervalSince1970, forKey: Self.syncedAtKey)
  }

  /// The server's answer: `{"versiya", "sozlar": [[word, score]], "juftlar": [[w1, w2, score]]}`, or
  /// `{"versiya", "ozgarmagan": true}`. Nil for a body it cannot read.
  private static func parse(_ data: Data) -> Parsed? {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    if (root["ozgarmagan"] as? Bool) == true { return .unchanged }
    let versiya = (root["versiya"] as? NSNumber)?.int64Value

    var entries: [Entry] = []
    var seen = Set<String>()
    if let rows = root["sozlar"] as? [Any] {
      entries.reserveCapacity(min(rows.count, maxListWords))
      for item in rows {
        // G57: never more than maxListWords, whatever the list holds.
        if entries.count >= maxListWords { break }
        guard let row = item as? [Any], row.count >= 2, let raw = row[0] as? String else { continue }
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !word.contains(" ") else { continue }
        let key = fold(word)
        guard seen.insert(key).inserted else { continue }
        entries.append(Entry(key: key, word: word, score: (row[1] as? NSNumber)?.floatValue ?? 0))
      }
    }
    entries.sort { $0.score > $1.score }
    var byFirst: [Character: [Int32]] = [:]
    for (index, entry) in entries.enumerated() {
      guard let first = entry.key.first else { continue }
      byFirst[first, default: []].append(Int32(index))
    }

    var next: [String: [Entry]] = [:]
    if let rows = root["juftlar"] as? [Any] {
      var pairCount = 0
      for item in rows {
        // G57: never more than maxListPairs, whatever the list holds.
        if pairCount >= maxListPairs { break }
        guard let row = item as? [Any], row.count >= 3,
              let rawFirst = row[0] as? String, let rawSecond = row[1] as? String
        else { continue }
        let first = fold(rawFirst.trimmingCharacters(in: .whitespacesAndNewlines))
        let second = rawSecond.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty, !second.isEmpty, !first.contains(" "), !second.contains(" ") else { continue }
        let score = (row[2] as? NSNumber)?.floatValue ?? 1
        next[first, default: []].append(Entry(key: fold(second), word: second, score: score))
        pairCount += 1
      }
    }
    next = next.mapValues { list in
      Array(list.sorted { $0.score > $1.score }.prefix(nextPerWord))
    }
    return .list(Model(versiya: versiya, entries: entries, byFirst: byFirst, next: next))
  }

  // MARK: The queue

  private func loadQueue() {
    guard !queueLoaded else { return }
    queueLoaded = true
    guard let url = folder?.appendingPathComponent(Self.queueFile),
          let data = try? Data(contentsOf: url),
          let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return }
    if let saved = root["sozlar"] as? [String: Any] {
      for (word, value) in saved {
        guard let count = (value as? NSNumber)?.intValue, count > 0 else { continue }
        words[word] = min((words[word] ?? 0) + count, Self.maxCount)
        noteLearned(word, count: count)
      }
    }
    if let saved = root["juftlar"] as? [String: Any] {
      for (key, value) in saved {
        guard let count = (value as? NSNumber)?.intValue, count > 0 else { continue }
        let parts = key.components(separatedBy: "\t")
        guard parts.count == 2 else { continue }
        pairs[key] = min((pairs[key] ?? 0) + count, Self.maxCount)
        noteLearnedPair(first: parts[0], second: parts[1], count: count)
      }
    }
    if let saved = root["unut"] as? [String] {
      for word in saved where !forgets.contains(word) { forgets.append(word) }
    }
    if let saved = root["yashirin"] as? [String] {
      hidden.formUnion(saved)
    }
    hidden.formUnion(forgets)
  }

  /// Written beside the file and moved over it, so a crash mid-write never leaves it empty.
  private func saveQueue() {
    sinceSave = 0
    guard let url = folder?.appendingPathComponent(Self.queueFile) else { return }
    let empty = words.isEmpty && pairs.isEmpty && forgets.isEmpty && hidden.isEmpty
    let body: [String: Any] = ["sozlar": words, "juftlar": pairs, "unut": forgets, "yashirin": Array(hidden)]
    ioQueue.async {
      if empty {
        try? FileManager.default.removeItem(at: url)
        return
      }
      guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
      try? data.write(to: url, options: .atomic)
    }
  }

  /// Sends the forgets, then the counts in server-sized pieces; what fails stays for the next try. `done` runs once
  /// nothing more can be sent now.
  private func sendPending(then done: (() -> Void)? = nil) {
    guard !sending, keyReader != nil else {
      done?()
      return
    }
    if let word = forgets.first {
      sending = true
      request("POST", path: "unut", query: nil, body: ["soz": word]) { [weak self] status, _ in
        guard let self else { return }
        self.sending = false
        // 404: the server never had it; 400: it never will take it.
        guard (200..<300).contains(status) || status == 404 || status == 400 else {
          done?()
          return
        }
        self.forgets.removeAll { $0 == word }
        self.saveQueue()
        self.sendPending(then: done)
      }
      return
    }
    guard !words.isEmpty || !pairs.isEmpty else {
      done?()
      return
    }
    let wordChunk = Array(words.prefix(Self.maxWordsPerPost))
    let pairChunk = Array(pairs.prefix(Self.maxPairsPerPost))
    var sentWords: [String: Int] = [:]
    for entry in wordChunk { sentWords[entry.key] = entry.value }
    var sentPairs: [[Any]] = []
    for entry in pairChunk {
      let parts = entry.key.components(separatedBy: "\t")
      guard parts.count == 2 else { continue }
      sentPairs.append([parts[0], parts[1], entry.value])
    }
    let body: [String: Any] = ["sozlar": sentWords, "juftlar": sentPairs, "qurilma": Self.device]
    sending = true
    lastSend = Date()
    request("POST", path: nil, query: nil, body: body) { [weak self] status, _ in
      guard let self else { return }
      self.sending = false
      // 400: the server will never take this piece — dropped rather than sent forever. Offline, 401, 5xx: kept.
      guard (200..<300).contains(status) || status == 400 else {
        done?()
        return
      }
      for entry in wordChunk {
        let left = (self.words[entry.key] ?? 0) - entry.value
        if left > 0 { self.words[entry.key] = left } else { self.words.removeValue(forKey: entry.key) }
      }
      for entry in pairChunk {
        let left = (self.pairs[entry.key] ?? 0) - entry.value
        if left > 0 { self.pairs[entry.key] = left } else { self.pairs.removeValue(forKey: entry.key) }
      }
      self.saveQueue()
      if self.words.isEmpty && self.pairs.isEmpty {
        done?()
      } else {
        self.sendPending(then: done)
      }
    }
  }

  /// One call to the Gapla server with the dictation key; `completion` gets the HTTP status (0 offline) on the main
  /// queue. Only words and counts travel here, and nothing of them is logged.
  private func request(
    _ method: String,
    path: String?,
    query: [URLQueryItem]?,
    body: [String: Any]?,
    completion: @escaping (Int, Data?) -> Void
  ) {
    guard let key = keyReader?.serverKey() else {
      DispatchQueue.main.async { completion(401, nil) }
      return
    }
    let url = path.map { Self.baseURL.appendingPathComponent($0) } ?? Self.baseURL
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.queryItems = query
    guard let requestURL = components?.url else {
      DispatchQueue.main.async { completion(0, nil) }
      return
    }
    var request = URLRequest(url: requestURL)
    request.httpMethod = method
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.httpBody = try? JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    session.dataTask(with: request) { data, response, error in
      let status = error == nil ? ((response as? HTTPURLResponse)?.statusCode ?? 0) : 0
      DispatchQueue.main.async { completion(status, data) }
    }.resume()
  }
}

/// The three suggestion slots in the toolbar's place: the best word in the middle, as on Apple's keyboard, the next
/// ones left and right. A tap writes the word; holding it forgets the word.
final class GaplaTavsiyaBar: UIView {
  var onPick: ((String) -> Void)?
  var onForget: ((String) -> Void)?

  private final class Slot: UIButton {
    var word: String?
    var canForget = false
    var pressedColor: UIColor = .clear

    override var isHighlighted: Bool {
      didSet { backgroundColor = isHighlighted ? pressedColor : .clear }
    }
  }

  private let slots: [Slot] = (0..<3).map { _ in Slot(type: .custom) }
  private let dividers: [UIView] = (0..<2).map { _ in UIView() }
  private let noteLabel = UILabel()
  private var noteTimer: Timer?
  private var pending: (words: [String], literal: Bool) = ([], false)

  init(textColor: UIColor, pressedColor: UIColor) {
    super.init(frame: .zero)
    let stack = UIStackView(arrangedSubviews: slots)
    stack.axis = .horizontal
    stack.distribution = .fillEqually
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    for slot in slots {
      slot.pressedColor = pressedColor
      slot.layer.cornerRadius = 8
      slot.setTitleColor(textColor, for: .normal)
      slot.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .regular)
      slot.titleLabel?.lineBreakMode = .byTruncatingMiddle
      slot.titleLabel?.adjustsFontSizeToFitWidth = true
      slot.titleLabel?.minimumScaleFactor = 0.75
      slot.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)
      let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
      hold.minimumPressDuration = 0.5
      slot.addGestureRecognizer(hold)
    }

    for (index, divider) in dividers.enumerated() {
      divider.backgroundColor = UIColor.separator
      divider.isUserInteractionEnabled = false
      divider.translatesAutoresizingMaskIntoConstraints = false
      addSubview(divider)
      NSLayoutConstraint.activate([
        divider.widthAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        divider.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.55),
        divider.centerYAnchor.constraint(equalTo: centerYAnchor),
        divider.centerXAnchor.constraint(equalTo: slots[index].trailingAnchor),
      ])
    }

    noteLabel.textColor = textColor
    noteLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
    noteLabel.textAlignment = .center
    noteLabel.adjustsFontSizeToFitWidth = true
    noteLabel.minimumScaleFactor = 0.75
    noteLabel.alpha = 0
    noteLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(noteLabel)
    NSLayoutConstraint.activate([
      noteLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      noteLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      noteLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// `words` best first. `literal`: nothing in the list matches, so the one word is what was typed, in quotes as on
  /// Apple's keyboard; a tap keeps it and adds a space.
  func show(_ words: [String], literal: Bool) {
    pending = (words, literal)
    guard noteTimer == nil else { return }
    apply()
  }

  /// A short line in the slots' place, such as «salom» unutildi; then the suggestions again.
  func showNote(_ text: String) {
    noteTimer?.invalidate()
    noteLabel.text = text
    noteLabel.alpha = 1
    slots.forEach { $0.alpha = 0 }
    dividers.forEach { $0.alpha = 0 }
    noteTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
      guard let self else { return }
      self.noteTimer = nil
      self.noteLabel.alpha = 0
      self.slots.forEach { $0.alpha = 1 }
      self.dividers.forEach { $0.alpha = 1 }
      self.apply()
    }
  }

  private func apply() {
    // Best in the middle, the second on the left, the third on the right.
    let order = [1, 0, 2]
    for slot in slots {
      slot.word = nil
      slot.canForget = false
      slot.setTitle(nil, for: .normal)
      slot.isAccessibilityElement = false
    }
    for (rank, word) in pending.words.prefix(3).enumerated() {
      let slot = slots[order[rank]]
      slot.word = word
      slot.canForget = !pending.literal
      slot.setTitle(pending.literal ? "\u{00AB}\(word)\u{00BB}" : word, for: .normal)
      slot.isAccessibilityElement = true
      slot.accessibilityLabel = word
      slot.accessibilityHint = pending.literal ? nil : "Bosib tursangiz, bu so'z boshqa taklif qilinmaydi"
    }
    dividers[0].isHidden = slots[0].word == nil || slots[1].word == nil
    dividers[1].isHidden = slots[1].word == nil || slots[2].word == nil
  }

  @objc private func handleTap(_ sender: UIButton) {
    guard let slot = sender as? Slot, let word = slot.word else { return }
    onPick?(word)
  }

  @objc private func handleHold(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .began, let slot = gesture.view as? Slot, slot.canForget, let word = slot.word else {
      return
    }
    slot.isHighlighted = false
    onForget?(word)
  }
}
