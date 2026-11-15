import UIKit

// Gapla tarjimoni klaviatura ichida (G56, owner 2026-11-12; 2026-11-15: «shu joydan chiqmasdan turib qilsa
// bo'lmasmidi?», then «hop sinab koraylik, lekin til tanlash va ishlash oson blishi kerak»).
//
// The look follows G67 (owner 2026-11-15: «qaysi tildan qaysi tilga tarjima qilayotganini tushunib bolmayapti … har
// safar standart holatda ozbekchadan ruschaga tarjima qilish tanlangan holatda kelsin»; design: the main window's
// gapla-g67-tarjimon-dizayn/taklif.png): «Qaysi tildan» ⇄ «Qaysi tilga», O'zbekcha → Русский on every opening; a box
// tapped lists the three languages; the same language on both sides swaps the other; the button says where to —
// «Ruschaga tarjima qilish»; the results say it too — «Ruscha — aniq», «Ruscha — sayqallangan».
//
// 文A opens the panel above the keys: the keys, the clipboard and Gapla dictation write into its own text, not the
// field. Nothing but the button translates (G65). The variants then show in the keys' place: «Joylash» types the
// chosen one into the field, «Nusxa» copies it.
//
// Server: `POST <Gapla>/v1/tarjima` with the dictation key the app mirrors into the App Group's Keychain group (the key
// GaplaClipboardClient reads), request `{matn, til}` — the server finds the source language itself — answer `{manba, til, variantlar: [{tur, matn}]}` — as
// Android (GaplaTarjimon.kt). The text is never logged.

struct GaplaTarjimaNatija {
  let manba: String
  let til: String
  let aniq: String
  let silliq: String
}

enum GaplaTarjimonTil: String, CaseIterable {
  case uz, ru, en

  /// Each language in its own name, as the list shows it.
  var name: String {
    switch self {
    case .uz: return "O'zbekcha"
    case .ru: return "Русский"
    case .en: return "English"
    }
  }

  /// In Uzbek, for the result titles: «Ruscha — aniq».
  var uzbekName: String {
    switch self {
    case .uz: return "O'zbekcha"
    case .ru: return "Ruscha"
    case .en: return "Inglizcha"
    }
  }

  /// The button: «Ruschaga tarjima qilish».
  var buttonTitle: String {
    switch self {
    case .uz: return "O'zbekchaga tarjima qilish"
    case .ru: return "Ruschaga tarjima qilish"
    case .en: return "Inglizchaga tarjima qilish"
    }
  }
}

final class GaplaTarjimonClient {
  static let maxCharacters = 20_000
  private static let url = URL(string: "https://gapla.xaliljonov.uz/v1/tarjima")!

  private let keySource: GaplaClipboardClient
  private let session: URLSession
  private var task: URLSessionDataTask?

  init(accessGroup: String) {
    keySource = GaplaClipboardClient(accessGroup: accessGroup)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 40
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    session = URLSession(configuration: configuration)
  }

  /// Same wording as Android's (GaplaTarjimon.Xato).
  static func message(forStatus status: Int) -> String {
    switch status {
    case 0: return "Internet yo'q yoki server javob bermadi. Qayta urinib ko'ring."
    case 400: return "So'rov noto'g'ri. Matnni tekshirib, qayta urinib ko'ring."
    case 401, 403: return "Gapla kaliti yo'q. Gapla ilovasini bir marta oching."
    case 404: return "Tarjima xizmati hali ishga tushmagan."
    case 413: return "Matn juda uzun: 20 000 belgidan oshmasin."
    case 429: return "So'rov juda ko'p. Birozdan keyin qayta urinib ko'ring."
    default: return "Tarjima chiqmadi, qayta urinib ko'ring."
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }

  /// Calls back on the main queue; a cancelled request never calls back.
  func translate(
    _ text: String,
    from source: GaplaTarjimonTil,
    to target: GaplaTarjimonTil,
    completion: @escaping (Result<GaplaTarjimaNatija, Error>) -> Void
  ) {
    cancel()
    if text.count > Self.maxCharacters {
      completion(.failure(GaplaTarjimonError(status: 413)))
      return
    }
    guard let key = keySource.serverKey() else {
      completion(.failure(GaplaTarjimonError(status: 401)))
      return
    }
    var request = URLRequest(url: Self.url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = try? JSONSerialization.data(
      withJSONObject: ["matn": text, "til": target.rawValue]
    )
    let task = session.dataTask(with: request) { data, response, error in
      if let error = error as NSError?, error.code == NSURLErrorCancelled { return }
      let result: Result<GaplaTarjimaNatija, Error>
      if error != nil {
        result = .failure(GaplaTarjimonError(status: 0))
      } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        result = .failure(GaplaTarjimonError(status: http.statusCode))
      } else if let natija = Self.parse(data) {
        result = .success(natija)
      } else {
        result = .failure(GaplaTarjimonError(status: 502))
      }
      DispatchQueue.main.async { completion(result) }
    }
    self.task = task
    task.resume()
  }

  private static func parse(_ data: Data?) -> GaplaTarjimaNatija? {
    guard let data,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    let variants = object["variantlar"] as? [[String: Any]] ?? []
    func variant(_ kind: String) -> String {
      variants.first { ($0["tur"] as? String) == kind }?["matn"] as? String ?? ""
    }
    let exact = variant("aniq").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? (object["matn"] as? String ?? "")
      : variant("aniq")
    guard !exact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return GaplaTarjimaNatija(
      manba: object["manba"] as? String ?? "",
      til: object["til"] as? String ?? "",
      aniq: exact,
      silliq: variant("silliq")
    )
  }
}

struct GaplaTarjimonError: LocalizedError {
  let status: Int
  var errorDescription: String? { GaplaTarjimonClient.message(forStatus: status) }
}

/// The panel above the keys, three rows: «Qaysi tildan» ⇄ «Qaysi tilga»; the text being translated, its language
/// under it, and «Qo'yish»; ✕ and the button «Ruschaga tarjima qilish». Every target is at least 44 pt (main window's
/// advice, 2026-11-15), and the language row fits an iPhone SE with the names in full.
final class GaplaTarjimonPanel: UIView {
  static let height: CGFloat = 150

  var onClose: (() -> Void)?
  var onTranslate: (() -> Void)?
  var onPaste: (() -> Void)?
  var onClear: (() -> Void)?
  var onKeyClick: (() -> Void)?

  private(set) var source: GaplaTarjimonTil = .uz
  private(set) var target: GaplaTarjimonTil = .ru
  private let accent: UIColor
  private let keyBackground: UIColor
  private let textColor: UIColor

  private let sourceButton = UIButton(type: .custom)
  private let targetButton = UIButton(type: .custom)
  private let swapButton = UIButton(type: .system)
  private let closeButton = UIButton(type: .system)
  private let inputBox = UIView()
  private let textLabel = UILabel()
  private let languageNote = UILabel()
  private let clearButton = UIButton(type: .system)
  private let pasteButton = UIButton(type: .system)
  private let translateButton = UIButton(type: .custom)
  private let spinner = UIActivityIndicatorView(style: .medium)
  private var text = ""
  private var busy = false

  init(accent: UIColor, keyBackground: UIColor, textColor: UIColor) {
    self.accent = accent
    self.keyBackground = keyBackground
    self.textColor = textColor
    super.init(frame: .zero)
    build()
    refresh()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func build() {
    backgroundColor = .clear

    for button in [sourceButton, targetButton] {
      button.translatesAutoresizingMaskIntoConstraints = false
      button.showsMenuAsPrimaryAction = true
      button.layer.cornerRadius = 10
      button.layer.borderWidth = 1.5
      button.layer.borderColor = accent.resolvedColor(with: traitCollection).cgColor
      button.backgroundColor = keyBackground
      button.contentHorizontalAlignment = .leading
      button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 24)
      button.titleLabel?.numberOfLines = 2
      button.titleLabel?.lineBreakMode = .byTruncatingTail
      addSubview(button)
      // ▾: a tap lists the languages.
      let chevron = UIImageView(image: UIImage(systemName: "chevron.down")?.withConfiguration(
        UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
      ))
      chevron.translatesAutoresizingMaskIntoConstraints = false
      chevron.tintColor = textColor.withAlphaComponent(0.6)
      chevron.isUserInteractionEnabled = false
      button.addSubview(chevron)
      NSLayoutConstraint.activate([
        chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -9),
        chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
      ])
    }

    configureIcon(swapButton, systemImage: "arrow.left.arrow.right", label: "Tillarni almashtirish", pointSize: 14)
    swapButton.tintColor = textColor
    swapButton.backgroundColor = keyBackground
    swapButton.layer.cornerRadius = 22
    swapButton.addTarget(self, action: #selector(swapTapped), for: .touchUpInside)
    addSubview(swapButton)

    configureIcon(closeButton, systemImage: "xmark", label: "Tarjimonni yopish", pointSize: 13)
    closeButton.tintColor = textColor
    closeButton.backgroundColor = keyBackground
    closeButton.layer.cornerRadius = 22
    closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    addSubview(closeButton)

    inputBox.translatesAutoresizingMaskIntoConstraints = false
    inputBox.backgroundColor = keyBackground
    inputBox.layer.cornerRadius = 10
    addSubview(inputBox)

    textLabel.translatesAutoresizingMaskIntoConstraints = false
    textLabel.numberOfLines = 1
    textLabel.lineBreakMode = .byTruncatingHead
    textLabel.font = UIFont.systemFont(ofSize: 15)
    inputBox.addSubview(textLabel)

    // G67: the chosen «from» language under the text — «O'zbekcha matn».
    languageNote.translatesAutoresizingMaskIntoConstraints = false
    languageNote.font = UIFont.systemFont(ofSize: 11)
    languageNote.textColor = textColor.withAlphaComponent(0.5)
    inputBox.addSubview(languageNote)

    configureIcon(clearButton, systemImage: "xmark.circle.fill", label: "Matnni tozalash", pointSize: 15)
    clearButton.tintColor = UIColor.tertiaryLabel
    clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
    inputBox.addSubview(clearButton)

    pasteButton.translatesAutoresizingMaskIntoConstraints = false
    pasteButton.setTitle("Qo'yish", for: .normal)
    pasteButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
    pasteButton.setTitleColor(textColor, for: .normal)
    pasteButton.backgroundColor = keyBackground
    pasteButton.layer.cornerRadius = 10
    pasteButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
    pasteButton.accessibilityLabel = "Buferdan qo'yish"
    pasteButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    pasteButton.addTarget(self, action: #selector(pasteTapped), for: .touchUpInside)
    addSubview(pasteButton)

    translateButton.translatesAutoresizingMaskIntoConstraints = false
    translateButton.backgroundColor = accent
    translateButton.layer.cornerRadius = 22
    translateButton.setTitleColor(.white, for: .normal)
    translateButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
    translateButton.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)
    addSubview(translateButton)

    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.color = .white
    spinner.hidesWhenStopped = true
    translateButton.addSubview(spinner)

    NSLayoutConstraint.activate([
      sourceButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      sourceButton.leadingAnchor.constraint(equalTo: leadingAnchor),
      sourceButton.heightAnchor.constraint(equalToConstant: 44),
      sourceButton.trailingAnchor.constraint(equalTo: swapButton.leadingAnchor, constant: -6),

      swapButton.centerYAnchor.constraint(equalTo: sourceButton.centerYAnchor),
      swapButton.widthAnchor.constraint(equalToConstant: 44),
      swapButton.heightAnchor.constraint(equalToConstant: 44),

      targetButton.leadingAnchor.constraint(equalTo: swapButton.trailingAnchor, constant: 6),
      targetButton.topAnchor.constraint(equalTo: sourceButton.topAnchor),
      targetButton.heightAnchor.constraint(equalTo: sourceButton.heightAnchor),
      targetButton.widthAnchor.constraint(equalTo: sourceButton.widthAnchor),
      targetButton.trailingAnchor.constraint(equalTo: trailingAnchor),

      inputBox.topAnchor.constraint(equalTo: sourceButton.bottomAnchor, constant: 6),
      inputBox.leadingAnchor.constraint(equalTo: leadingAnchor),
      inputBox.heightAnchor.constraint(equalToConstant: 44),
      inputBox.trailingAnchor.constraint(equalTo: pasteButton.leadingAnchor, constant: -6),

      pasteButton.trailingAnchor.constraint(equalTo: trailingAnchor),
      pasteButton.topAnchor.constraint(equalTo: inputBox.topAnchor),
      pasteButton.heightAnchor.constraint(equalTo: inputBox.heightAnchor),

      textLabel.leadingAnchor.constraint(equalTo: inputBox.leadingAnchor, constant: 10),
      textLabel.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
      textLabel.topAnchor.constraint(equalTo: inputBox.topAnchor, constant: 5),

      languageNote.leadingAnchor.constraint(equalTo: textLabel.leadingAnchor),
      languageNote.trailingAnchor.constraint(equalTo: textLabel.trailingAnchor),
      languageNote.bottomAnchor.constraint(equalTo: inputBox.bottomAnchor, constant: -4),

      clearButton.trailingAnchor.constraint(equalTo: inputBox.trailingAnchor, constant: -2),
      clearButton.centerYAnchor.constraint(equalTo: inputBox.centerYAnchor),
      clearButton.widthAnchor.constraint(equalToConstant: 36),
      clearButton.heightAnchor.constraint(equalToConstant: 44),

      closeButton.leadingAnchor.constraint(equalTo: leadingAnchor),
      closeButton.topAnchor.constraint(equalTo: inputBox.bottomAnchor, constant: 6),
      closeButton.widthAnchor.constraint(equalToConstant: 44),
      closeButton.heightAnchor.constraint(equalToConstant: 44),

      translateButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 6),
      translateButton.trailingAnchor.constraint(equalTo: trailingAnchor),
      translateButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
      translateButton.heightAnchor.constraint(equalToConstant: 44),

      spinner.centerYAnchor.constraint(equalTo: translateButton.centerYAnchor),
      spinner.leadingAnchor.constraint(equalTo: translateButton.leadingAnchor, constant: 14),
    ])
  }

  private func configureIcon(_ button: UIButton, systemImage: String, label: String, pointSize: CGFloat) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(
      UIImage(systemName: systemImage)?.withConfiguration(UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)),
      for: .normal
    )
    button.accessibilityLabel = label
  }

  /// G67: every opening starts at O'zbekcha → Русский.
  func reset() {
    source = .uz
    target = .ru
    text = ""
    busy = false
    refresh()
  }

  /// The text the keys have typed so far; shown with a caret at its end.
  func setText(_ value: String) {
    text = value
    refresh()
  }

  func setBusy(_ value: Bool) {
    busy = value
    refresh()
  }

  /// G67: the same language on both sides swaps the other one. G65: a choice never translates.
  private func choose(_ til: GaplaTarjimonTil, asSource: Bool) {
    onKeyClick?()
    if asSource {
      if til == target { target = source }
      source = til
    } else {
      if til == source { source = target }
      target = til
    }
    refresh()
  }

  @objc private func swapTapped() {
    onKeyClick?()
    (source, target) = (target, source)
    refresh()
  }

  /// «Qaysi tildan» small above, the language below in bold.
  private func boxTitle(caption: String, til: GaplaTarjimonTil) -> NSAttributedString {
    let title = NSMutableAttributedString(string: caption + "\n", attributes: [
      .font: UIFont.systemFont(ofSize: 11),
      .foregroundColor: textColor.withAlphaComponent(0.55),
    ])
    title.append(NSAttributedString(string: til.name, attributes: [
      .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
      .foregroundColor: textColor,
    ]))
    return title
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    // A layer colour does not follow light and dark by itself.
    for button in [sourceButton, targetButton] {
      button.layer.borderColor = accent.resolvedColor(with: traitCollection).cgColor
    }
  }

  private func menu(asSource: Bool) -> UIMenu {
    let current = asSource ? source : target
    return UIMenu(children: GaplaTarjimonTil.allCases.map { til in
      UIAction(title: til.name, state: til == current ? .on : .off) { [weak self] _ in
        self?.choose(til, asSource: asSource)
      }
    })
  }

  private func refresh() {
    sourceButton.setAttributedTitle(boxTitle(caption: "Qaysi tildan", til: source), for: .normal)
    targetButton.setAttributedTitle(boxTitle(caption: "Qaysi tilga", til: target), for: .normal)
    sourceButton.menu = menu(asSource: true)
    targetButton.menu = menu(asSource: false)
    sourceButton.accessibilityLabel = "Qaysi tildan: \(source.name)"
    targetButton.accessibilityLabel = "Qaysi tilga: \(target.name)"

    let shown = NSMutableAttributedString()
    if text.isEmpty {
      shown.append(NSAttributedString(
        string: "Yozing, qo'ying yoki ayting",
        attributes: [.foregroundColor: UIColor.placeholderText]
      ))
    } else {
      // One line for a line break, so both lines stay useful.
      shown.append(NSAttributedString(
        string: text.replacingOccurrences(of: "\n", with: " ↵ "),
        attributes: [.foregroundColor: textColor]
      ))
    }
    shown.append(NSAttributedString(string: "|", attributes: [.foregroundColor: accent]))
    textLabel.attributedText = shown
    languageNote.text = "\(source.uzbekName) matn"
    clearButton.isHidden = text.isEmpty

    // G65: off on an empty text, a spinner while it works. G67: the button says where to.
    let blank = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    translateButton.setTitle(target.buttonTitle, for: .normal)
    translateButton.isEnabled = !blank && !busy
    translateButton.alpha = blank && !busy ? 0.4 : 1
    if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
  }

  @objc private func translateTapped() {
    onKeyClick?()
    onTranslate?()
  }

  @objc private func pasteTapped() {
    onKeyClick?()
    onPaste?()
  }

  @objc private func clearTapped() {
    onKeyClick?()
    onClear?()
  }

  @objc private func closeTapped() {
    onKeyClick?()
    onClose?()
  }
}

/// The two variants, in the keys' place: «Ruscha — aniq» and «Ruscha — sayqallangan», each with «Joylash» and
/// «Nusxa»; above them the direction (O'zbekcha → Русский) and «Tahrirlash», which brings the keys back.
final class GaplaTarjimonNatijaView: UIView {
  var onInsert: ((String) -> Void)?
  var onCopy: ((String) -> Void)?
  var onEdit: (() -> Void)?

  private let accent: UIColor
  private let keyBackground: UIColor
  private let textColor: UIColor
  private let headerLabel = UILabel()
  private let editButton = UIButton(type: .system)
  private let cards = UIStackView()

  init(accent: UIColor, keyBackground: UIColor, textColor: UIColor) {
    self.accent = accent
    self.keyBackground = keyBackground
    self.textColor = textColor
    super.init(frame: .zero)
    build()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func build() {
    // Not fully clear: iOS sends a keyboard no touches where its pixels are transparent.
    backgroundColor = UIColor(white: 0, alpha: 0.001)

    headerLabel.translatesAutoresizingMaskIntoConstraints = false
    headerLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
    headerLabel.textColor = textColor.withAlphaComponent(0.6)
    headerLabel.numberOfLines = 2
    headerLabel.adjustsFontSizeToFitWidth = true
    headerLabel.minimumScaleFactor = 0.8
    addSubview(headerLabel)

    editButton.translatesAutoresizingMaskIntoConstraints = false
    editButton.setTitle("Tahrirlash", for: .normal)
    editButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
    editButton.setImage(
      UIImage(systemName: "keyboard")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)),
      for: .normal
    )
    editButton.tintColor = accent
    editButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
    editButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    editButton.addAction(UIAction { [weak self] _ in self?.onEdit?() }, for: .touchUpInside)
    addSubview(editButton)

    cards.translatesAutoresizingMaskIntoConstraints = false
    cards.axis = .vertical
    cards.spacing = 6
    cards.distribution = .fillEqually
    addSubview(cards)

    NSLayoutConstraint.activate([
      headerLabel.topAnchor.constraint(equalTo: topAnchor),
      headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
      headerLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 26),
      headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: editButton.leadingAnchor, constant: -8),

      editButton.trailingAnchor.constraint(equalTo: trailingAnchor),
      editButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
      editButton.heightAnchor.constraint(equalToConstant: 26),

      cards.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 2),
      cards.leadingAnchor.constraint(equalTo: leadingAnchor),
      cards.trailingAnchor.constraint(equalTo: trailingAnchor),
      cards.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  /// A note in the header in place of the direction (an error, «Nusxa olindi»).
  func showNote(_ note: String, isError: Bool) {
    headerLabel.text = note
    headerLabel.textColor = isError ? UIColor.systemRed : accent
  }

  /// No translation came: the reason alone; «Tahrirlash» brings the keys back.
  func showError(_ message: String) {
    cards.arrangedSubviews.forEach { $0.removeFromSuperview() }
    showNote(message, isError: true)
  }

  func show(_ natija: GaplaTarjimaNatija, from source: GaplaTarjimonTil, to target: GaplaTarjimonTil) {
    // The server's own answer wins: it names the languages it really used.
    let from = GaplaTarjimonTil(rawValue: natija.manba) ?? source
    let to = GaplaTarjimonTil(rawValue: natija.til) ?? target
    headerLabel.text = "\(from.name) → \(to.name)"
    headerLabel.textColor = textColor.withAlphaComponent(0.6)
    cards.arrangedSubviews.forEach { $0.removeFromSuperview() }
    cards.addArrangedSubview(makeCard(title: "\(to.uzbekName) — aniq", text: natija.aniq))
    if !natija.silliq.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      cards.addArrangedSubview(makeCard(title: "\(to.uzbekName) — sayqallangan", text: natija.silliq))
    }
  }

  private func makeCard(title: String, text: String) -> UIView {
    let card = UIView()
    card.backgroundColor = keyBackground
    card.layer.cornerRadius = 12

    let titleLabel = UILabel()
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = title
    titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
    titleLabel.textColor = accent
    card.addSubview(titleLabel)

    // Read-only and scrollable; the server keeps the line breaks (G63) and they show as they are.
    let body = UITextView()
    body.translatesAutoresizingMaskIntoConstraints = false
    body.isEditable = false
    body.isSelectable = false
    body.backgroundColor = .clear
    body.textContainerInset = .zero
    body.textContainer.lineFragmentPadding = 0
    body.font = UIFont.systemFont(ofSize: 15)
    body.textColor = textColor
    body.text = text
    card.addSubview(body)

    let insert = actionButton(title: "Joylash", systemImage: "text.insert", filled: true)
    insert.addAction(UIAction { [weak self] _ in self?.onInsert?(text) }, for: .touchUpInside)
    let copy = actionButton(title: "Nusxa", systemImage: "doc.on.doc", filled: false)
    copy.addAction(UIAction { [weak self] _ in self?.onCopy?(text) }, for: .touchUpInside)
    let actions = UIStackView(arrangedSubviews: [insert, copy])
    actions.translatesAutoresizingMaskIntoConstraints = false
    actions.axis = .vertical
    actions.spacing = 6
    actions.distribution = .fillEqually
    card.addSubview(actions)

    NSLayoutConstraint.activate([
      titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
      titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
      titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -8),

      body.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
      body.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
      body.trailingAnchor.constraint(equalTo: actions.leadingAnchor, constant: -8),
      body.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),

      actions.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
      actions.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
      actions.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
      actions.widthAnchor.constraint(equalToConstant: 96),
    ])
    return card
  }

  private func actionButton(title: String, systemImage: String, filled: Bool) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
    button.setImage(
      UIImage(systemName: systemImage)?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)),
      for: .normal
    )
    button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
    button.layer.cornerRadius = 8
    if filled {
      button.backgroundColor = accent
      button.tintColor = .white
      button.setTitleColor(.white, for: .normal)
    } else {
      button.backgroundColor = UIColor.tertiarySystemFill
      button.tintColor = accent
      button.setTitleColor(accent, for: .normal)
    }
    return button
  }
}
