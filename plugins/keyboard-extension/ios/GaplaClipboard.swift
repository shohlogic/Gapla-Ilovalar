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
  /// G73: only in a search answer, when the words lie past `boshi` — about 200 characters around them, «…» at the cut
  /// edges. Shown in `boshi`'s place.
  var parcha: String? = nil

  func pinned(_ value: Bool) -> GaplaClipboardItem {
    GaplaClipboardItem(
      id: id, boshi: boshi, uzunlik: uzunlik, qurilma: qurilma, vaqt: vaqt, qadalgan: value, maxfiy: maxfiy,
      parcha: parcha
    )
  }
}

/// Gapla (G73, owner 2026-11-23: [so'zlari: bilim/gapla-goyalar-royxati.md], chose «Serverdagi hammasi»): the
/// clipboard search. The server searches every copy of the last 3 days in full; the keyboard filters the rows on hand
/// at once while it waits. The rules are the server's and the computer's (gaplaBuferQidiruv.js): all the words, in any
/// order; letter case and the apostrophe kind (' ʻ ‘ ’) do not matter; a secret copy is never found.
enum GaplaBuferQidiruv {
  /// The server takes a query up to 200 characters.
  static let maxLength = 200
  /// The server is asked once typing pauses this long.
  static let delay: TimeInterval = 0.25

  private static let apostrophes: Set<Character> = ["ʻ", "ʼ", "‘", "’", "`", "´", "ʹ"]

  /// The first 200 characters (Python `len`, i.e. Unicode scalars, as the server counts).
  static func limited(_ query: String) -> String {
    String(String.UnicodeScalarView(query.unicodeScalars.prefix(maxLength)))
  }

  static func normal(_ text: String) -> String {
    String(text.map { apostrophes.contains($0) ? "'" : $0 }).lowercased()
  }

  static func words(_ query: String) -> [String] {
    normal(limited(query)).split(whereSeparator: { $0.isWhitespace }).map(String.init)
  }

  /// The rows on hand, filtered at once by what shows of them (the start, or the excerpt); secret ones never.
  static func filter(_ items: [GaplaClipboardItem], query: String) -> [GaplaClipboardItem] {
    let words = words(query)
    guard !words.isEmpty else { return items }
    return items.filter { item in
      guard !item.maxfiy else { return false }
      let text = normal(item.boshi + " " + (item.parcha ?? ""))
      return words.allSatisfy { text.contains($0) }
    }
  }

  /// Where the words are in `text`, as NSString ranges. None when folding the case changed the text's length (a few
  /// letters, as Turkish İ): the row then shows unmarked rather than marked in the wrong place.
  static func matches(in text: String, query: String) -> [NSRange] {
    let words = words(query)
    let original = text as NSString
    let folded = normal(text) as NSString
    guard !words.isEmpty, folded.length == original.length else { return [] }
    var ranges: [NSRange] = []
    for word in words {
      var from = 0
      while from < folded.length {
        let found = folded.range(of: word, options: .literal, range: NSRange(location: from, length: folded.length - from))
        guard found.location != NSNotFound, found.length > 0 else { break }
        ranges.append(found)
        from = found.location + 1
      }
    }
    return ranges
  }
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

  /// G73: `GET /v1/bufer?q=<so'zlar>&soni=50` (bilim/gapla-bufer-reja.md, «Server qismi») — the same rows as the list,
  /// with `parcha` when the words lie past the start. The task is returned so that a newer search can cancel it.
  @discardableResult
  func search(
    _ query: String,
    completion: @escaping (Result<[GaplaClipboardItem], GaplaClipboardError>) -> Void
  ) -> URLSessionDataTask? {
    let asked = GaplaBuferQidiruv.limited(query.trimmingCharacters(in: .whitespacesAndNewlines))
    return send("GET", query: [URLQueryItem(name: "q", value: asked), URLQueryItem(name: "soni", value: "50")]) { result in
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
  @discardableResult
  private func send(
    _ method: String,
    path: String? = nil,
    query: [URLQueryItem]? = nil,
    body: [String: Any]? = nil,
    completion: @escaping (Result<Data, GaplaClipboardError>) -> Void
  ) -> URLSessionDataTask? {
    guard let key = serverKey() else {
      DispatchQueue.main.async { completion(.failure(.noKey)) }
      return nil
    }
    let url = path.map { Self.baseURL.appendingPathComponent($0) } ?? Self.baseURL
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.queryItems = query
    // URLComponents leaves «+» as it is, and the server would read it as a space (G73: a search for «C++»).
    if let encoded = components?.percentEncodedQuery {
      components?.percentEncodedQuery = encoded.replacingOccurrences(of: "+", with: "%2B")
    }
    guard let requestURL = components?.url else {
      DispatchQueue.main.async { completion(.failure(.server)) }
      return nil
    }
    var request = URLRequest(url: requestURL)
    request.httpMethod = method
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.httpBody = try? JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let task = session.dataTask(with: request) { data, response, error in
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
    }
    task.resume()
    return task
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

/// The clipboard page, in the letter rows' and the bottom row's place: ← (back to the letters), the add button and a
/// status line on top, the list below — newest first, pinned ones above; each row has the
/// text's start, where and when it was copied, a pin and a delete button. Tap a row to copy it.
///
/// G73 (owner 2026-11-23, chose «Tarjimondek»): a search field sits between the header and the list. A tap on it opens
/// the same panel in its `.search` mode above the toolbar, as the translator opens: the field and the rows found on
/// top, the keys below, which type into the field (an extension cannot bring up the system keyboard). While the field
/// is being typed in, the rows on hand are filtered at once and the server's answer replaces them 0.25 s after typing
/// pauses; a word found is marked; an empty field shows the ordinary list. Like the computer's Option+B window
/// (GaplaBuferOverlay.jsx), a copy closes the search.
final class GaplaClipboardPanel: UIView, UITableViewDelegate {
  enum Mode { case page, search }

  /// The search panel's height above the toolbar — the translator's, so the keyboard grows the same way: the field and
  /// two rows.
  static let searchHeight: CGFloat = 150

  /// Plays the key click (the controller owns the input-click sound).
  var onKeyClick: (() -> Void)?
  /// Page: the search field was tapped.
  var onSearchTap: (() -> Void)?
  /// Page: ← — back to the letters. Owner 2026-11-24 («Qator ketsin»): the bottom row (ABC, emoji, language) has no
  /// use on the clipboard page, so the page takes its place and ← goes back, as on Android (ClipboardInputLayout).
  var onBack: (() -> Void)?
  /// Search: ✕ — back to the clipboard page.
  var onSearchClose: (() -> Void)?
  /// Search: the copy chosen is on the iPhone clipboard.
  var onSearchCopied: (() -> Void)?
  /// Search: ✕ in the field — the controller keeps the text the keys type, so it clears it.
  var onSearchClear: (() -> Void)?

  // Pasteboard types password managers set on a secret copy (nspasteboard.org convention and
  // 1Password's own); reading the types does not read the text.
  private static let secretTypes: Set<String> = ["org.nspasteboard.ConcealedType", "com.agilebits.onepassword"]
  private static let rowHeight: CGFloat = 50
  private static let loadingText = "Yuklanmoqda…"
  private static let emptyText = "Bufer bo'sh. Biror matnni nusxalang va «Hozirgi nusxani qo'sh»ni bosing."
  /// The computer's words (GaplaBuferOverlay.jsx).
  private static let searchPlaceholder = "Qidirish — 3 kunlik hamma nusxa ichidan"
  private static let notFoundNote = "3 kunlik hamma nusxa ichidan izlandi. Maxfiy nusxalar (parollar) qidiruvda chiqmaydi."
  /// Below this the page (landscape phone, 133 pt with the bottom row's place) keeps its list rows and shows a search
  /// icon in the header instead of the field row; a portrait phone's page is 186 pt and more.
  private static let fieldRowMinPageHeight: CGFloat = 150
  /// A marked word further in than this starts the line a little before it, so it shows on the row's one line.
  private static let leadKeep = 16

  let mode: Mode
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

  // G73 search state (mode .search).
  private var query = ""
  /// The ordinary list the search opened with: shown for an empty field, filtered at once while the server is asked.
  private var baseList: [GaplaClipboardItem] = []
  /// The server's last answer and the field's text it answers.
  private var found: (query: String, items: [GaplaClipboardItem])?
  private var searchError: GaplaClipboardError?
  /// Deleted during this search: a late answer does not bring them back.
  private var removedIDs = Set<Int>()
  private var searchTimer: Timer?
  private var searchTask: URLSessionDataTask?
  private var searchGeneration = 0

  private let backButton = UIButton(type: .system)
  private let addButton = UIButton(type: .system)
  /// Gapla (G53, owner 2026-11-12: [so'zlari: bilim/gapla-goyalar-royxati.md]): the same refresh as on opening, at the header's right end with
  /// the same circular-arrow icon as the Android panel (ClipboardInputLayout, Icons.Default.Refresh).
  private let refreshButton = UIButton(type: .system)
  private let statusLabel = UILabel()
  /// Page: looks like a field; a tap opens the search.
  private let searchField = UIControl()
  /// Page on a short keyboard: the search as an icon in the header.
  private let searchIconButton = UIButton(type: .system)
  /// Search: the field the keys type into, its ✕ (clear), and the panel's ✕ (close).
  private let inputBox = UIView()
  private let queryLabel = UILabel()
  private let clearButton = UIButton(type: .system)
  private let closeButton = UIButton(type: .system)
  /// Search: notes (pinned, deleted, an error) float over the rows' bottom for 1.6 s.
  private let toastView = UIView()
  private let tableView = UITableView(frame: .zero, style: .plain)
  private let emptyLabel = UILabel()

  init(
    mode: Mode = .page,
    pageHeight: CGFloat = 0,
    client: GaplaClipboardClient,
    hasFullAccess: @escaping () -> Bool,
    rowBackground: UIColor,
    textColor: UIColor,
    accent: UIColor
  ) {
    self.mode = mode
    self.client = client
    self.hasFullAccess = hasFullAccess
    self.rowBackground = rowBackground
    self.textColor = textColor
    self.accent = accent
    super.init(frame: .zero)

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

    emptyLabel.textAlignment = .center
    emptyLabel.numberOfLines = 0
    emptyLabel.isHidden = true
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(emptyLabel)

    NSLayoutConstraint.activate([
      tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
      tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

      emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
      emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
    ])

    switch mode {
    case .page: buildPageHeader(fieldRow: pageHeight <= 0 || pageHeight >= Self.fieldRowMinPageHeight)
    case .search: buildSearchRow()
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func buildPageHeader(fieldRow: Bool) {
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

    configureHeaderIcon(backButton, systemImage: "arrow.left", label: "Harflarga qaytish")
    backButton.addTarget(self, action: #selector(handleBackTapped), for: .touchUpInside)

    configureHeaderIcon(refreshButton, systemImage: "arrow.clockwise", label: "Yangilash")
    refreshButton.addTarget(self, action: #selector(handleRefreshTapped), for: .touchUpInside)

    statusLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
    statusLabel.textColor = .secondaryLabel
    statusLabel.textAlignment = .right
    statusLabel.adjustsFontSizeToFitWidth = true
    statusLabel.minimumScaleFactor = 0.8
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(statusLabel)
    statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    NSLayoutConstraint.activate([
      backButton.leadingAnchor.constraint(equalTo: leadingAnchor),
      backButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
      backButton.widthAnchor.constraint(equalToConstant: 36),
      backButton.heightAnchor.constraint(equalToConstant: 30),

      addButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),
      addButton.topAnchor.constraint(equalTo: topAnchor),
      addButton.heightAnchor.constraint(equalToConstant: 30),

      refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor),
      refreshButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
      refreshButton.widthAnchor.constraint(equalToConstant: 36),
      refreshButton.heightAnchor.constraint(equalToConstant: 30),

      statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: addButton.trailingAnchor, constant: 8),
      statusLabel.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
    ])

    guard fieldRow else {
      configureHeaderIcon(searchIconButton, systemImage: "magnifyingglass", label: "Buferdan qidirish")
      searchIconButton.addTarget(self, action: #selector(handleSearchFieldTapped), for: .touchUpInside)
      NSLayoutConstraint.activate([
        searchIconButton.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor),
        searchIconButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
        searchIconButton.widthAnchor.constraint(equalToConstant: 36),
        searchIconButton.heightAnchor.constraint(equalToConstant: 30),
        statusLabel.trailingAnchor.constraint(equalTo: searchIconButton.leadingAnchor, constant: -4),
        tableView.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: 6),
      ])
      return
    }

    searchField.backgroundColor = rowBackground
    searchField.layer.cornerRadius = 8
    searchField.layer.cornerCurve = .continuous
    searchField.isAccessibilityElement = true
    searchField.accessibilityLabel = "Buferdan qidirish"
    searchField.accessibilityTraits = .button
    searchField.addTarget(self, action: #selector(handleSearchFieldTapped), for: .touchUpInside)
    searchField.addTarget(self, action: #selector(handleSearchFieldPressed), for: [.touchDown, .touchDragEnter])
    searchField.addTarget(
      self, action: #selector(handleSearchFieldReleased), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
    )
    searchField.translatesAutoresizingMaskIntoConstraints = false
    addSubview(searchField)

    let icon = makeSearchIcon()
    searchField.addSubview(icon)
    let hint = UILabel()
    hint.text = Self.searchPlaceholder
    hint.font = UIFont.systemFont(ofSize: 14)
    hint.textColor = .placeholderText
    hint.lineBreakMode = .byTruncatingTail
    hint.translatesAutoresizingMaskIntoConstraints = false
    searchField.addSubview(hint)

    NSLayoutConstraint.activate([
      statusLabel.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -4),

      searchField.leadingAnchor.constraint(equalTo: leadingAnchor),
      searchField.trailingAnchor.constraint(equalTo: trailingAnchor),
      searchField.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: 5),
      searchField.heightAnchor.constraint(equalToConstant: 30),

      icon.leadingAnchor.constraint(equalTo: searchField.leadingAnchor, constant: 10),
      icon.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
      hint.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
      hint.trailingAnchor.constraint(lessThanOrEqualTo: searchField.trailingAnchor, constant: -10),
      hint.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),

      tableView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 5),
    ])
  }

  private func buildSearchRow() {
    inputBox.backgroundColor = rowBackground
    inputBox.layer.cornerRadius = 10
    inputBox.layer.cornerCurve = .continuous
    inputBox.layer.borderWidth = 1.5
    inputBox.layer.borderColor = accent.resolvedColor(with: traitCollection).cgColor
    inputBox.translatesAutoresizingMaskIntoConstraints = false
    addSubview(inputBox)

    let icon = makeSearchIcon()
    inputBox.addSubview(icon)

    queryLabel.font = UIFont.systemFont(ofSize: 16)
    queryLabel.numberOfLines = 1
    queryLabel.translatesAutoresizingMaskIntoConstraints = false
    inputBox.addSubview(queryLabel)

    clearButton.setImage(
      UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)),
      for: .normal
    )
    clearButton.tintColor = .tertiaryLabel
    clearButton.accessibilityLabel = "Qidiruvni tozalash"
    clearButton.addTarget(self, action: #selector(handleClearTapped), for: .touchUpInside)
    clearButton.translatesAutoresizingMaskIntoConstraints = false
    inputBox.addSubview(clearButton)

    // The translator's ✕ (GaplaTarjimonPanel): a 44 pt circle.
    closeButton.setImage(
      UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)),
      for: .normal
    )
    closeButton.tintColor = textColor
    closeButton.backgroundColor = rowBackground
    closeButton.layer.cornerRadius = 22
    closeButton.accessibilityLabel = "Qidiruvni yopish"
    closeButton.addTarget(self, action: #selector(handleCloseTapped), for: .touchUpInside)
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    addSubview(closeButton)

    toastView.backgroundColor = textColor.withAlphaComponent(0.88)
    toastView.layer.cornerRadius = 14
    toastView.layer.cornerCurve = .continuous
    toastView.isHidden = true
    toastView.isUserInteractionEnabled = false
    toastView.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
    statusLabel.textColor = .systemBackground
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 2
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    toastView.addSubview(statusLabel)
    addSubview(toastView)

    NSLayoutConstraint.activate([
      inputBox.leadingAnchor.constraint(equalTo: leadingAnchor),
      inputBox.topAnchor.constraint(equalTo: topAnchor),
      inputBox.heightAnchor.constraint(equalToConstant: 44),
      inputBox.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),

      closeButton.trailingAnchor.constraint(equalTo: trailingAnchor),
      closeButton.centerYAnchor.constraint(equalTo: inputBox.centerYAnchor),
      closeButton.widthAnchor.constraint(equalToConstant: 44),
      closeButton.heightAnchor.constraint(equalToConstant: 44),

      icon.leadingAnchor.constraint(equalTo: inputBox.leadingAnchor, constant: 11),
      icon.centerYAnchor.constraint(equalTo: inputBox.centerYAnchor),
      queryLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
      queryLabel.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -2),
      queryLabel.centerYAnchor.constraint(equalTo: inputBox.centerYAnchor),

      clearButton.trailingAnchor.constraint(equalTo: inputBox.trailingAnchor, constant: -2),
      clearButton.centerYAnchor.constraint(equalTo: inputBox.centerYAnchor),
      clearButton.widthAnchor.constraint(equalToConstant: 36),
      clearButton.heightAnchor.constraint(equalToConstant: 44),

      tableView.topAnchor.constraint(equalTo: inputBox.bottomAnchor, constant: 6),

      toastView.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
      toastView.bottomAnchor.constraint(equalTo: tableView.bottomAnchor, constant: -6),
      toastView.widthAnchor.constraint(lessThanOrEqualTo: tableView.widthAnchor, constant: -24),
      statusLabel.leadingAnchor.constraint(equalTo: toastView.leadingAnchor, constant: 14),
      statusLabel.trailingAnchor.constraint(equalTo: toastView.trailingAnchor, constant: -14),
      statusLabel.topAnchor.constraint(equalTo: toastView.topAnchor, constant: 6),
      statusLabel.bottomAnchor.constraint(equalTo: toastView.bottomAnchor, constant: -6),
    ])
    refreshQueryRow()
  }

  private func makeSearchIcon() -> UIImageView {
    let icon = UIImageView(image: UIImage(
      systemName: "magnifyingglass",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
    ))
    icon.tintColor = .secondaryLabel
    icon.isUserInteractionEnabled = false
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.setContentHuggingPriority(.required, for: .horizontal)
    return icon
  }

  @objc private func handleBackTapped() {
    onBack?()
  }

  private func configureHeaderIcon(_ button: UIButton, systemImage: String, label: String) {
    var config = UIButton.Configuration.plain()
    config.image = UIImage(systemName: systemImage)
    config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    config.baseForegroundColor = textColor
    config.contentInsets = .zero
    button.configuration = config
    button.accessibilityLabel = label
    button.translatesAutoresizingMaskIntoConstraints = false
    addSubview(button)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    // A layer colour does not follow light and dark by itself.
    if mode == .search {
      inputBox.layer.borderColor = accent.resolvedColor(with: traitCollection).cgColor
    }
  }

  /// The list showing on the page, for the search to start from; nil before one has shown.
  var listShown: [GaplaClipboardItem]? { hasList ? items : nil }

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
      // Redraws the rows so "5 daq oldin" is current. The saved list, when there is one, also has what a search
      // deleted (G73).
      apply(store.savedList() ?? items, empty: Self.emptyText, animated: false, redrawAll: true)
    } else {
      showSaved()
    }
    tableView.setContentOffset(.zero, animated: false)
    refresh()
  }

  /// A short note in the status place, cleared after 1.6 s.
  func showNote(_ text: String) {
    setStatus(text, flash: true)
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
    guard mode == .page else { return }
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
  /// rows change — no reload of the whole table, no jump to the top. `note` goes in small print under `empty`.
  private func apply(
    _ list: [GaplaClipboardItem], empty: String, note: String? = nil, animated: Bool, redrawAll: Bool = false
  ) {
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

    let centred = NSMutableParagraphStyle()
    centred.alignment = .center
    let message = NSMutableAttributedString(string: empty, attributes: [
      .font: UIFont.systemFont(ofSize: 14, weight: note == nil ? .regular : .semibold),
      .foregroundColor: note == nil ? UIColor.secondaryLabel : textColor,
      .paragraphStyle: centred,
    ])
    if let note {
      message.append(NSAttributedString(string: "\n" + note, attributes: [
        .font: UIFont.systemFont(ofSize: 12),
        .foregroundColor: UIColor.secondaryLabel,
        .paragraphStyle: centred,
      ]))
    }
    emptyLabel.attributedText = message
    emptyLabel.isHidden = !list.isEmpty
  }

  /// A short note — on the page right of the add button, in the search over the rows; `flash` clears it after 1.6 s.
  private func setStatus(_ text: String?, flash: Bool) {
    statusTimer?.invalidate()
    statusTimer = nil
    statusLabel.text = text
    if mode == .search { toastView.isHidden = text == nil }
    guard flash, text != nil else { return }
    let timer = Timer(timeInterval: 1.6, repeats: false) { [weak self] _ in
      self?.setStatus(nil, flash: false)
    }
    RunLoop.main.add(timer, forMode: .common)
    statusTimer = timer
  }

  // MARK: Search (G73)

  /// The search opens with an empty field and the ordinary list — the page's, or the one saved.
  func beginSearch(list: [GaplaClipboardItem]?) {
    endSearch()
    query = ""
    found = nil
    searchError = nil
    removedIDs = []
    baseList = list ?? store.savedList() ?? []
    setStatus(nil, flash: false)
    refreshQueryRow()
    render()
    tableView.setContentOffset(.zero, animated: false)
  }

  /// Nothing asked or waited for any more.
  func endSearch() {
    searchTimer?.invalidate()
    searchTimer = nil
    searchTask?.cancel()
    searchTask = nil
    searchGeneration += 1
  }

  /// What the keys have typed: the rows on hand are filtered at once, the server is asked once typing pauses.
  func setQuery(_ text: String) {
    guard mode == .search else { return }
    query = text
    refreshQueryRow()
    endSearch()
    searchError = nil
    if GaplaBuferQidiruv.words(text).isEmpty {
      found = nil
    } else {
      let timer = Timer(timeInterval: GaplaBuferQidiruv.delay, repeats: false) { [weak self] _ in
        self?.runSearch()
      }
      RunLoop.main.add(timer, forMode: .common)
      searchTimer = timer
    }
    render()
    tableView.setContentOffset(.zero, animated: false)
  }

  /// The return key: the server is asked without waiting.
  func searchNow() {
    guard mode == .search, !GaplaBuferQidiruv.words(query).isEmpty else { return }
    runSearch()
  }

  private func runSearch() {
    endSearch()
    let generation = searchGeneration
    let asked = query
    searchTask = client.search(asked) { [weak self] result in
      guard let self, generation == self.searchGeneration else { return }
      self.searchTask = nil
      switch result {
      case .success(let list):
        self.found = (asked, list.filter { !self.removedIDs.contains($0.id) })
        self.searchError = nil
        self.render()
      case .failure(let error):
        // The rows filtered on hand stay; the note says why nothing more came.
        self.searchError = error
        self.render()
        if !self.items.isEmpty { self.setStatus(error.message, flash: true) }
      }
    }
  }

  private func render() {
    let words = GaplaBuferQidiruv.words(query)
    if words.isEmpty {
      apply(baseList.filter { !removedIDs.contains($0.id) }, empty: Self.emptyText, animated: false, redrawAll: true)
      return
    }
    if let found, found.query == query {
      let shown = query.trimmingCharacters(in: .whitespacesAndNewlines)
      apply(found.items, empty: "«\(shown)» topilmadi", note: Self.notFoundNote, animated: false, redrawAll: true)
      return
    }
    // Until the server answers: the last answer and the ordinary list together, so the rows do not jump.
    let pool = found.map { Self.merged($0.items, baseList) } ?? baseList
    let shown = GaplaBuferQidiruv.filter(pool.filter { !removedIDs.contains($0.id) }, query: query)
    apply(shown, empty: searchError?.message ?? "Qidirilmoqda…", animated: false, redrawAll: true)
  }

  /// Pinned first, then the latest — the server's order.
  private static func merged(_ first: [GaplaClipboardItem], _ second: [GaplaClipboardItem]) -> [GaplaClipboardItem] {
    let seen = Set(first.map { $0.id })
    return (first + second.filter { !seen.contains($0.id) }).sorted { a, b in
      if a.qadalgan != b.qadalgan { return a.qadalgan }
      return a.vaqt > b.vaqt
    }
  }

  /// The typed text and an accent caret at its end, as the translator shows it; the placeholder after the caret.
  private func refreshQueryRow() {
    let shown = NSMutableAttributedString()
    let caret = NSAttributedString(string: "|", attributes: [.foregroundColor: accent])
    if query.isEmpty {
      shown.append(caret)
      shown.append(NSAttributedString(string: Self.searchPlaceholder, attributes: [.foregroundColor: UIColor.placeholderText]))
      queryLabel.lineBreakMode = .byTruncatingTail
    } else {
      shown.append(NSAttributedString(string: query, attributes: [.foregroundColor: textColor]))
      shown.append(caret)
      // The end being typed stays in sight.
      queryLabel.lineBreakMode = .byTruncatingHead
    }
    queryLabel.attributedText = shown
    queryLabel.accessibilityLabel = query.isEmpty ? Self.searchPlaceholder : query
    clearButton.isHidden = query.isEmpty
  }

  @objc private func handleSearchFieldPressed() { searchField.alpha = 0.6 }
  @objc private func handleSearchFieldReleased() { searchField.alpha = 1 }

  @objc private func handleSearchFieldTapped() {
    onKeyClick?()
    guard hasFullAccess() else {
      setStatus("To'liq kirish kerak", flash: true)
      return
    }
    onSearchTap?()
  }

  /// ✕ in the field: the text goes, the ordinary list comes back; the keys keep typing here.
  @objc private func handleClearTapped() {
    onKeyClick?()
    onSearchClear?()
  }

  @objc private func handleCloseTapped() {
    onKeyClick?()
    onSearchClose?()
  }

  /// G73: a change made in the search (pinned) shows in its rows at once, without asking again.
  private func replaceInSearch(_ item: GaplaClipboardItem) {
    baseList = baseList.map { $0.id == item.id ? item : $0 }
    if let found {
      self.found = (found.query, found.items.map { $0.id == item.id ? item : $0 })
    }
    render()
  }

  private func dropInSearch(_ id: Int) {
    removedIDs.insert(id)
    if let saved = store.savedList(), saved.contains(where: { $0.id == id }) {
      store.saveList(saved.filter { $0.id != id })
    }
    render()
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
      copied()
      return
    }
    setStatus("Olinmoqda…", flash: false)
    client.fullText(id: item.id) { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let text):
        self.store.storeFullText(text, for: item)
        UIPasteboard.general.string = text
        self.copied()
      case .failure(.notFound):
        self.setStatus(GaplaClipboardError.notFound.message, flash: true)
        if self.mode == .search { self.dropInSearch(item.id) } else { self.refresh() }
      case .failure(let error):
        self.setStatus(error.message, flash: true)
      }
    }
  }

  private func copied() {
    if mode == .search {
      setStatus(nil, flash: false)
      onSearchCopied?()
    } else {
      setStatus("Nusxalandi", flash: true)
    }
  }

  private func togglePin(_ item: GaplaClipboardItem) {
    onKeyClick?()
    client.setPinned(id: item.id, pinned: !item.qadalgan) { [weak self] result in
      guard let self else { return }
      switch result {
      case .success:
        if self.mode == .search { self.replaceInSearch(item.pinned(!item.qadalgan)) } else { self.refresh() }
        self.setStatus(item.qadalgan ? "Qadash olindi" : "Qadaldi", flash: true)
      case .failure(let error):
        self.setStatus(error.message, flash: true)
        if case .notFound = error {
          if self.mode == .search { self.dropInSearch(item.id) } else { self.refresh() }
        }
      }
    }
  }

  private func delete(_ item: GaplaClipboardItem) {
    onKeyClick?()
    client.delete(id: item.id) { [weak self] result in
      guard let self else { return }
      switch result {
      case .success, .failure(.notFound):
        if self.mode == .search {
          self.dropInSearch(item.id)
        } else {
          // A list asked for before the delete would bring the row back.
          self.loadGeneration += 1
          let remaining = self.items.filter { $0.id != item.id }
          self.store.saveList(remaining)
          self.apply(remaining, empty: "Bufer bo'sh.", animated: true)
        }
        self.setStatus("O'chirildi", flash: true)
      case .failure(let error):
        self.setStatus(error.message, flash: true)
      }
    }
  }

  // MARK: Table

  private func configure(_ cell: GaplaClipboardCell, with item: GaplaClipboardItem) {
    let searching = mode == .search && !GaplaBuferQidiruv.words(query).isEmpty
    let line = searching ? Self.searchPreview(item, query: query) : (text: Self.preview(item), marks: [])
    cell.configure(
      preview: line.text,
      marks: line.marks,
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

  /// One line: line breaks and runs of spaces become single spaces.
  private static func flat(_ text: String) -> String {
    text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
  }

  /// A secret copy is shown exactly as the server masks it (owner chose [so'zlari: bilim/gapla-goyalar-royxati.md], 2026-11-11: `●●●●●●●●`).
  private static func preview(_ item: GaplaClipboardItem) -> String {
    if item.maxfiy { return item.boshi }
    let flat = flat(item.boshi)
    return item.uzunlik > item.boshi.unicodeScalars.count ? flat + "…" : flat
  }

  /// G73: the server's excerpt in the start's place, the words found marked. A word deep in the line moves the line's
  /// start to a little before it («…» in front), so it shows on the row's one line.
  private static func searchPreview(_ item: GaplaClipboardItem, query: String) -> (text: String, marks: [NSRange]) {
    let text: String
    if let parcha = item.parcha, !parcha.isEmpty {
      text = flat(parcha)
    } else {
      text = preview(item)
    }
    let marks = GaplaBuferQidiruv.matches(in: text, query: query)
    guard let first = marks.map({ $0.location }).min(), first > leadKeep else { return (text, marks) }
    let ns = text as NSString
    var start = first - leadKeep
    // From the start of a word when one begins near.
    let space = ns.rangeOfCharacter(from: .whitespaces, options: [], range: NSRange(location: start, length: first - start))
    if space.location != NSNotFound, space.location + 1 < first { start = space.location + 1 }
    start = ns.rangeOfComposedCharacterSequence(at: start).location
    let shift = start - 1 // «…» is one UTF-16 unit
    let cut = "…" + ns.substring(from: start)
    return (cut, marks.map { NSRange(location: $0.location - shift, length: $0.length) })
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

  /// `marks` (G73): the words a search found, as NSString ranges of `preview` — on the computer's look, a soft accent
  /// behind them.
  func configure(
    preview: String, marks: [NSRange], detail: String, pinned: Bool, secret: Bool,
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
    } else if !marks.isEmpty {
      let line = NSMutableAttributedString(string: preview, attributes: [
        .font: previewLabel.font ?? UIFont.systemFont(ofSize: 15),
        .foregroundColor: textColor,
      ])
      let markColour = accent.resolvedColor(with: traitCollection).withAlphaComponent(0.28)
      for range in marks where NSMaxRange(range) <= line.length {
        line.addAttribute(.backgroundColor, value: markColour, range: range)
      }
      previewLabel.attributedText = line
    } else {
      previewLabel.attributedText = nil
      previewLabel.text = preview
      previewLabel.textColor = textColor
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
