import Foundation
import Security
import UIKit

// Gapla (G8): the shared clipboard on the Gapla server. Owner, 2026-11-11: [so'zlari: bilim/gapla-goyalar-royxati.md].
// So: the list loads only when the clipboard page opens (no background sync); it holds each
// copy's first 200 characters; the full text is fetched and put on the iPhone clipboard only
// when one is chosen; this iPhone's current copy goes up only with the add button (iOS lets a
// keyboard read the clipboard only while it is open). Server contract: bilim/gapla-bufer-reja.md,
// «Server qismi».
// Owner, 2026-11-11, on Android: [so'zlari: bilim/gapla-goyalar-royxati.md] — both
// phones alike: the button shows the last list at once from what the keyboard saved, the
// server's list replaces it quietly, and a full text fetched once is not fetched again
// (GaplaClipboardStore).

struct GaplaClipboardItem: Codable, Equatable {
  let id: Int
  let boshi: String
  let uzunlik: Int
  let qurilma: String
  let vaqt: Double
  let qadalgan: Bool
  let maxfiy: Bool
}

enum GaplaClipboardError: Error {
  case noKey, unauthorized, tooLarge, notFound, disabled, tooManyRequests, network, server

  var message: String {
    switch self {
    case .noKey: return "Gapla kaliti topilmadi. Gapla ilovasini bir marta oching."
    case .unauthorized: return "Kalit noto'g'ri. Gapla ilovasida kalitni tekshiring."
    case .tooLarge: return "Juda katta, saqlanmadi"
    case .notFound: return "Bu nusxa endi yo'q"
    case .disabled: return "Bufer serverda o'chiq"
    case .tooManyRequests: return "Juda ko'p so'rov. Birozdan keyin urinib ko'ring."
    case .network: return "Internet yo'q yoki server javob bermadi"
    case .server: return "Serverda xato. Keyinroq urinib ko'ring."
    }
  }
}

final class GaplaClipboardClient {
  /// The server keeps at most this many characters (Python `len`, i.e. Unicode scalars).
  static let maxCharacters = 100_000

  private static let baseURL = URL(string: "https://gapla.xaliljonov.uz/v1/bufer")!
  // The app writes this item (AppGroupStorageModule.swift, setSharedServerKey).
  private static let keyService = "gapla.server"
  private static let keyAccount = "dictation-key"

  private let accessGroup: String
  private let session: URLSession

  init(accessGroup: String) {
    self.accessGroup = accessGroup
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration: configuration)
  }

  /// The dictation key the app mirrored into the App Group's Keychain group; nil until the app
  /// has run once with a key.
  func serverKey() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.keyService,
      kSecAttrAccount as String: Self.keyAccount,
      kSecAttrAccessGroup as String: accessGroup,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data,
          let key = String(data: data, encoding: .utf8),
          !key.isEmpty
    else { return nil }
    return key
  }

  private struct ListResponse: Decodable { let elementlar: [GaplaClipboardItem] }
  private struct FullResponse: Decodable { let matn: String }
  private struct AddResponse: Decodable { let yangi: Bool }

  func list(completion: @escaping (Result<[GaplaClipboardItem], GaplaClipboardError>) -> Void) {
    send("GET", query: [URLQueryItem(name: "soni", value: "50")]) { result in
      completion(result.flatMap { data -> Result<[GaplaClipboardItem], GaplaClipboardError> in
        guard let decoded = try? JSONDecoder().decode(ListResponse.self, from: data) else { return .failure(.server) }
        return .success(decoded.elementlar)
      })
    }
  }

  func fullText(id: Int, completion: @escaping (Result<String, GaplaClipboardError>) -> Void) {
    send("GET", path: "\(id)") { result in
      completion(result.flatMap { data -> Result<String, GaplaClipboardError> in
        guard let decoded = try? JSONDecoder().decode(FullResponse.self, from: data) else { return .failure(.server) }
        return .success(decoded.matn)
      })
    }
  }

  func setPinned(id: Int, pinned: Bool, completion: @escaping (Result<Void, GaplaClipboardError>) -> Void) {
    send("POST", path: "\(id)/qadash", body: ["qadalgan": pinned]) { completion($0.map { _ in () }) }
  }

  func delete(id: Int, completion: @escaping (Result<Void, GaplaClipboardError>) -> Void) {
    send("DELETE", path: "\(id)") { completion($0.map { _ in () }) }
  }

  /// Adds a copy; success says whether it is new (false: the same text was there and moved up).
  func add(text: String, device: String, secret: Bool, completion: @escaping (Result<Bool, GaplaClipboardError>) -> Void) {
    send("POST", body: ["matn": text, "qurilma": device, "maxfiy": secret]) { result in
      completion(result.map { data in (try? JSONDecoder().decode(AddResponse.self, from: data))?.yangi ?? true })
    }
  }

  /// Calls back on the main queue.
  private func send(
    _ method: String,
    path: String? = nil,
    query: [URLQueryItem]? = nil,
    body: [String: Any]? = nil,
    completion: @escaping (Result<Data, GaplaClipboardError>) -> Void
  ) {
    guard let key = serverKey() else {
      DispatchQueue.main.async { completion(.failure(.noKey)) }
      return
    }
    let url = path.map { Self.baseURL.appendingPathComponent($0) } ?? Self.baseURL
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.queryItems = query
    guard let requestURL = components?.url else {
      DispatchQueue.main.async { completion(.failure(.server)) }
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
      let result: Result<Data, GaplaClipboardError>
      if error != nil {
        result = .failure(.network)
      } else if let http = response as? HTTPURLResponse {
        switch http.statusCode {
        case 200..<300: result = .success(data ?? Data())
        case 401, 403: result = .failure(.unauthorized)
        case 404: result = .failure(.notFound)
        case 413: result = .failure(.tooLarge)
        case 429: result = .failure(.tooManyRequests)
        case 503: result = .failure(.disabled)
        default: result = .failure(.server)
        }
      } else {
        result = .failure(.server)
      }
      DispatchQueue.main.async { completion(result) }
    }.resume()
  }
}

/// What the keyboard keeps between openings, in its own Caches folder: the last list (the
/// starts only, as the server sent them) and each full text fetched, one file per copy. Files
/// for copies the list no longer has are removed each time a list is saved. A secret copy's full
/// text stays in memory only, while the keyboard runs — never on disk.
final class GaplaClipboardStore {
  static let shared = GaplaClipboardStore()

  private let folder: URL?
  private var secretTexts: [Int: String] = [:]

  private init() {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    folder = caches?.appendingPathComponent("GaplaBufer", isDirectory: true)
    if let folder {
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
  }

  private var listURL: URL? { folder?.appendingPathComponent("royxat.json") }

  private func textURL(_ id: Int) -> URL? { folder?.appendingPathComponent("matn-\(id).txt") }

  /// The list last saved; nil when there is none yet.
  func savedList() -> [GaplaClipboardItem]? {
    guard let url = listURL, let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode([GaplaClipboardItem].self, from: data)
  }

  func saveList(_ items: [GaplaClipboardItem]) {
    if let url = listURL, let data = try? JSONEncoder().encode(items) {
      try? data.write(to: url, options: .atomic)
    }
    let secretIDs = Set(items.filter { $0.maxfiy }.map { $0.id })
    let plainIDs = Set(items.filter { !$0.maxfiy }.map { $0.id })
    secretTexts = secretTexts.filter { entry in secretIDs.contains(entry.key) }
    guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
    for name in names where name.hasPrefix("matn-") && name.hasSuffix(".txt") {
      let id = Int(name.dropFirst(5).dropLast(4))
      if id.map({ plainIDs.contains($0) }) != true {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
      }
    }
  }

  /// The full text fetched before, if it still matches. The server never reuses an id, but a
  /// re-copy of the same text (line ends or edge spaces aside) keeps its id with the new text —
  /// the length tells them apart.
  func fullText(for item: GaplaClipboardItem) -> String? {
    let text: String?
    if item.maxfiy {
      text = secretTexts[item.id]
    } else if let url = textURL(item.id), let data = try? Data(contentsOf: url) {
      text = String(decoding: data, as: UTF8.self)
    } else {
      text = nil
    }
    guard let text, text.unicodeScalars.count == item.uzunlik else { return nil }
    return text
  }

  func storeFullText(_ text: String, for item: GaplaClipboardItem) {
    if item.maxfiy {
      secretTexts[item.id] = text
      return
    }
    guard let url = textURL(item.id) else { return }
    try? Data(text.utf8).write(to: url, options: .atomic)
  }
}

/// The clipboard page, in the letter rows' place (like the emoji page): the add button and a
/// status line on top, the list below — newest first, pinned ones above; each row has the
/// text's start, where and when it was copied, a pin and a delete button. Tap a row to copy it.
final class GaplaClipboardPanel: UIView, UITableViewDelegate {
  /// Plays the key click (the controller owns the input-click sound).
  var onKeyClick: (() -> Void)?

  // Pasteboard types password managers set on a secret copy (nspasteboard.org convention and
  // 1Password's own); reading the types does not read the text.
  private static let secretTypes: Set<String> = ["org.nspasteboard.ConcealedType", "com.agilebits.onepassword"]
  private static let rowHeight: CGFloat = 50
  private static let loadingText = "Yuklanmoqda…"
  private static let emptyText = "Bufer bo'sh. Biror matnni nusxalang va «Hozirgi nusxani qo'sh»ni bosing."

  private let client: GaplaClipboardClient
  private let store = GaplaClipboardStore.shared
  private let hasFullAccess: () -> Bool
  private let rowBackground: UIColor
  private let textColor: UIColor
  private let accent: UIColor
  private var items: [GaplaClipboardItem] = []
  /// The page shows a list — saved or from the server, even an empty one — so a refresh needs
  /// no loading note.
  private var hasList = false
  private var loadGeneration = 0
  private var statusTimer: Timer?
  private var dataSource: UITableViewDiffableDataSource<Int, Int>!

  private let addButton = UIButton(type: .system)
  /// Gapla (G53, owner 2026-11-12: [so'zlari: bilim/gapla-goyalar-royxati.md]): the same refresh as on opening, at the header's right end with
  /// the same circular-arrow icon as the Android panel (ClipboardInputLayout, Icons.Default.Refresh).
  private let refreshButton = UIButton(type: .system)
  private let statusLabel = UILabel()
  private let tableView = UITableView(frame: .zero, style: .plain)
  private let emptyLabel = UILabel()

  init(client: GaplaClipboardClient, hasFullAccess: @escaping () -> Bool, rowBackground: UIColor, textColor: UIColor, accent: UIColor) {
    self.client = client
    self.hasFullAccess = hasFullAccess
    self.rowBackground = rowBackground
    self.textColor = textColor
    self.accent = accent
    super.init(frame: .zero)

    var config = UIButton.Configuration.filled()
    config.title = "Hozirgi nusxani qo'sh"
    config.image = UIImage(systemName: "plus")
    config.imagePadding = 6
    config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
    config.baseBackgroundColor = rowBackground
    config.baseForegroundColor = textColor
    config.cornerStyle = .capsule
    config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 14)
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var attributes = attributes
      attributes.font = UIFont.systemFont(ofSize: 14, weight: .medium)
      return attributes
    }
    addButton.configuration = config
    addButton.accessibilityLabel = "Hozirgi nusxani qo'shish"
    addButton.addTarget(self, action: #selector(handleAddTapped), for: .touchUpInside)
    addButton.translatesAutoresizingMaskIntoConstraints = false
    addSubview(addButton)

    var refreshConfig = UIButton.Configuration.plain()
    refreshConfig.image = UIImage(systemName: "arrow.clockwise")
    refreshConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    refreshConfig.baseForegroundColor = textColor
    refreshConfig.contentInsets = .zero
    refreshButton.configuration = refreshConfig
    refreshButton.accessibilityLabel = "Yangilash"
    refreshButton.addTarget(self, action: #selector(handleRefreshTapped), for: .touchUpInside)
    refreshButton.translatesAutoresizingMaskIntoConstraints = false
    addSubview(refreshButton)

    statusLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
    statusLabel.textColor = .secondaryLabel
    statusLabel.textAlignment = .right
    statusLabel.adjustsFontSizeToFitWidth = true
    statusLabel.minimumScaleFactor = 0.8
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(statusLabel)

    tableView.backgroundColor = .clear
    tableView.separatorStyle = .none
    tableView.rowHeight = Self.rowHeight
    tableView.showsVerticalScrollIndicator = false
    tableView.delegate = self
    tableView.register(GaplaClipboardCell.self, forCellReuseIdentifier: GaplaClipboardCell.reuseIdentifier)
    // Rows are keyed by the copy's id, so a fresh list only moves, adds and removes the rows that
    // changed — the rest stay where they are.
    dataSource = UITableViewDiffableDataSource<Int, Int>(tableView: tableView) { [weak self] tableView, indexPath, id in
      let cell = tableView.dequeueReusableCell(withIdentifier: GaplaClipboardCell.reuseIdentifier, for: indexPath)
      guard let self,
            let clipboardCell = cell as? GaplaClipboardCell,
            let item = self.items.first(where: { $0.id == id })
      else { return cell }
      self.configure(clipboardCell, with: item)
      return clipboardCell
    }
    dataSource.defaultRowAnimation = .fade
    tableView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(tableView)

    emptyLabel.font = UIFont.systemFont(ofSize: 14)
    emptyLabel.textColor = .secondaryLabel
    emptyLabel.textAlignment = .center
    emptyLabel.numberOfLines = 0
    emptyLabel.isHidden = true
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(emptyLabel)

    NSLayoutConstraint.activate([
      addButton.leadingAnchor.constraint(equalTo: leadingAnchor),
      addButton.topAnchor.constraint(equalTo: topAnchor),
      addButton.heightAnchor.constraint(equalToConstant: 30),

      refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor),
      refreshButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
      refreshButton.widthAnchor.constraint(equalToConstant: 36),
      refreshButton.heightAnchor.constraint(equalToConstant: 30),

      statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: addButton.trailingAnchor, constant: 8),
      statusLabel.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -4),
      statusLabel.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),

      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: 6),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

      emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
    ])
    statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Shows the list the keyboard saved, without asking the server — for a page built without a
  /// tap on the button (a rebuild on rotation).
  func showSaved() {
    guard hasFullAccess() else {
      showNoFullAccess()
      return
    }
    guard !hasList, let saved = store.savedList() else { return }
    hasList = true
    apply(saved, empty: Self.emptyText, animated: false)
  }

  /// The clipboard button was tapped: the last list shows at once, the server's list replaces it
  /// quietly when it comes. The loading note shows only when nothing was saved yet.
  func open() {
    guard hasFullAccess() else {
      showNoFullAccess()
      return
    }
    if hasList {
      // Redraws the rows so "5 daq oldin" is current.
      apply(items, empty: Self.emptyText, animated: false, redrawAll: true)
    } else {
      showSaved()
    }
    tableView.setContentOffset(.zero, animated: false)
    refresh()
  }

  private func showNoFullAccess() {
    loadGeneration += 1
    refreshButton.isEnabled = true
    hasList = false
    apply([], empty: "Bufer uchun Gapla klaviaturasiga to'liq kirish kerak.", animated: false)
  }

  /// G53: the header's refresh button — the same server refresh as opening the page.
  @objc private func handleRefreshTapped() {
    guard hasFullAccess() else {
      showNoFullAccess()
      return
    }
    refresh()
  }

  /// Asks the server for the list and puts it in place of the one showing, then saves it.
  private func refresh() {
    loadGeneration += 1
    let generation = loadGeneration
    let showsLoading = !hasList
    if showsLoading {
      emptyLabel.isHidden = true
      setStatus(Self.loadingText, flash: false)
    }
    // A dimmed button says the refresh is under way; the answer (or a newer refresh) restores it.
    refreshButton.isEnabled = false
    client.list { [weak self] result in
      guard let self, generation == self.loadGeneration else { return }
      self.refreshButton.isEnabled = true
      if showsLoading, self.statusLabel.text == Self.loadingText { self.setStatus(nil, flash: false) }
      switch result {
      case .success(let list):
        self.hasList = true
        self.store.saveList(list)
        self.apply(list, empty: Self.emptyText, animated: self.window != nil)
      case .failure(let error):
        if self.hasList {
          self.setStatus(error.message, flash: true)
        } else {
          self.apply([], empty: error.message, animated: false)
        }
      }
    }
  }

  /// Puts `list` on screen. Rows that stay keep their place; only new, gone, moved and changed
  /// rows change — no reload of the whole table, no jump to the top.
  private func apply(_ list: [GaplaClipboardItem], empty: String, animated: Bool, redrawAll: Bool = false) {
    var seen = Set<Int>()
    let list = list.filter { seen.insert($0.id).inserted } // the table needs each id once
    var before: [Int: GaplaClipboardItem] = [:]
    for item in items { before[item.id] = item }
    items = list
    var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
    snapshot.appendSections([0])
    snapshot.appendItems(list.map { $0.id })
    let redraw = list.filter { item in
      guard let old = before[item.id] else { return false }
      return redrawAll || old != item
    }.map { $0.id }
    if !redraw.isEmpty { snapshot.reconfigureItems(redraw) }
    dataSource.apply(snapshot, animatingDifferences: animated)
    emptyLabel.text = empty
    emptyLabel.isHidden = !list.isEmpty
  }

  /// A short note on the right of the add button; `flash` clears it after 1.6 s.
  private func setStatus(_ text: String?, flash: Bool) {
    statusTimer?.invalidate()
    statusTimer = nil
    statusLabel.text = text
    guard flash, text != nil else { return }
    let timer = Timer(timeInterval: 1.6, repeats: false) { [weak self] _ in
      self?.statusLabel.text = nil
    }
    RunLoop.main.add(timer, forMode: .common)
    statusTimer = timer
  }

  // MARK: Actions

  @objc private func handleAddTapped() {
    onKeyClick?()
    guard hasFullAccess() else {
      setStatus("To'liq kirish kerak", flash: true)
      return
    }
    let pasteboard = UIPasteboard.general
    guard pasteboard.hasStrings,
          let text = pasteboard.string,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      setStatus("Buferda matn yo'q", flash: true)
      return
    }
    guard text.unicodeScalars.count <= GaplaClipboardClient.maxCharacters else {
      setStatus(GaplaClipboardError.tooLarge.message, flash: true)
      return
    }
    let secret = pasteboard.types.contains { Self.secretTypes.contains($0) }
    let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    setStatus("Yuborilmoqda…", flash: false)
    client.add(text: text, device: device, secret: secret) { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let isNew):
        self.refresh()
        self.setStatus(isNew ? "Qo'shildi" : "Bor edi, tepaga chiqdi", flash: true)
      case .failure(let error):
        self.setStatus(error.message, flash: true)
      }
    }
  }

  /// A full text fetched before is copied at once; otherwise it is fetched once and kept.
  private func copy(_ item: GaplaClipboardItem) {
    onKeyClick?()
    if let text = store.fullText(for: item) {
      UIPasteboard.general.string = text
      setStatus("Nusxalandi", flash: true)
      return
    }
    setStatus("Olinmoqda…", flash: false)
    client.fullText(id: item.id) { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let text):
        self.store.storeFullText(text, for: item)
        UIPasteboard.general.string = text
        self.setStatus("Nusxalandi", flash: true)
      case .failure(.notFound):
        self.setStatus(GaplaClipboardError.notFound.message, flash: true)
        self.refresh()
      case .failure(let error):
        self.setStatus(error.message, flash: true)
      }
    }
  }

  private func togglePin(_ item: GaplaClipboardItem) {
    onKeyClick?()
    client.setPinned(id: item.id, pinned: !item.qadalgan) { [weak self] result in
      guard let self else { return }
      switch result {
      case .success:
        self.refresh()
        self.setStatus(item.qadalgan ? "Qadash olindi" : "Qadaldi", flash: true)
      case .failure(let error):
        self.setStatus(error.message, flash: true)
        if case .notFound = error { self.refresh() }
      }
    }
  }

  private func delete(_ item: GaplaClipboardItem) {
    onKeyClick?()
    client.delete(id: item.id) { [weak self] result in
      guard let self else { return }
      switch result {
      case .success, .failure(.notFound):
        // A list asked for before the delete would bring the row back.
        self.loadGeneration += 1
        let remaining = self.items.filter { $0.id != item.id }
        self.store.saveList(remaining)
        self.apply(remaining, empty: "Bufer bo'sh.", animated: true)
        self.setStatus("O'chirildi", flash: true)
      case .failure(let error):
        self.setStatus(error.message, flash: true)
      }
    }
  }

  // MARK: Table

  private func configure(_ cell: GaplaClipboardCell, with item: GaplaClipboardItem) {
    cell.configure(
      preview: Self.preview(item),
      detail: Self.detail(item),
      pinned: item.qadalgan,
      secret: item.maxfiy,
      background: rowBackground,
      textColor: textColor,
      accent: accent
    )
    cell.onPin = { [weak self] in self?.togglePin(item) }
    cell.onDelete = { [weak self] in self?.delete(item) }
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard let id = dataSource.itemIdentifier(for: indexPath),
          let item = items.first(where: { $0.id == id })
    else { return }
    copy(item)
  }

  /// One line: line breaks and runs of spaces become single spaces. A secret copy is shown
  /// exactly as the server masks it (owner chose [so'zlari: bilim/gapla-goyalar-royxati.md], 2026-11-11: `●●●●●●●●`).
  private static func preview(_ item: GaplaClipboardItem) -> String {
    if item.maxfiy { return item.boshi }
    let flat = item.boshi
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return item.uzunlik > item.boshi.unicodeScalars.count ? flat + "…" : flat
  }

  /// "iPhone · 5 daq oldin · 1240 belgi" (owner's ask: which device, when). A secret copy shows
  /// "maxfiy" instead of its length, which would tell a password's length.
  private static func detail(_ item: GaplaClipboardItem) -> String {
    let size = item.maxfiy ? "maxfiy" : "\(item.uzunlik) belgi"
    return [item.qurilma.isEmpty ? "?" : item.qurilma, ago(item.vaqt), size].joined(separator: " · ")
  }

  private static func ago(_ unixTime: Double) -> String {
    let seconds = max(0, Date().timeIntervalSince1970 - unixTime)
    switch seconds {
    case ..<60: return "hozir"
    case ..<3600: return "\(Int(seconds / 60)) daq oldin"
    case ..<86_400: return "\(Int(seconds / 3600)) soat oldin"
    default: return "\(Int(seconds / 86_400)) kun oldin"
    }
  }
}

private final class GaplaClipboardCell: UITableViewCell {
  static let reuseIdentifier = "GaplaClipboardCell"

  var onPin: (() -> Void)?
  var onDelete: (() -> Void)?

  private let card = UIView()
  private let previewLabel = UILabel()
  private let detailLabel = UILabel()
  private let pinButton = UIButton(type: .system)
  private let deleteButton = UIButton(type: .system)

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    backgroundColor = .clear
    contentView.backgroundColor = .clear
    selectionStyle = .none

    card.layer.cornerRadius = 8
    card.layer.cornerCurve = .continuous
    card.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(card)

    previewLabel.font = UIFont.systemFont(ofSize: 15)
    previewLabel.lineBreakMode = .byTruncatingTail
    detailLabel.font = UIFont.systemFont(ofSize: 12)
    detailLabel.textColor = .secondaryLabel
    detailLabel.lineBreakMode = .byTruncatingTail
    [previewLabel, detailLabel].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      card.addSubview($0)
    }

    let symbols = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
    pinButton.setPreferredSymbolConfiguration(symbols, forImageIn: .normal)
    pinButton.addTarget(self, action: #selector(handlePin), for: .touchUpInside)
    deleteButton.setPreferredSymbolConfiguration(symbols, forImageIn: .normal)
    deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
    deleteButton.accessibilityLabel = "O'chirish"
    deleteButton.addTarget(self, action: #selector(handleDelete), for: .touchUpInside)
    [pinButton, deleteButton].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      card.addSubview($0)
    }

    NSLayoutConstraint.activate([
      card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
      card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),

      deleteButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -2),
      deleteButton.centerYAnchor.constraint(equalTo: card.centerYAnchor),
      deleteButton.widthAnchor.constraint(equalToConstant: 40),
      deleteButton.heightAnchor.constraint(equalTo: card.heightAnchor),

      pinButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor),
      pinButton.centerYAnchor.constraint(equalTo: card.centerYAnchor),
      pinButton.widthAnchor.constraint(equalToConstant: 40),
      pinButton.heightAnchor.constraint(equalTo: card.heightAnchor),

      previewLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
      previewLabel.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -4),
      previewLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 5),

      detailLabel.leadingAnchor.constraint(equalTo: previewLabel.leadingAnchor),
      detailLabel.trailingAnchor.constraint(equalTo: previewLabel.trailingAnchor),
      detailLabel.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 1),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    onPin = nil
    onDelete = nil
  }

  func configure(
    preview: String, detail: String, pinned: Bool, secret: Bool,
    background: UIColor, textColor: UIColor, accent: UIColor
  ) {
    card.backgroundColor = background
    previewLabel.textColor = textColor
    if secret, let lock = UIImage(
      systemName: "lock.fill",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
    ) {
      // A small lock before the masked text; its colour follows light/dark when the row is redrawn.
      let attachment = NSTextAttachment()
      attachment.image = lock.withTintColor(
        UIColor.secondaryLabel.resolvedColor(with: traitCollection),
        renderingMode: .alwaysOriginal
      )
      let line = NSMutableAttributedString(attachment: attachment)
      line.append(NSAttributedString(string: " " + preview))
      previewLabel.attributedText = line
    } else {
      previewLabel.attributedText = nil
      previewLabel.text = preview
    }
    detailLabel.text = detail
    pinButton.setImage(UIImage(systemName: pinned ? "pin.fill" : "pin"), for: .normal)
    pinButton.tintColor = pinned ? accent : textColor
    pinButton.accessibilityLabel = pinned ? "Qadashni olish" : "Qadash"
    deleteButton.tintColor = textColor
    accessibilityLabel = preview
    accessibilityHint = "Nusxalash uchun ikki marta bosing."
  }

  @objc private func handlePin() { onPin?() }
  @objc private func handleDelete() { onDelete?() }
}
