import os
import SwiftUI
import UIKit

private enum KeyboardLog {
  static let ui = Logger(subsystem: "com.gizmolabs.openwhispr.keyboard", category: "UI")
  static let transcription = Logger(
    subsystem: "com.gizmolabs.openwhispr.keyboard",
    category: "Transcription"
  )
  static let storage = Logger(subsystem: "com.gizmolabs.openwhispr.keyboard", category: "Storage")

  static func echo(_ message: String) {
    #if DEBUG
    NSLog("[OpenWhisprKeyboard] %@", message)
    #endif
  }
}

/// Every colour the keyboard draws. Theme-dependent ones are dynamic: iOS applies both a
/// light/dark switch and the host field's keyboardAppearance to the extension, so views
/// restyle with no code. (Overriding the style from textDocumentProxy.keyboardAppearance
/// freezes it: for a default field the proxy reports the style resolved at focus.)
private enum Palette {
  /// A colour that resolves differently for light vs dark appearance.
  private static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
    UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
  }

  private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
    UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
  }

  // Apple's iOS 26 keys, one colour for every key, measured over the system glass:
  // (255,255,255) on (226,228,232) light, (61,61,61) on (23,23,23) dark. The view is
  // transparent, so the system draws the glass and these composite over it. Dark is a
  // grey that also matches Apple over a coloured backdrop ((126,61,63) on (108,22,24)).
  // Apple's light keys blend with the app content beneath the glass, which an extension
  // cannot see, so light matches on plain backdrops only.
  static let keyBackground = dynamic(light: UIColor(white: 1, alpha: 0.96), dark: UIColor(white: 0.73, alpha: 0.235))
  // Pressed function key: (196,197,200) light, (125,125,125) dark.
  static let keyPressedBackground = dynamic(light: UIColor(white: 0, alpha: 0.135), dark: UIColor(white: 1, alpha: 0.44))
  // Disabled return: key (191,193,197) / (116,116,116), glyph (172,173,177) / (129,129,129).
  static let keyDisabledBackground = dynamic(light: UIColor(white: 0, alpha: 0.155), dark: UIColor(white: 1, alpha: 0.40))
  static let keyDisabledText = dynamic(light: rgb(172, 173, 177), dark: rgb(129, 129, 129))
  // The prominent return key (Go, Search, Send, Done…) is Gapla mandarin #BC4B1C in both modes (owner chose it over
  // Apple's blue, 2026-11-12, G54): white glyph 5.05:1. Held, it shows as a plain key (keyBackground, keyText glyph).
  static let returnKeyProminent = rgb(188, 75, 28)
  static let keyText = dynamic(light: .black, dark: .white)
  // Key preview balloon, opaque as Apple's in both modes: the key under it stays hidden (its
  // glyph shows through Apple's dark one by at most 3). No shadow.
  static let popupBackground = dynamic(light: .white, dark: UIColor(white: 80 / 255, alpha: 1))

  // Gapla mandarini (G54, egasi 2026-11-12: [so'zlari: bilim/gapla-goyalar-royxati.md]; kompyuter ilovasi 5ef477e va
  // src/config/colors.ts `BRAND` bilan bir xil). Plashka foni sifatida: oq yozuv 5,05:1, tungi klaviatura
  // fonida (#171717) shakl 3,5:1. Ikkala ko'rinishda bir xil: plashka qatlamlari (CGColor) ko'rinish
  // almashganda qayta chizilmaydi. The warning amber reads well on both appearances too.
  static let accent = rgb(188, 75, 28)
  static let issue = UIColor(red: 1.00, green: 0.62, blue: 0.04, alpha: 1.0)
  // Klaviatura yuzasidagi belgi va yozuv uchun: kunduz #BC4B1C (oq tugmada 5,05:1), tun #FF9447 (tungi tugmada
  // 4,95:1) — kompyuterdagi kunduzgi va tungi asosiy rang. Klaviaturaning umumiy rangi (view.tintColor) ham shu.
  static let accentTint = dynamic(light: rgb(188, 75, 28), dark: rgb(255, 148, 71))

  // Ink for the persistent "Turn on Full Access" pill (#1C1300 on issue amber
  // = 5.6:1, passes AA). White on the same amber is 2.1:1 and fails. The
  // transient amber states keep white ink — a 1.2s flash is not something a
  // low-vision user has to read, a permanent notice is.
  static let issueInk = UIColor(red: 0.110, green: 0.075, blue: 0.000, alpha: 1.0)

  // Tozalash (cleanup) va ovozli yordamchi holatlari ham Gapla mandarinida: kompyuter ilovasida urg'u rangi
  // asosiy rang bilan bitta (G54).
  static let cleanupAccent = accent

  // "Faollashtirish" tugmasining shishasi — ilovadagi BRAND_GRADIENT (#C24F1F → #B0451A), oq yozuv kamida
  // 4,74:1 (src/config/colors.ts).
  static let brandGradientStart = rgb(194, 79, 31)
  static let brandGradientEnd = rgb(176, 69, 26)
}

/// Apple's iOS 26 keycap type, measured at 3x on the iPhone 17 Pro: capitals and digits
/// have a 15.3pt cap height and lowercase a 13pt x-height (Apple draws lowercase larger),
/// all regular weight, on one baseline 6.5pt below the key's centre in portrait. The faces
/// that change with orientation are in Keycaps.
private enum KeyFont {
  static let modeLabel = UIFont.systemFont(ofSize: 17.75, weight: .regular)  // 123, ABC
  static let pageLabel = UIFont.systemFont(ofSize: 15, weight: .regular)  // 123 in row 3
  static let domainLabel = UIFont.systemFont(ofSize: 19, weight: .regular)  // .com, larger than 123/ABC
  static let moreSymbolsLabel = UIFont.systemFont(ofSize: 12, weight: .semibold)  // #+= in row 3
  static let glyph = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)  // shift, delete, return, globe
  static let characterBaseline: CGFloat = 6.5
  static let moreSymbolsBaseline: CGFloat = 3.17

  /// Apple sets ".", ",", "_", "#" and ":" lower than the other characters' baseline.
  static func baseline(for character: String) -> CGFloat {
    switch character {
    case ".", ",": return characterBaseline + 2.67
    case "_": return characterBaseline + 3
    case "#", ":": return characterBaseline + 1
    default: return characterBaseline
    }
  }

  /// The bottom row's field keys: its "#" is the regular-size one, on the shared baseline.
  static func shortcutBaseline(for character: String, raisesPeriod: Bool) -> CGFloat {
    switch character {
    case "#": return characterBaseline
    case "." where raisesPeriod: return baseline(for: character) - 4
    default: return baseline(for: character)
    }
  }
  // Apple's caps-lock glyph sits a little above centre (shift/delete: Keycaps; return glyphs:
  // ReturnKeyStyle).
  static let capsLockGlyphOffset: CGFloat = -0.33

  /// Apple's iOS 26 keycaps are SF Compact (narrower round letters than SF Pro), which has no
  /// public font API, so this loads the copy iOS ships. Sizes keep SF Pro's cap and x-heights.
  /// Nil where the file is missing; the SF Pro fallback then matches every height and baseline.
  static func compact(size: CGFloat, weight: CGFloat, caseSensitive: Bool = false) -> UIFont? {
    var path = "/System/Library/Fonts/Core/SFCompact.ttf"
    #if targetEnvironment(simulator)
    path = (ProcessInfo.processInfo.environment["IPHONE_SIMULATOR_ROOT"] ?? "") + path
    #endif
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(
      URL(fileURLWithPath: path) as CFURL
    ) as? [CTFontDescriptor], let descriptor = descriptors.first else { return nil }
    var weighted = CTFontDescriptorCreateCopyWithVariation(descriptor, 0x7767_6874 as CFNumber, weight)
    if caseSensitive {
      weighted = CTFontDescriptorCreateCopyWithFeature(
        weighted, kCaseSensitiveLayoutType as CFNumber, kCaseSensitiveLayoutOnSelector as CFNumber
      )
    }
    return CTFontCreateWithFontDescriptor(weighted, size, nil) as UIFont
  }
}

/// The keycap faces and nudges that change with orientation. Landscape keys are shorter:
/// there Apple sets letters 11% smaller with lowercase 0.67pt higher, the "123" key at the
/// 15pt row-3 size but "ABC" full size and 0.5pt lower, ".com" 0.5pt lower and shift/delete
/// on centre (17 Pro).
private struct Keycaps: Equatable {
  struct Label: Equatable {
    let font: UIFont
    let baseline: CGFloat
  }

  let lowercase: UIFont
  /// Also digits and symbols, which Apple raises to the capitals (case-sensitive forms).
  let uppercase: UIFont
  /// …except ":", "#" and "_", which Apple draws larger and without those forms.
  let large: UIFont
  /// The mode key's titles: "123" on the letters page, "ABC" on the others.
  let label123: Label
  let labelABC: Label
  let domainBaseline: CGFloat  // .com
  /// The lowercase baseline, from the capitals'.
  let lowercaseBaselineShift: CGFloat
  /// Shift and delete glyphs, from UIKit's centring.
  let edgeGlyphOffset: CGFloat

  static let portrait = Keycaps(
    scale: 1,
    label123: Label(font: KeyFont.modeLabel, baseline: 5.5),
    labelABC: Label(font: KeyFont.modeLabel, baseline: 5.5),
    domainBaseline: 3.67,
    lowercaseBaselineShift: 0,
    edgeGlyphOffset: 0.67
  )
  static let landscape = Keycaps(
    scale: 0.89,
    label123: Label(font: KeyFont.pageLabel, baseline: 4.83),
    labelABC: Label(font: KeyFont.modeLabel, baseline: 6),
    domainBaseline: 4.17,
    lowercaseBaselineShift: -0.67,
    edgeGlyphOffset: 0
  )

  private init(
    scale: CGFloat,
    label123: Label,
    labelABC: Label,
    domainBaseline: CGFloat,
    lowercaseBaselineShift: CGFloat,
    edgeGlyphOffset: CGFloat
  ) {
    lowercase = KeyFont.compact(size: 24.67 * scale, weight: 420)
      ?? UIFont.systemFont(ofSize: 24.5 * scale, weight: UIFont.Weight(-0.08))
    uppercase = KeyFont.compact(size: 22.4 * scale, weight: 480, caseSensitive: true)
      ?? UIFont.systemFont(ofSize: 21.5 * scale, weight: UIFont.Weight(0.1))
    large = KeyFont.compact(size: 27 * scale, weight: 480) ?? uppercase
    self.label123 = label123
    self.labelABC = labelABC
    self.domainBaseline = domainBaseline
    self.lowercaseBaselineShift = lowercaseBaselineShift
    self.edgeGlyphOffset = edgeGlyphOffset
  }

  func character(_ display: String) -> UIFont {
    switch display {
    case ":", "#", "_": return large
    default: return uppercase
    }
  }
}

/// Route through row/stack boundaries so a key's enlarged target also works in
/// the gaps between rows. UIKit's default hit testing stops at a parent whose
/// bounds do not contain the touch, before consulting the key's point(inside:).
/// Touches no key claims keep UIKit's default target.
private final class KeyboardRowsStack: UIStackView {
  /// Padding around the rows that still routes to the nearest key, as the system
  /// keyboard does at its edges.
  var touchMargins = UIEdgeInsets.zero

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    let expanded = bounds.inset(
      by: UIEdgeInsets(
        top: -touchMargins.top,
        left: -touchMargins.left,
        bottom: -touchMargins.bottom,
        right: -touchMargins.right
      )
    )
    return expanded.contains(point)
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard let defaultTarget = super.hitTest(point, with: event) else { return nil }

    var nearest: KeyButton?
    var nearestDistance = CGFloat.infinity
    var nearestCenterDistance = CGFloat.infinity

    func visit(_ view: UIView) {
      guard !view.isHidden, view.isUserInteractionEnabled, view.alpha >= 0.01 else { return }
      if let key = view as? KeyButton {
        guard key.isEnabled,
              key.point(inside: key.convert(point, from: self), with: event) else { return }

        // Prefer the visible key rectangle over another key's expanded area.
        // In a gap, choose the nearer edge; center distance breaks edge ties.
        // This avoids UIKit's reverse-subview-order bias in overlapping targets.
        let rect = key.convert(key.bounds, to: self)
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        let distance = dx * dx + dy * dy
        let centerDX = point.x - rect.midX
        let centerDY = point.y - rect.midY
        let centerDistance = centerDX * centerDX + centerDY * centerDY
        if distance < nearestDistance
          || (distance == nearestDistance && centerDistance < nearestCenterDistance) {
          nearest = key
          nearestDistance = distance
          nearestCenterDistance = centerDistance
        }
        return
      }
      view.subviews.forEach(visit)
    }

    subviews.forEach(visit)
    return nearest ?? defaultTarget
  }
}

private extension UIColor {
  func brightened(by amount: CGFloat) -> UIColor {
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return UIColor(hue: h, saturation: s, brightness: max(0, min(b + amount, 1.0)), alpha: a)
  }
}

private final class KeyButton: UIButton {
  var hitTestOutsets = UIEdgeInsets(top: 6, left: 3, bottom: 6, right: 3)
  /// What the key inserts; the title is only what it shows (” displays, " inserts).
  var output: String?

  var normalBackground: UIColor = .clear {
    didSet { refreshPressedLook() }
  }
  var pressedBackground: UIColor?
  /// The glyph colour while pressed, where it isn't the key's tint (the held blue return).
  var pressedTint: UIColor? {
    didSet { refreshPressedLook() }
  }
  /// Keeps the pressed look while a long press owns the touch (delete repeating), as Apple's
  /// key stays pressed for the whole hold.
  var isLongPressed = false {
    didSet { refreshPressedLook() }
  }
  /// Where the title's baseline sits below the key's centre; nil keeps UIKit's centring.
  var titleBaselineFromCenter: CGFloat? {
    didSet { setNeedsLayout() }
  }
  /// Nudges the glyph down (or up, negative) from UIKit's centring to Apple's position.
  var imageOffsetY: CGFloat = 0 {
    didSet { setNeedsLayout() }
  }

  // UIKit asks for this rect on every layout, so the nudge neither accumulates nor gets lost
  // when the image changes, as a frame offset or a transform applied after layout did.
  override func imageRect(forContentRect contentRect: CGRect) -> CGRect {
    super.imageRect(forContentRect: contentRect).offsetBy(dx: 0, dy: imageOffsetY)
  }

  // Same luminous-rim treatment as PillBackgroundView: a white top-lit gradient
  // masked to the border stroke, so the button reads as glass-edged. Opt-in —
  // only the toolbar's tone and agent buttons use it.
  var showsGlassRim = false {
    didSet {
      guard showsGlassRim != oldValue else { return }
      if showsGlassRim { installGlassRim() } else { removeGlassRim() }
    }
  }

  private static let glassRimWidth: CGFloat = 1.5
  private var glassRimLayer: CAGradientLayer?

  private func installGlassRim() {
    let rim = CAGradientLayer()
    rim.colors = [
      UIColor(white: 1, alpha: 0.55).cgColor,
      UIColor(white: 1, alpha: 0.12).cgColor,
    ]
    rim.startPoint = CGPoint(x: 0.5, y: 0)
    rim.endPoint = CGPoint(x: 0.5, y: 1)
    let mask = CAShapeLayer()
    mask.fillColor = UIColor.clear.cgColor
    mask.strokeColor = UIColor.black.cgColor
    mask.lineWidth = Self.glassRimWidth
    rim.mask = mask
    layer.addSublayer(rim)
    glassRimLayer = rim
    setNeedsLayout()
  }

  private func removeGlassRim() {
    glassRimLayer?.removeFromSuperlayer()
    glassRimLayer = nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if let titleBaselineFromCenter, let label = titleLabel, let font = label.font {
      label.frame.origin.y =
        bounds.midY + titleBaselineFromCenter - font.ascender - (label.bounds.height - font.lineHeight) / 2
    }
    if let rim = glassRimLayer, let mask = rim.mask as? CAShapeLayer {
      rim.frame = bounds
      mask.frame = bounds
      let inset = Self.glassRimWidth / 2
      mask.path = UIBezierPath(
        roundedRect: bounds.insetBy(dx: inset, dy: inset),
        cornerRadius: max(0, layer.cornerRadius - inset)
      ).cgPath
    }
  }

  override var isHighlighted: Bool {
    didSet { refreshPressedLook() }
  }

  // UIKit darkens a highlighted image that falls back to the normal state's; Apple's pressed
  // glyphs keep their colour, so the highlighted state carries the same image and size.
  override func setImage(_ image: UIImage?, for state: UIControl.State) {
    super.setImage(image, for: state)
    if state == .normal { super.setImage(image, for: .highlighted) }
  }

  override func setPreferredSymbolConfiguration(
    _ configuration: UIImage.SymbolConfiguration?, forImageIn state: UIControl.State
  ) {
    super.setPreferredSymbolConfiguration(configuration, forImageIn: state)
    if state == .normal { super.setPreferredSymbolConfiguration(configuration, forImageIn: .highlighted) }
  }

  private func refreshPressedLook() {
    let isPressed = isHighlighted || isLongPressed
    backgroundColor = isPressed ? (pressedBackground ?? normalBackground) : normalBackground
    // nil hands the glyph back to the button's tint.
    imageView?.tintColor = isPressed ? pressedTint : nil
  }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    let expanded = bounds.inset(
      by: UIEdgeInsets(
        top: -hitTestOutsets.top,
        left: -hitTestOutsets.left,
        bottom: -hitTestOutsets.bottom,
        right: -hitTestOutsets.right
      )
    )
    return expanded.contains(point)
  }
}

/// A diagonal-gradient (top-left → bottom-right) background, rounded to its
/// corner radius, with a soft drop shadow. Sits behind the transparent record
/// button so the button's icon/text render on top of it.
///
/// `.adaptive` is the idle dictation style — a dark-grey filled pill in light
/// mode, an outlined (transparent + light border) pill in dark mode. `.solid`
/// is a flat colour fill used for transient states (processing, errors).
private final class PillBackgroundView: UIView {
  enum Style {
    case adaptive            // grey fill (light) / outlined (dark) — "Tap to speak"
    case gradient([UIColor]) // Gapla mandarin glass — "Activate"
    case solid(UIColor)      // flat colour — transient/issue states
  }

  private static let adaptiveFill = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? .clear
      : UIColor(red: 0.27, green: 0.27, blue: 0.29, alpha: 1.0)
  }

  private static let rimWidth: CGFloat = 1.5

  private let gradientLayer = CAGradientLayer()
  private let rimLayer = CAGradientLayer()    // glass edge highlight
  private let rimMask = CAShapeLayer()        // masks the rim to the border only
  private let highlightLayer = CALayer()      // white press overlay (lightens on touch)
  private var style: Style = .adaptive

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    layer.cornerCurve = .continuous

    // Base gradient fill (used by .gradient), behind everything.
    gradientLayer.startPoint = CGPoint(x: 0, y: 0)
    gradientLayer.endPoint = CGPoint(x: 1, y: 1)
    gradientLayer.cornerCurve = .continuous
    gradientLayer.masksToBounds = true
    layer.addSublayer(gradientLayer)

    // The "glass" is a luminous rim on the border — bright at the top edge,
    // fading down — rather than a sheen across the surface. A white vertical
    // gradient is masked to just the border stroke.
    rimLayer.colors = [
      UIColor(white: 1, alpha: 0.55).cgColor,
      UIColor(white: 1, alpha: 0.12).cgColor,
    ]
    rimLayer.startPoint = CGPoint(x: 0.5, y: 0)
    rimLayer.endPoint = CGPoint(x: 0.5, y: 1)
    rimMask.fillColor = UIColor.clear.cgColor
    rimMask.strokeColor = UIColor.black.cgColor
    rimMask.lineWidth = Self.rimWidth
    rimLayer.mask = rimMask
    layer.addSublayer(rimLayer)

    // White overlay on top of the fill (but behind the button's content, which
    // is a sibling view) — fades in on press so the button lights up.
    highlightLayer.backgroundColor = UIColor.white.cgColor
    highlightLayer.opacity = 0
    highlightLayer.masksToBounds = true
    layer.addSublayer(highlightLayer)

    // Drop shadow so the pill reads as a raised button.
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.20
    layer.shadowRadius = 5
    layer.shadowOffset = CGSize(width: 0, height: 2)

    apply()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    gradientLayer.frame = bounds
    gradientLayer.cornerRadius = layer.cornerRadius

    rimLayer.frame = bounds
    rimMask.frame = bounds
    let inset = Self.rimWidth / 2
    rimMask.path = UIBezierPath(
      roundedRect: bounds.insetBy(dx: inset, dy: inset),
      cornerRadius: max(0, layer.cornerRadius - inset)
    ).cgPath

    highlightLayer.frame = bounds
    highlightLayer.cornerRadius = layer.cornerRadius

    layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
  }

  func setStyle(_ style: Style) {
    self.style = style
    apply()
  }

  // Pressed = lights up: white overlay fades in and the shadow softens.
  func setPressed(_ pressed: Bool) {
    CATransaction.begin()
    CATransaction.setAnimationDuration(0.09)
    highlightLayer.opacity = pressed ? 0.22 : 0
    layer.shadowOpacity = pressed ? 0.12 : 0.20
    CATransaction.commit()
  }

  private func apply() {
    switch style {
    case .adaptive:
      gradientLayer.isHidden = true
      backgroundColor = Self.adaptiveFill
    case .gradient(let colors):
      gradientLayer.isHidden = false
      gradientLayer.colors = colors.map { $0.cgColor }
      backgroundColor = .clear
    case .solid(let color):
      gradientLayer.isHidden = true
      backgroundColor = color
    }
  }
}

/// Three dots that bounce up and down in a staggered wave — the animated
/// "Processing" indicator, so the state reads as alive rather than stuck.
private final class ProcessingDotsView: UIView {
  private static let dotSize: CGFloat = 4.5
  private static let gap: CGFloat = 4
  static let preferredSize = CGSize(width: dotSize * 3 + gap * 2, height: 14)

  private let dots: [CALayer]

  override init(frame: CGRect) {
    dots = (0..<3).map { _ in
      let dot = CALayer()
      dot.backgroundColor = UIColor.white.cgColor
      dot.cornerRadius = ProcessingDotsView.dotSize / 2
      return dot
    }
    super.init(frame: frame)
    isUserInteractionEnabled = false
    dots.forEach { layer.addSublayer($0) }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: CGSize { Self.preferredSize }

  override func layoutSubviews() {
    super.layoutSubviews()
    var x: CGFloat = 0
    for dot in dots {
      dot.frame = CGRect(
        x: x, y: bounds.midY - Self.dotSize / 2,
        width: Self.dotSize, height: Self.dotSize
      )
      x += Self.dotSize + Self.gap
    }
  }

  func startAnimating() {
    for (index, dot) in dots.enumerated() {
      dot.removeAllAnimations()
      let move = CABasicAnimation(keyPath: "transform.translation.y")
      move.fromValue = 1.5
      move.toValue = -2.5
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0.55
      fade.toValue = 1.0
      let group = CAAnimationGroup()
      group.animations = [move, fade]
      group.duration = 0.55
      group.autoreverses = true
      group.repeatCount = .infinity
      group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      group.beginTime = CACurrentMediaTime() + Double(index) * 0.15
      dot.add(group, forKey: "bounce")
    }
  }

  func stopAnimating() {
    dots.forEach { $0.removeAllAnimations() }
  }
}

/// Gapla (G57, analysis finding 3): the emoji page's scrolling grid. A collection view keeps only the cells on screen
/// (about forty) and reuses them while scrolling, where the first page (G45) built a button for every one of the ~250
/// emoji at once and kept them. Same look: `columns` equal cells a row, `cellHeight` tall, `rowSpacing` apart.
private final class EmojiGridView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
  /// A tap on an emoji.
  var onPick: ((String) -> Void)?

  private final class Cell: UICollectionViewCell {
    static let reuseIdentifier = "gapla-emoji"
    let label = UILabel()

    override init(frame: CGRect) {
      super.init(frame: frame)
      label.textAlignment = .center
      label.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(label)
      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        label.topAnchor.constraint(equalTo: contentView.topAnchor),
        label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      ])
      isAccessibilityElement = true
      accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }

  private let emojis: [String]
  private let columns: Int
  private let cellHeight: CGFloat
  private let emojiFont: UIFont
  private let collectionView: UICollectionView
  private var laidOutWidth: CGFloat = 0

  init(emojis: [String], columns: Int, cellHeight: CGFloat, rowSpacing: CGFloat) {
    self.emojis = emojis
    self.columns = max(1, columns)
    self.cellHeight = cellHeight
    emojiFont = UIFont.systemFont(ofSize: min(32, cellHeight * 0.72))
    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .vertical
    layout.minimumInteritemSpacing = 0
    layout.minimumLineSpacing = rowSpacing
    layout.sectionInset = .zero
    collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    super.init(frame: .zero)

    collectionView.backgroundColor = .clear
    collectionView.showsVerticalScrollIndicator = false
    collectionView.alwaysBounceVertical = true
    // Only the visible cells: prefetching would build the next rows ahead of time.
    collectionView.isPrefetchingEnabled = false
    collectionView.register(Cell.self, forCellWithReuseIdentifier: Cell.reuseIdentifier)
    collectionView.dataSource = self
    collectionView.delegate = self
    collectionView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(collectionView)
    NSLayoutConstraint.activate([
      collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
      collectionView.topAnchor.constraint(equalTo: topAnchor),
      collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // The cell width follows the grid's width; a new width (first layout, rotation) re-sizes the cells.
    let width = collectionView.bounds.width
    if abs(width - laidOutWidth) > 0.5 {
      laidOutWidth = width
      collectionView.collectionViewLayout.invalidateLayout()
    }
  }

  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    emojis.count
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Cell.reuseIdentifier, for: indexPath)
    if let emojiCell = cell as? Cell, emojis.indices.contains(indexPath.item) {
      let emoji = emojis[indexPath.item]
      emojiCell.label.font = emojiFont
      emojiCell.label.text = emoji
      emojiCell.accessibilityLabel = emoji
    }
    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  ) -> CGSize {
    // Rounded down to the pixel so `columns` cells always fit a row.
    let scale = max(1, collectionView.traitCollection.displayScale)
    let width = floor(collectionView.bounds.width / CGFloat(columns) * scale) / scale
    return CGSize(width: max(1, width), height: cellHeight)
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    collectionView.deselectItem(at: indexPath, animated: false)
    guard emojis.indices.contains(indexPath.item) else { return }
    onPick?(emojis[indexPath.item])
  }
}

/// Apple's iOS 26 key preview, measured on the iPhone 17 Pro: a head 12pt wider than the
/// key on each side with 12pt corners, its top 66pt above the key's, joined to the key by
/// an S-curve, and no shadow. Extensions can't draw above their view, so a top-row head
/// starts at the view's top instead. An edge key's head is flush with the key's outer side
/// and reaches 22pt (left edge) or 20pt (right edge) past its inner side, its letter centred
/// where a full-width head ending there would centre it (17 Pro and Pro Max).
private final class KeyPopupView: UIView {
  private static let headOutset: CGFloat = 12
  private static let leftEdgeReach: CGFloat = 22
  private static let rightEdgeReach: CGFloat = 20
  private static let headRise: CGFloat = 66
  private static let headHeight: CGFloat = 50
  private static let headRadius: CGFloat = 12
  private static let neckLength: CGFloat = 22
  private static let glyphBaseline: CGFloat = 47
  private static let glyphScale: CGFloat = 1.556

  private let fill = UIView()
  private let shapeMask = CAShapeLayer()
  private let label = UILabel()
  private weak var owner: UIView?
  private var pendingHide: DispatchWorkItem?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    isHidden = true
    fill.backgroundColor = Palette.popupBackground
    shapeMask.fillColor = UIColor.black.cgColor
    fill.layer.mask = shapeMask
    addSubview(fill)
    label.textAlignment = .center
    label.textColor = Palette.keyText
    addSubview(label)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Shows `text` over `keyFrame` (superview coordinates), kept inside `container`.
  func show(
    _ text: String,
    font: UIFont,
    keyFrame: CGRect,
    keyCornerRadius: CGFloat,
    container: CGRect,
    owner: UIView
  ) {
    var (minX, maxX) = (keyFrame.minX - Self.headOutset, keyFrame.maxX + Self.headOutset)
    var glyphMidX = keyFrame.midX
    if minX < container.minX {
      (minX, maxX) = (keyFrame.minX, keyFrame.maxX + Self.leftEdgeReach)
      glyphMidX = maxX - keyFrame.width / 2 - Self.headOutset
    } else if maxX > container.maxX {
      (minX, maxX) = (keyFrame.minX - Self.rightEdgeReach, keyFrame.maxX)
      glyphMidX = minX + keyFrame.width / 2 + Self.headOutset
    }
    let head = CGRect(
      x: minX,
      y: max(container.minY, keyFrame.minY - Self.headRise),
      width: maxX - minX,
      height: Self.headHeight
    )
    frame = head.union(keyFrame)
    let headRect = head.offsetBy(dx: -frame.minX, dy: -frame.minY)
    let keyRect = keyFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
    fill.frame = bounds
    shapeMask.frame = fill.bounds
    shapeMask.path = Self.balloon(head: headRect, key: keyRect, keyCornerRadius: keyCornerRadius).cgPath

    // The keycap's own face and weight, enlarged: Apple's preview letter matches its key's.
    label.font = font.withSize(font.pointSize * Self.glyphScale)
    label.text = text
    label.sizeToFit()
    label.frame.origin = CGPoint(
      x: glyphMidX - frame.minX - label.bounds.width / 2,
      y: headRect.minY + Self.glyphBaseline - label.font.ascender
        - (label.bounds.height - label.font.lineHeight) / 2
    )
    pendingHide?.cancel()
    pendingHide = nil
    self.owner = owner
    isHidden = false
  }

  /// Hides the preview, but only for the key that showed it when `owner` is given, so a
  /// rolled second key's preview survives the first key's release. `after` keeps it up a
  /// moment past the release, as Apple's does (~50ms, measured on iOS 26.5); a new
  /// `show` or an immediate `hide` cancels the wait.
  func hide(owner: UIView? = nil, after delay: TimeInterval = 0) {
    guard owner == nil || owner === self.owner else { return }
    pendingHide?.cancel()
    pendingHide = nil
    guard delay > 0 else {
      isHidden = true
      self.owner = nil
      return
    }
    let work = DispatchWorkItem { [weak self] in self?.hide(owner: owner) }
    pendingHide = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private static func balloon(head: CGRect, key: CGRect, keyCornerRadius r: CGFloat) -> UIBezierPath {
    let neckEnd = min(head.maxY + neckLength, key.maxY - r)
    let neckMid = (head.maxY + neckEnd) / 2
    let path = UIBezierPath()
    path.move(to: CGPoint(x: head.minX, y: head.minY + headRadius))
    path.addArc(
      withCenter: CGPoint(x: head.minX + headRadius, y: head.minY + headRadius),
      radius: headRadius, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: true
    )
    path.addArc(
      withCenter: CGPoint(x: head.maxX - headRadius, y: head.minY + headRadius),
      radius: headRadius, startAngle: 1.5 * .pi, endAngle: 0, clockwise: true
    )
    path.addLine(to: CGPoint(x: head.maxX, y: head.maxY))
    path.addCurve(
      to: CGPoint(x: key.maxX, y: neckEnd),
      controlPoint1: CGPoint(x: head.maxX, y: neckMid),
      controlPoint2: CGPoint(x: key.maxX, y: neckMid)
    )
    path.addArc(
      withCenter: CGPoint(x: key.maxX - r, y: key.maxY - r),
      radius: r, startAngle: 0, endAngle: 0.5 * .pi, clockwise: true
    )
    path.addArc(
      withCenter: CGPoint(x: key.minX + r, y: key.maxY - r),
      radius: r, startAngle: 0.5 * .pi, endAngle: .pi, clockwise: true
    )
    path.addLine(to: CGPoint(x: key.minX, y: neckEnd))
    path.addCurve(
      to: CGPoint(x: head.minX, y: head.maxY),
      controlPoint1: CGPoint(x: key.minX, y: neckMid),
      controlPoint2: CGPoint(x: head.minX, y: neckMid)
    )
    path.close()
    return path
  }
}

/// Gapla (G56): a button that reports when it is shown or hidden — the processing ✕ beside the dictation pill, so the
/// translate button (文A), which it would overlap, steps aside while it is up (refreshTranslateButton).
private final class VisibilityReportingButton: UIButton {
  var onHiddenChanged: ((Bool) -> Void)?

  override var isHidden: Bool {
    didSet {
      if oldValue != isHidden { onHiddenChanged?(isHidden) }
    }
  }
}

private struct DictationLinkView: View {
  let url: URL

  var body: some View {
    Link(destination: url) {
      Color.clear
        .contentShape(Rectangle())
    }
  }
}

/// Gapla (G60): the letters a held key offers, in a row above it, as Apple's accent picker. The finger slides along the
/// row to choose; lifting types the chosen one (KeyboardViewController.handleAlternateLongPress). The first is picked
/// until the finger moves, so a key with one alternate types it on a plain hold.
private final class AlternatesPopupView: UIView {
  private static let cellWidth: CGFloat = 42
  private static let height: CGFloat = 50
  private static let rise: CGFloat = 8

  private let stack = UIStackView()
  private var labels: [UILabel] = []
  private(set) var selectedIndex = 0

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    isHidden = true
    backgroundColor = Palette.popupBackground
    layer.cornerRadius = 10
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.25
    layer.shadowRadius = 4
    layer.shadowOffset = CGSize(width: 0, height: 1)
    stack.axis = .horizontal
    stack.distribution = .fillEqually
    addSubview(stack)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Shows `choices` above `keyFrame` (both in the superview's coordinates), kept inside `container`.
  func show(_ choices: [String], font: UIFont, keyFrame: CGRect, container: CGRect) {
    labels.forEach { $0.removeFromSuperview() }
    labels = choices.map { choice in
      let label = UILabel()
      label.text = choice
      label.font = font
      label.textAlignment = .center
      label.layer.cornerRadius = 8
      label.layer.masksToBounds = true
      stack.addArrangedSubview(label)
      return label
    }
    let width = max(keyFrame.width, CGFloat(choices.count) * Self.cellWidth)
    let x = min(max(keyFrame.midX - width / 2, container.minX), container.maxX - width)
    let y = max(keyFrame.minY - Self.height - Self.rise, 0)
    frame = CGRect(x: x, y: y, width: width, height: Self.height)
    stack.frame = bounds.insetBy(dx: 4, dy: 4)
    select(0)
    isHidden = false
    superview?.bringSubviewToFront(self)
  }

  func select(_ index: Int) {
    selectedIndex = index
    for (position, label) in labels.enumerated() {
      let picked = position == index
      label.backgroundColor = picked ? Palette.returnKeyProminent : .clear
      label.textColor = picked ? .white : Palette.keyText
    }
  }

  /// The choice under `x`, in this view's coordinates, held to the row's ends.
  func index(atX x: CGFloat) -> Int {
    guard !labels.isEmpty, bounds.width > 0 else { return 0 }
    let position = Int((x / bounds.width) * CGFloat(labels.count))
    return min(max(position, 0), labels.count - 1)
  }

  func hide() {
    isHidden = true
  }
}

/// Gapla (G58, owner 2026-11-14: [so'zlari: bilim/gapla-goyalar-royxati.md]): the keyboard's languages, in the order
/// the language key steps through them. Uzbek is always on; the app turns the others off (src/lib/keyboardLanguages.ts,
/// read by KeyboardHandoffProvider.keyboardLanguages). The letter rows are KeyboardViewController.letterRows.
private enum KeyboardLanguage: String, CaseIterable {
  // G60: rq is the owner's own Russian on the QWERTY positions, after Apple's ЙЦУКЕН.
  case uz, ru, rq, en, tr

  /// The language key's label: text, so it never looks like the system's globe key on Home-button phones.
  var keyLabel: String {
    switch self {
    case .uz: return "UZ"
    case .ru: return "RU"
    case .rq: return "RQ"
    case .en: return "EN"
    case .tr: return "TR"
    }
  }

  /// The language's own name: on the space bar and in the language key's list.
  var name: String {
    switch self {
    case .uz: return "O'zbekcha"
    case .ru: return "Русский"
    case .rq: return "Русский QWERTY"
    case .en: return "English"
    case .tr: return "Türkçe"
    }
  }

  /// The language the keyboard reports to iOS and the host app (UIInputViewController.primaryLanguage). Uzbek keeps
  /// Info.plist's "mul", as before G58, so host apps treat Uzbek typing exactly as they did.
  var primaryLanguage: String {
    switch self {
    case .uz: return "mul"
    case .ru, .rq: return "ru-RU"
    case .en: return "en-US"
    case .tr: return "tr-TR"
    }
  }

  /// The letters a held key offers, first one picked unless the finger slides to another (handleAlternateLongPress):
  /// Apple's ё on е and ъ on ь in Russian; G60's Russian QWERTY, owner's approved sketch 2026-11-14 ([so'zlari:
  /// bilim/gapla-goyalar-royxati.md]): е → ё э, ь → ъ, й → ю я ё, и → ы, г → ғ, у → ў.
  func alternates(for letter: String) -> [String] {
    switch (self, letter) {
    case (.ru, "е"): return ["ё"]
    case (.ru, "ь"), (.rq, "ь"): return ["ъ"]
    case (.rq, "е"): return ["ё", "э"]
    case (.rq, "й"): return ["ю", "я", "ё"]
    case (.rq, "и"): return ["ы"]
    case (.rq, "г"): return ["ғ"]
    case (.rq, "у"): return ["ў"]
    default: return []
    }
  }

  /// G59/G60: the comma sits right of the space bar instead of in the letter rows, and the iPad's row 2 is indented.
  var commaBesideSpace: Bool { self == .uz || self == .rq }

  /// A letter in capitals: Turkish has its own (i → İ, ı → I); the others take the usual ones.
  func uppercased(_ letter: String) -> String {
    self == .tr ? letter.uppercased(with: Self.turkishLocale) : letter.uppercased()
  }

  private static let turkishLocale = Locale(identifier: "tr_TR")
}

final class KeyboardViewController: UIInputViewController, UIGestureRecognizerDelegate {
  private static func infoString(_ key: String) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static var resolvedContainingAppBundleID: String {
    if let configured = infoString("OpenWhisprContainingAppBundleIdentifier") {
      return configured
    }
    let bundleID = Bundle.main.bundleIdentifier ?? "com.gizmolabs.openwhispr.keyboard"
    let suffix = ".keyboard"
    return bundleID.hasSuffix(suffix) ? String(bundleID.dropLast(suffix.count)) : bundleID
  }

  private static var appUrlScheme: String {
    infoString("OpenWhisprAppScheme") ?? "openwhispr"
  }

  private static var darwinStatusNotificationName: String {
    "\(resolvedContainingAppBundleID).keyboardStatusChanged"
  }
  private static var darwinTranscriptReadyNotificationName: String {
    "\(resolvedContainingAppBundleID).transcriptReady"
  }

  private enum KeyboardLayoutMode {
    case letters
    case numbers
    case symbols
    case emoji
    /// Gapla (G8): the shared clipboard page, in the letter rows' place.
    case clipboard
  }

  private enum KeyRole {
    case character
    case utility
  }

  private enum CachedImages {
    static let shift = UIImage(systemName: "shift")?.withRenderingMode(.alwaysTemplate)
    static let shiftFill = UIImage(systemName: "shift.fill")?.withRenderingMode(.alwaysTemplate)
    static let capslockFill = UIImage(systemName: "capslock.fill")?.withRenderingMode(.alwaysTemplate)

    // Transparent image the size of the animated processing dots, so the button
    // reserves the right space while the real dots are overlaid on top.
    static let processingDotsSpacer = UIGraphicsImageRenderer(
      size: ProcessingDotsView.preferredSize
    ).image { _ in }

    // The full OpenWhispr logo mark: a ring enclosing three rounded bars
    // (short / tall / short), matching the app icon. Rendered as a template so
    // the button tint applies.
    static let brandLogoMark = makeBrandLogoMark()

    // Gapla (G44, owner 2026-11-11 [so'zlari: bilim/gapla-goyalar-royxati.md]): the Gapla mark from the app icon
    // (assets/icon.png) — a text cursor (I-beam) and four sound bars — replaces OpenWhispr's
    // ring-and-bars mark. Shown in the dictation pill and on the trailing toolbar button.
    private static func makeBrandLogoMark() -> UIImage {
      let size: CGFloat = 24
      // The icon's 1024-unit artwork: the mark spans x 195…831 and y 301…722.
      let scale: CGFloat = 22 / 636
      let originX = (size - 636 * scale) / 2 - 195 * scale
      let originY = (size - 421 * scale) / 2 - 301 * scale
      let shapes: [CGRect] = [
        CGRect(x: 195, y: 301, width: 165, height: 55),  // cursor, top
        CGRect(x: 250, y: 301, width: 55, height: 421),  // cursor, stem
        CGRect(x: 195, y: 667, width: 165, height: 55),  // cursor, bottom
        CGRect(x: 431, y: 449, width: 55, height: 126),  // bars: short, tall, tall, short
        CGRect(x: 546, y: 390, width: 55, height: 244),
        CGRect(x: 661, y: 390, width: 55, height: 244),
        CGRect(x: 776, y: 449, width: 55, height: 126),
      ]

      let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
      let image = renderer.image { _ in
        UIColor.black.setFill()
        for shape in shapes {
          UIBezierPath(rect: CGRect(
            x: originX + shape.minX * scale,
            y: originY + shape.minY * scale,
            width: shape.width * scale,
            height: shape.height * scale
          )).fill()
        }
      }
      return image.withRenderingMode(.alwaysTemplate)
    }
  }

  private enum Metrics {
    // The toolbar: tone, the centred dictation pill, agent.
    // Gapla (G46): 36pt like the circle buttons beside it, so the strip fits Apple's bar height.
    static let dictationButtonSize: CGFloat = 36
    /// Where the pill's icon starts; the animated dots overlay the icon's place.
    static let pillLeadingInset: CGFloat = 16
    static let toolbarButtonSize: CGFloat = 36
    static let toolbarButtonInset: CGFloat = 8
    static let processingCancelSize: CGFloat = 30
    static let recordingActionButtonSize: CGFloat = 36
    /// The keyboard grows by this while the agent review card shows: at Apple's height its
    /// text gets about three lines in landscape. Back to 299pt on a 17 Pro, as before the
    /// keys were rebuilt to Apple's.
    static let agentReviewExtraHeight: CGFloat = 40
  }

  private enum KeyboardSize {
    case compact, regular, large

    static func detect(width: CGFloat) -> KeyboardSize {
      let fallbackWidth = UIScreen.main.bounds.width
      let width = width.isFinite && width > 0 ? width : fallbackWidth
      guard width.isFinite, width > 0 else { return .regular }
      if width >= 410 { return .large }
      if width < 375 { return .compact }
      return .regular
    }
  }

  private struct KeyboardMetrics: Equatable {
    /// The toolbar strip, where the pill and buttons centre: from the view's top, its height,
    /// and the gap below it to row 1. The band above the keys is the three together.
    var stripTop: CGFloat
    var stripHeight: CGFloat
    var stripGapBelow: CGFloat
    /// The toolbar's side inset, from the keyboard's edge: tone and agent sit this far in, plus
    /// their own 8pt. The bar itself starts at sideMargin, so the strip reaches past it.
    var stripSideInset: CGFloat
    let sideMargin: CGFloat
    let keyGap: CGFloat
    let keyHeight: CGFloat
    let rowGap: CGFloat
    let bottomPadding: CGFloat
    let keyCornerRadius: CGFloat
    /// Shift, delete, and the #+= / 123 key on the symbol pages, in letter keys.
    var functionKeys: CGFloat = 1.35
    /// 123/ABC and return: 2.5w + 1.5g in portrait, so they end under Z and start under M.
    var bottomKeys: CGFloat = 2.5
    var bottomGaps: CGFloat = 1.5
    /// The webSearch "." key, in letter keys.
    var searchShortcutKeys: CGFloat = 1
    /// Return beside it: 1.75w + 0.75g in portrait (63.33pt on the 17 Pro, 70pt on the Pro Max).
    var narrowReturnKeys: CGFloat = 1.75
    var narrowReturnGaps: CGFloat = 0.75
    var keycaps = Keycaps.portrait

    var topBarHeight: CGFloat { stripTop + stripHeight + stripGapBelow }
    var keyboardHeight: CGFloat { topBarHeight + 4 * keyHeight + 3 * rowGap + bottomPadding }

    // Keys: Apple's iOS 26 keyboard, measured on the iOS 26.5 simulator at 3x: 17 Pro
    // (402pt) and 17 Pro Max (440pt). Margins and gaps stay put; keys grow with width.
    // Toolbar: a strip as tall as the pill, one row gap above row 1. iOS 26 draws ~17pt of
    // glass above the view, where nothing can be drawn, so that glass is the space above the
    // pill; before iOS 26 the strip gets a row gap.
    // Gapla (G46, owner 2026-11-11: [so'zlari: bilim/gapla-goyalar-royxati.md]): measured on his iPhone 14 Pro Max (430pt) screenshots of Apple's
    // keyboard — keys 45pt tall, 6pt gaps, 11pt row gaps, 6.5pt margins (as here); Apple's
    // suggestion bar takes 51.7pt from the keyboard's top to row 1. The Gapla toolbar takes its
    // place: a 36pt strip (pill and circle buttons alike) and an 8pt gap, 48pt with the top gap.
    static let regular = KeyboardMetrics(
      stripTop: 0, stripHeight: 36, stripGapBelow: 8, stripSideInset: 3,
      sideMargin: 6.5, keyGap: 6, keyHeight: 43, rowGap: 11, bottomPadding: 3,
      keyCornerRadius: 8
    )
    // 17 Pro Max: rows sit 2pt higher than on the 17 Pro's 3pt padding.
    static let large = KeyboardMetrics(
      stripTop: 0, stripHeight: 36, stripGapBelow: 8, stripSideInset: 4,
      sideMargin: 6.5, keyGap: 6, keyHeight: 45, rowGap: 11, bottomPadding: 5,
      keyCornerRadius: 8
    )
    // Home-button phones (needsInputModeSwitchKey, no system bar): iPhone SE (3rd gen),
    // 375pt at 2x. Same margins; shorter keys, wider row gaps.
    static let homeButton = KeyboardMetrics(
      stripTop: 0, stripHeight: 36, stripGapBelow: 9, stripSideInset: 3,
      sideMargin: 6.5, keyGap: 6, keyHeight: 42, rowGap: 12, bottomPadding: 4,
      keyCornerRadius: 8
    )
    // Under 375pt without a globe key: Display Zoom on Face ID phones (320pt), which
    // can't be measured here. Apple's margins, shorter keys.
    static let compact = KeyboardMetrics(
      stripTop: 0, stripHeight: 36, stripGapBelow: 7, stripSideInset: 3,
      sideMargin: 6.5, keyGap: 6, keyHeight: 39, rowGap: 10, bottomPadding: 3,
      keyCornerRadius: 7
    )
    // 17 Pro landscape: 123 and return span two keys (Q–W, O–P); key corners as in
    // portrait. No glass is drawn above the view here; the pill sits 5pt from the top and
    // from row 1, so the keys keep Apple's landscape height.
    static let landscape = KeyboardMetrics(
      stripTop: 5, stripHeight: 40, stripGapBelow: 5, stripSideInset: 4,
      sideMargin: 4, keyGap: 6, keyHeight: 27.33, rowGap: 8, bottomPadding: 4,
      keyCornerRadius: 8, functionKeys: 1.33, bottomKeys: 2, bottomGaps: 1,
      searchShortcutKeys: 0.785, narrowReturnKeys: 1.435, narrowReturnGaps: 0, keycaps: .landscape
    )

    // iPad, docked across the screen: the rows follow Apple's iPad keyboard (G46,
    // addTabletLetterRows); the heights keep the 309pt keyboard and the gap above the strip
    // it had before (the iOS 26 glass above the view is unverified on iPad).
    static let tablet = KeyboardMetrics(
      stripTop: 7, stripHeight: 40, stripGapBelow: 11, stripSideInset: 4,
      sideMargin: 6.5, keyGap: 6, keyHeight: 53, rowGap: 11, bottomPadding: 6,
      keyCornerRadius: 8
    )

    /// Gapla: the toolbar's own gap above the pill on iOS 26 portrait phones. 4pt keeps the
    /// pill off the edge where iOS draws no glass, and the toolbar near Apple's 51.7pt where it does.
    static let glassFallbackStripTop: CGFloat = 4

    static func current(for inputs: LayoutInputs) -> KeyboardMetrics {
      if inputs.tablet { return .tablet }
      if inputs.landscape { return .landscape }
      var metrics: KeyboardMetrics
      let size = KeyboardSize.detect(width: inputs.width)
      if inputs.homeButton, size != .large {
        metrics = .homeButton
      } else {
        switch size {
        case .compact: metrics = .compact
        case .regular: metrics = .regular
        case .large: metrics = .large
        }
      }
      // Before iOS 26 nothing is drawn above the view, so the strip keeps a row gap above it
      // (unverified here: only the iOS 26.5 simulator is installed).
      if #unavailable(iOS 26) {
        metrics.stripTop = metrics.rowGap
      } else {
        // Gapla: on iOS 26.5 the ~17pt of glass above the view shows only in some apps
        // (Messages); in others the view starts at the keyboard's top edge and the toolbar
        // touched it (owner's screenshots, 2026-11-11). The extension can't tell which, so a
        // small gap of its own keeps the toolbar off the edge in every app.
        metrics.stripTop = Self.glassFallbackStripTop
      }
      return metrics
    }
  }

  /// The bottom row Apple shows for a keyboard type: the field keys between space and
  /// return, and how wide they are.
  private struct BottomRowLayout: Equatable {
    enum ShortcutWidth {
      case shared  // URL: the keys share the space bar's span
      case half    // email, twitter: half a 123 key each
      case letter  // webSearch: one letter key
    }

    var shortcuts: [String] = []
    var shortcutWidth = ShortcutWidth.half
    var showsSpace = true
    var showsReturn = true
    var narrowReturn = false
    /// Apple draws email's and web search's "." 4pt higher than a typed period (17 Pro).
    var raisesPeriod = false

    /// `letters`: the page showing. Twitter's @ and # replace return on letters only; its
    /// 123 and #+= pages have Apple's usual space and return (iOS 26.5).
    static func forKeyboardType(_ type: UIKeyboardType?, letters: Bool) -> BottomRowLayout {
      switch type {
      case .twitter? where !letters: return BottomRowLayout()
      case .URL?: return BottomRowLayout(shortcuts: [".", "/", ".com"], shortcutWidth: .shared, showsSpace: false)
      case .emailAddress?: return BottomRowLayout(shortcuts: ["@", "."], raisesPeriod: true)
      case .webSearch?:
        return BottomRowLayout(shortcuts: ["."], shortcutWidth: .letter, narrowReturn: true, raisesPeriod: true)
      case .twitter?: return BottomRowLayout(shortcuts: ["@", "#"], showsReturn: false)
      default: return BottomRowLayout()
      }
    }
  }

  /// Width constraints refreshBottomRow switches between, rebuilt with the keys.
  private struct BottomRowConstraints {
    var halfWidth: [NSLayoutConstraint] = []
    var letterWidth: [NSLayoutConstraint] = []
    var sharedWidth: [NSLayoutConstraint] = []
    var returnWidth: NSLayoutConstraint?
    var narrowReturnWidth: NSLayoutConstraint?
  }

  /// Apple's iOS 26 return key per returnKeyType: a glyph, and blue for the actions.
  private struct ReturnKeyStyle: Equatable {
    let symbolName: String
    let accessibilityLabel: String
    let isProminent: Bool
    /// From UIKit's centring to Apple's position (17 Pro): its return glyphs sit 1.83pt above
    /// the key's centre, ✓ 1.5pt, ↵ 0.5pt above and the phone 6.33pt below.
    var glyphOffsetY: CGFloat = -1.83

    static func forReturnKeyType(_ type: UIReturnKeyType?) -> ReturnKeyStyle {
      switch type ?? .default {
      case .go: return ReturnKeyStyle(symbolName: "arrow.right", accessibilityLabel: "O'tish", isProminent: true)
      case .join: return ReturnKeyStyle(symbolName: "arrow.right", accessibilityLabel: "Qo'shilish", isProminent: true)
      case .route: return ReturnKeyStyle(symbolName: "arrow.right", accessibilityLabel: "Yo'nalish", isProminent: true)
      case .search, .google, .yahoo:
        return ReturnKeyStyle(symbolName: "magnifyingglass", accessibilityLabel: "Qidirish", isProminent: true)
      case .send: return ReturnKeyStyle(symbolName: "arrow.up", accessibilityLabel: "Yuborish", isProminent: true)
      case .done:
        return ReturnKeyStyle(symbolName: "checkmark", accessibilityLabel: "Tayyor", isProminent: true, glyphOffsetY: -1.5)
      case .emergencyCall:
        return ReturnKeyStyle(
          symbolName: "phone", accessibilityLabel: "Favqulodda qo'ng'iroq", isProminent: true, glyphOffsetY: 6.33
        )
      case .next: return ReturnKeyStyle(symbolName: "chevron.right", accessibilityLabel: "Keyingisi", isProminent: false)
      case .continue:
        return ReturnKeyStyle(symbolName: "chevron.right", accessibilityLabel: "Davom etish", isProminent: false)
      default:
        return ReturnKeyStyle(
          symbolName: "return.left", accessibilityLabel: "Yangi qator", isProminent: false, glyphOffsetY: -0.5
        )
      }
    }
  }

  private struct ReturnKeyState: Equatable {
    let style: ReturnKeyStyle
    /// Greyed while the field is empty and asks for that (enablesReturnKeyAutomatically).
    let isDisabled: Bool
  }

  /// What the key metrics and the built keys depend on.
  private struct LayoutInputs: Equatable {
    var width: CGFloat
    var landscape: Bool
    /// needsInputModeSwitchKey: the globe key shows, on Home-button iPhones.
    var homeButton: Bool
    var tablet: Bool

    /// Equal but for a sub-point width change, which is only pixel rounding.
    func matches(_ other: LayoutInputs) -> Bool {
      var widthAligned = other
      widthAligned.width = width
      return abs(width - other.width) <= 1 && widthAligned == self
    }
  }

  private var metrics: KeyboardMetrics = .current(
    for: LayoutInputs(width: UIScreen.main.bounds.width, landscape: false, homeButton: false, tablet: false)
  )

  private let rootStack = UIStackView()
  // The toolbar: tone, the centred dictation pill, agent. The strip guide is the
  // pill-high strip at the top of the band, where the buttons centre.
  private let topBar = UIView()
  private let stripGuide = UILayoutGuide()
  private var stripConstraints: [NSLayoutConstraint] = []
  private let recordButton = UIButton(type: .system)
  private let recordButtonBackground = PillBackgroundView()
  private let processingDots = ProcessingDotsView()
  // Sits beside the processing pill ("Transcribing"/"Cleaning up") to abandon
  // the in-flight transcription. Hidden in every other state.
  private let processingCancelButton = VisibilityReportingButton(type: .system)
  private let toneButton = KeyButton(type: .system)
  private let keyboardRowsStack = KeyboardRowsStack()
  private let lettersRowsStack = UIStackView()
  private let numbersRowsStack = UIStackView()
  private let symbolsRowsStack = UIStackView()
  private let emojiRowsStack = UIStackView()
  private var emojiButton: KeyButton?
  /// G59: Uzbek's comma, right of the space bar (makeCommaKey, refreshCommaKey).
  private var commaButton: KeyButton?
  // Gapla (G8): the toolbar's clipboard button and its page, built the first time it opens.
  private let clipboardRowsStack = UIStackView()
  private let clipboardButton = KeyButton(type: .system)
  private var clipboardPanel: GaplaClipboardPanel?
  // Gapla (G41, G55): up to three words in the toolbar's place while typing (GaplaTavsiya.swift).
  private let tavsiyaBar = GaplaTavsiyaBar(textColor: Palette.keyText, pressedColor: Palette.keyBackground)
  /// The letters of the current word typed on the keys. A finished word counts toward the owner's list only when the
  /// field shows the same letters before the cursor, so dictated or pasted text never counts.
  private var tavsiyaTypedWord = ""
  /// The last word counted, so the next one counts with it as a pair.
  private var tavsiyaLastCounted: String?
  private let keyPopup = KeyPopupView()
  /// G60: the held key's letters to choose from (handleAlternateLongPress).
  private let alternatesPopup = AlternatesPopupView()
  private var alternateChoices: [String] = []
  // One Uzbek letter key's width, (row width − 10 gaps) / 11 (guideKeysPerRow), in every language. Every key width is
  // a multiple of it, so the layout follows the screen width without any width constants.
  private let keyWidthGuide = UILayoutGuide()
  private var keyWidthGuideConstraint: NSLayoutConstraint?

  private let recordingCanvas = UIView()
  // Shown whenever hasFullAccess is false, in place of the keys AND the
  // dictation strip — the amber pill and this panel are never on screen
  // together. Built lazily: the healthy path never needs it and the
  // extension's memory budget is tight.
  private let fullAccessPanel = UIView()
  private let fullAccessPanelTitleLabel = UILabel()
  private let fullAccessPanelBodyLabel = UILabel()
  private let fullAccessPanelCloseButton = UIButton(type: .system)
  private var fullAccessPanelGlobeButton: KeyButton?
  private var didSetupFullAccessPanel = false
  // Controller-lifetime on purpose: a fresh keyboard session shows the panel
  // again, and the App Group is unavailable for persistence.
  private var didDismissFullAccessPanel = false
  // Top-of-canvas header, shown only for agent recordings ("Tell {name} What to
  // Write"); hidden for normal dictation, which has no title.
  private let recordingHeaderLabel = UILabel()
  // Gapla (G47): the particle orb in the keyboard's middle replaces the waveform and the ✕/✓
  // buttons. Tap the circle to send, anywhere else to cancel.
  private let recordingOrb = RecordingOrbView()
  // The keys at 16 %, blurred 1.5 pt, while the orb is up (the live keys fade out under it).
  private let dimmedKeysView = UIImageView()

  private let agentButton = KeyButton(type: .system)
  /// Gapla (G56): the translator (文A), beside the dictation button; opens the app's translator page.
  private let translateButton = KeyButton(type: .system)

  private let agentReviewCanvas = UIView()
  private let agentReviewHeaderLabel = UILabel()
  private let agentReviewTextView = UITextView()
  private let agentReviewInsertButton = UIButton(type: .system)
  private let agentReviewDismissButton = UIButton(type: .system)
  private let agentReviewRegenerateButton = UIButton(type: .system)
  private let agentReviewFollowUpButton = UIButton(type: .system)
  private let agentReviewPagerPrevButton = UIButton(type: .system)
  private let agentReviewPagerNextButton = UIButton(type: .system)
  private let agentReviewPagerLabel = UILabel()
  private let agentReviewActionStack = UIStackView()
  // "Open OpenWhispr" wake-links overlaying the regenerate/follow-up buttons,
  // enabled only when the app's heartbeat is stale (both actions need it alive).
  private var agentReviewRegenerateWakeLink: UIHostingController<DictationLinkView>?
  private var agentReviewFollowUpWakeLink: UIHostingController<DictationLinkView>?

  private var characterButtons: [KeyButton] = []
  private var shiftButton: KeyButton?
  private var modeButton: KeyButton?
  private var spaceButton: KeyButton?
  private var returnButton: KeyButton?
  // Gapla (G46, iPad): Apple's iPad keyboard puts a shift at each end of row 3, a second
  // .?123 key and a hide-keyboard key in the bottom row, and a return key on every page.
  // shiftButton, modeButton and returnButton keep the first of each; these hold the rest.
  private var builtForTablet = false
  private var tabletExtraShiftButtons: [KeyButton] = []
  private var tabletExtraModeButtons: [KeyButton] = []
  private var tabletPageReturnButtons: [KeyButton] = []
  // The bottom row's field-specific keys (URL ". / .com", email "@ .", …) and the width
  // constraints refreshBottomRow switches between.
  private var shortcutButtons: [KeyButton] = []
  private var bottomRowConstraints = BottomRowConstraints()
  private var appliedBottomRowLayout: BottomRowLayout?
  /// What the return key last drew, so a keystroke that doesn't change it skips the redraw.
  private var appliedReturnKeyState: ReturnKeyState?
  /// The field the keyboard last typed into, and the last one seen reporting text.
  private var typedDocument: UUID?
  private var reportingDocument: UUID?
  private var dictationLinkHosting: UIHostingController<DictationLinkView>?
  // Detected once at setup (the host is fixed for the extension's lifetime).
  // Avoids calling the heavy private-API host detection on every button refresh.
  private var hostIsOwnApp = false
  private var didRequestCancelForCurrentSession = false

  private var layoutMode: KeyboardLayoutMode = .letters
  /// Gapla (G58): the language the letters are in, and the languages the app has on (Uzbek always), in key order.
  private var keyboardLanguage: KeyboardLanguage = .uz
  private var enabledLanguages: [KeyboardLanguage] = KeyboardLanguage.allCases
  /// The letter key held for its alternate (handleAlternateLongPress): its preview stays up until the finger lifts.
  private weak var alternateHeldKey: KeyButton?
  /// Something was typed on the 123/#+= pages since leaving letters; space then returns to
  /// letters, as on Apple's keyboard (a bare space keeps the page).
  private var typedOnSymbolPage = false
  private var isShiftEnabled = true
  private var isCapsLocked = false
  private var lastShiftTapDate: Date?

  private var deleteRepeatTimer: Timer?
  private var deleteRepeatCount = 0
  private var issueResetTimer: Timer?
  private var recordingPollTimer: Timer?
  private var waitForTranscriptTimer: Timer?
  /// Gapla (G57): brings the keys back if the orb is still spinning this long after the stop.
  private var processingKeysReturnTimer: Timer?
  /// When the orb moved to processing (CACurrentMediaTime), so the stop tap's own double tap is not read as a
  /// second tap.
  private var processingOrbStartedAt: CFTimeInterval = 0
  private var isObservingHandoffNotifications = false
  private var didBuildKeyboard = false
  private var lastMetricsWidth: CGFloat = 0
  private var appliedLayoutInputs: LayoutInputs?
  private var keysBuiltWithGlobe = false
  private var rootHeightConstraint: NSLayoutConstraint?
  private var topBarHeightConstraint: NSLayoutConstraint?
  private var keyboardHeightConstraint: NSLayoutConstraint?
  private var rowHeightConstraints: [NSLayoutConstraint] = []
  private var isRemoteRecordingActive = false
  private var isDarwinStartPending = false
  private var darwinStartPendingTicks = 0
  private var darwinStartActiveTicks = 0
  private var didRequestStopForCurrentSession = false
  // The job the user cancelled from the processing pill. A transcript that
  // still lands for it (the app finished before observing the cancel) is
  // discarded by job id instead of being inserted into the field.
  private var cancelledProcessingJobId: String?

  // Agent flow state. isAgentGenerating gates the "Writing" pill + result poll so
  // it can't collide with a normal-dictation transcription. The Link overlay
  // drives the not-ready handoff exactly like the record button's.
  private var agentLinkHosting: UIHostingController<DictationLinkView>?
  /// Gapla (G56, owner 2026-11-15: «shu joydan chiqmasdan turib qilsa bo'lmasmidi?» … «til tanlash va ishlash oson
  /// blishi kerak»): the translator inside the keyboard (GaplaTarjimon.swift). Non-nil while it is open: the keys, the
  /// clipboard and dictation then write into this text instead of the field.
  private var translatorText: String?
  private var translatorViewsInstalled = false
  private lazy var translatorPanel = GaplaTarjimonPanel(
    accent: Palette.accentTint,
    keyBackground: Palette.keyBackground,
    textColor: Palette.keyText
  )
  private lazy var translatorResults = GaplaTarjimonNatijaView(
    accent: Palette.accentTint,
    keyBackground: Palette.keyBackground,
    textColor: Palette.keyText
  )
  private lazy var translatorClient = GaplaTarjimonClient(accessGroup: "group.\(Self.resolvedContainingAppBundleID)")
  private var isTranslatorOpen: Bool { translatorText != nil }
  /// The panel and the stack's gap above the toolbar; the keys keep their height below.
  private var translatorExtraHeight: CGFloat {
    isTranslatorOpen ? GaplaTarjimonPanel.height + rootStack.spacing : 0
  }
  // The current recording is an agent instruction (spoken → generated), so its
  // canvas header and post-stop state differ from normal dictation. Set when the
  // agent button starts recording in place; cleared on reset/exit.
  private var isAgentRecordingActive = false
  // The recording-canvas header shown for the current agent recording. Compose
  // uses "Tell {name} What to Write"; a follow-up overrides it with "Describe
  // your changes". nil ⇒ the compose default (resolved when the canvas shows).
  private var agentRecordingHeaderText: String?
  // Example instruction shown under the waveform (in place of "Listening")
  // while an agent recording is live. One random pick per recording, stashed at
  // record-start so canvas re-shows don't reshuffle it.
  // Selection-flavored hints stay in the shared pool even when nothing is
  // highlighted — they're the only discoverability that highlighted text can
  // be operated on.
  private static let agentComposeHints = [
    "Belgilangan matnni ingliz tiliga tarjima qiling",
    "Kechikkanim uchun rasmiy uzr so'rab xat yozing",
    "Belgilangan matnni ro'yxat qilib bering",
    "Muddatni uzaytirishni so'rab yozing",
    "Hamkasbim Dilnozaga tug'ilgan kun tabrigini yozing",
  ]
  private static let agentFollowUpHints = [
    "Oddiyroq qiling",
    "Oxiriga xayrlashuv so'zini qo'shing",
    "Qisqaroq qiling",
  ]
  private var agentRecordingHint: String?

  // An example to say, unless the app's own walkthrough is telling the user what to say.
  private func agentHint(from hints: [String]) -> String? {
    KeyboardHandoffProvider.shared.agentHintsHidden() ? nil : hints.randomElement()
  }
  private var isAgentGenerating = false
  private var waitForAgentResultTimer: Timer?
  private var agentReviewNoteResetTimer: Timer?
  private var isAgentReviewShown = false
  // Pager state, local to the shown card: every generated version and the one
  // currently displayed. Switching pages only updates the text view (no App
  // Group writes); insert uses agentReviewVersions[agentReviewActiveIndex].
  private var agentReviewVersions: [String] = []
  private var agentReviewActiveIndex = 0
  // The session the shown reply belongs to, so follow-up/regenerate thread onto
  // it. Empty when no card is shown.
  private var agentReviewSessionId = ""
  // A card action (regenerate or follow-up) is generating with the previous
  // versions retained underneath: an error/app-death/cancel restores the card
  // (existing versions stay insertable) instead of dropping to idle, per the plan.
  // The keyboard keeps the card's extra height until the action ends, so it doesn't
  // shrink and grow again under the host app.
  private var isAgentActionInFlight = false {
    didSet { if isViewLoaded { view.setNeedsLayout() } }
  }
  // Set while a regenerate is generating: the session/recording-job is unchanged
  // so the pre-action result is still readable. Any result adopted (poll OR the
  // Darwin agent_ready path) must be newer than this action timestamp. nil for
  // the initial compose and follow-up (a fresh recording job supersedes instead).
  private var agentActionMinUpdatedAtMs: Int64?
  // Rejection memory for agent generations the user cancelled or that timed out
  // in the keyboard while the app kept streaming. The app can race past its own
  // cancel checkpoint and write agent_ready + a result seconds later (or on the
  // next keyboard open, ≤10 min); every adoption point (poll, Darwin agent_ready,
  // resume-on-reopen) drops a result matching one of these so a cancelled/timed-
  // out card can't pop up unprompted. Mirrors `cancelledProcessingJobId`.
  //   compose/follow-up: the recording jobId the result carries.
  //   regenerate: the action's atMs (its result's jobId is "<atMs>-<uuid>").
  private var rejectedAgentJobIds: Set<String> = []
  private var rejectedAgentActionAtMs: Set<Int64> = []

  private var layoutWidth: CGFloat {
    view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
  }

  private var isLandscapeLayout: Bool {
    switch traitCollection.verticalSizeClass {
    case .compact: return true
    case .regular: return false
    default: return UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }
  }

  private func layoutInputs(width: CGFloat) -> LayoutInputs {
    LayoutInputs(
      width: width,
      landscape: isLandscapeLayout,
      homeButton: needsInputModeSwitchKey,
      // A floating iPad keyboard is phone-sized and takes the phone layout.
      tablet: UIDevice.current.userInterfaceIdiom == .pad && width >= 600
    )
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    KeyboardLog.ui.info("Keyboard loaded. hasFullAccess=\(self.hasFullAccess, privacy: .public)")
    KeyboardLog.echo("Keyboard loaded. hasFullAccess=\(self.hasFullAccess)")
    metrics = KeyboardMetrics.current(for: layoutInputs(width: layoutWidth))
    // G54: anything drawn in the default tint (system blue) takes the Gapla accent instead.
    view.tintColor = Palette.accentTint
    GaplaTavsiya.shared.onChange = { [weak self] in self?.refreshTavsiya() }
    // G58: the keys are built in the language last used.
    loadKeyboardLanguages()
    setupLayout()
    applyKeyboardHeight()
    refreshRecordButton()
    buildKeyboardIfNeeded()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    refreshMetricsIfNeeded()
    applyKeyboardHeight()
  }

  private func applyKeyboardHeight() {
    // The keys keep their height at the bottom; the card above them takes the extra.
    let showsCardHeight = isAgentReviewShown || isAgentActionInFlight
    let keyboardHeight = metrics.keyboardHeight + translatorExtraHeight
      + (showsCardHeight ? Metrics.agentReviewExtraHeight : 0)

    if let keyboardHeightConstraint {
      keyboardHeightConstraint.constant = keyboardHeight
    } else {
      let constraint = view.heightAnchor.constraint(equalToConstant: keyboardHeight)
      constraint.priority = UILayoutPriority(999)
      constraint.isActive = true
      keyboardHeightConstraint = constraint
    }
    preferredContentSize = CGSize(width: view.bounds.width, height: keyboardHeight)
  }

  override func textDidChange(_ textInput: UITextInput?) {
    super.textDidChange(textInput)
    noteFieldReport()
    syncShiftWithContextIfNeeded()
    refreshFieldAwareKeys()
    _ = consumePendingTranscriptIfAvailable(trigger: "textDidChange")
    refreshTavsiya()
  }

  // Gapla (G41): the cursor moved (a tap in the text): the suggestions follow the word under it.
  override func selectionDidChange(_ textInput: UITextInput?) {
    super.selectionDidChange(textInput)
    refreshTavsiya()
  }

  // The field's text and traits may not be known at viewDidLoad, and iOS needn't send
  // textDidChange when the keyboard opens: shift and the return key follow the field here.
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // G58: languages turned on or off in the app since the keyboard was last up.
    if loadKeyboardLanguages() { applyKeyboardLanguageChange() }
    noteFieldReport()
    syncShiftWithContextIfNeeded()
    refreshFieldAwareKeys()
    refreshTavsiya()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    logMemory("viewDidAppear")
    // Without Full Access every write below is a no-op and every resume gate
    // reads a dead App Group. Today this method reaches refreshRecordButton()
    // anyway, but only because four separate resume gates each happen to fail
    // closed — an explicit guard means a future early return can't silently
    // reintroduce a dead-but-healthy-looking keyboard.
    guard hasFullAccess else {
      refreshRecordButton()
      return
    }
    KeyboardHandoffProvider.shared.markShown()
    KeyboardHandoffProvider.shared.storeHostReturnInfo(from: self)
    // Gapla (G41): the saved word list, fetched again from the server when it is due (G58: in Uzbek only).
    startTavsiyaIfOn()
    refreshTavsiya()
    refreshToneButton()
    refreshAgentButton()
    insertPendingTranslation()
    // The review card owns the screen until the user acts on it; don't let a
    // stale recording flag or resume path tear it down on reappear. Re-gate its
    // controls so the regenerate/follow-up wake-links reflect current app
    // liveness after time away.
    if isAgentReviewShown {
      refreshAgentReviewControls()
      startHandoffObservers()
      startRecordingPoll()
      return
    }
    let consumedPendingTranscript = consumePendingTranscriptIfAvailable(trigger: "viewDidAppear")
    isRemoteRecordingActive = KeyboardHandoffProvider.shared.isRecordingActive()
    if isRemoteRecordingActive {
      // Recover the agent flag if the keyboard was rebuilt mid-recording, so the
      // canvas header/accent and the post-stop generating path are correct.
      isAgentRecordingActive = KeyboardHandoffProvider.shared.hasAgentJobForCurrentRecording()
      enterRecordingMode()
    } else if !consumedPendingTranscript && !resumeFreshHandoffState() {
      refreshRecordButton()
    }
    logRecordMarker("viewDidAppear", extra: "consumedPending=\(consumedPendingTranscript)")
    startHandoffObservers()
    startRecordingPoll()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    logRecordMarker("viewWillDisappear")
    // G56: an open translator does not come back with the next field.
    closeTranslator()
    resetRecordingOrbImmediately()
    // Gapla (G8): the clipboard list is never left open to go stale; it reloads when reopened.
    if layoutMode == .clipboard { returnToLetters() }
    // Gapla (G41): what was counted is saved (and sent when due); the next opening starts a new run. G58: in another
    // language it is only saved; it goes the next time the keyboard is in Uzbek.
    if tavsiyaOn {
      GaplaTavsiya.shared.flush()
    } else {
      GaplaTavsiya.shared.save()
    }
    tavsiyaTypedWord = ""
    tavsiyaLastCounted = nil
    stopDeleteRepeating()
    issueResetTimer?.invalidate()
    waitForTranscriptTimer?.invalidate()
    waitForAgentResultTimer?.invalidate()
    agentReviewNoteResetTimer?.invalidate()
    stopRecordingPoll()
    stopHandoffObservers()
  }

  /// Gapla (G57): one line in the device log with the extension's memory footprint — iOS ends a keyboard extension
  /// near its 48–70 MB limit, and the system keyboard comes up instead («ochilmadi»). Release logger, notice level,
  /// so it reaches the device log without a debug build; grep it for «gapla-xotira».
  private func logMemory(_ moment: String) {
    let footprint = String(format: "%.1f", RecordingOrbView.footprintMB())
    KeyboardLog.ui.notice("gapla-xotira \(moment, privacy: .public) footprintMB=\(footprint, privacy: .public)")
  }

  deinit {
    stopDeleteRepeating()
    issueResetTimer?.invalidate()
    processingKeysReturnTimer?.invalidate()
    waitForTranscriptTimer?.invalidate()
    waitForAgentResultTimer?.invalidate()
    agentReviewNoteResetTimer?.invalidate()
    stopRecordingPoll()
    stopHandoffObservers()
  }

  @objc private func handleCharacterKeyTapped(_ sender: KeyButton) {
    guard let output = sender.output else { return }
    playKeyClick()

    // G58: capitals in the keyboard's language (Turkish i → İ).
    let insertion = layoutMode == .letters && isShiftEnabled ? keyboardLanguage.uppercased(output) : output
    // Gapla: the apostrophe is part of Uzbek words (ma'no, san'at), so it stays straight, as
    // the Gapla bridge writes it. Since G39 it sits on the 123 page only.
    let text = layoutMode == .letters || output == "'"
      ? insertion
      : (smartQuoteSubstitution(for: insertion) ?? insertion)
    // Gapla (G41): letters and the apostrophe build the word being typed; any other key ends it. G58: Uzbek only.
    if tavsiyaOn, text.count == 1, let character = text.first, GaplaTavsiya.isWordCharacter(character) {
      tavsiyaTypedWord += text
    } else {
      countTypedWordIfFinished()
    }
    typeText(text)
    if layoutMode != .letters {
      // Apple's apostrophe returns to letters at once ("rock 'n' roll", "'90s").
      if output == "'" { returnToLetters() } else { typedOnSymbolPage = true }
    }

    // Shift ends after one letter unless the field capitalizes the next one too (all
    // characters). Decided from the field, not the text before the cursor: iOS doesn't
    // report the keyboard's own inserts back in time, and some hosts never report text.
    if layoutMode == .letters && !isCapsLocked {
      let shiftStaysOn = fieldCapitalization == .allCharacters
      if shiftStaysOn != isShiftEnabled {
        isShiftEnabled = shiftStaysOn
        refreshShiftState()
      }
    }
    refreshAfterEdit()
  }

  // Gapla (G39, owner 2026-11-11): [so'zlari: bilim/gapla-goyalar-royxati.md] — holding the letters-page
  // comma types a full stop instead; the held press cancels the comma.
  @objc private func handleCommaLongPress(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .began else { return }
    playKeyClick()
    countTypedWordIfFinished()
    typeText(".")
    syncShiftWithContextIfNeeded()
    refreshAfterEdit()
  }

  @objc private func handleCharacterKeyDown(_ sender: KeyButton) {
    guard let text = sender.title(for: .normal) else { return }
    keyPopup.show(
      text,
      font: sender.titleLabel?.font ?? metrics.keycaps.uppercase,
      keyFrame: sender.convert(sender.bounds, to: rootStack),
      keyCornerRadius: metrics.keyCornerRadius,
      container: rootStack.layoutMarginsGuide.layoutFrame,
      owner: sender
    )
  }

  @objc private func handleCharacterKeyReleased(_ sender: KeyButton) {
    // G58: a key held for its alternate keeps the alternate's preview until the finger lifts.
    guard sender !== alternateHeldKey else { return }
    keyPopup.hide(owner: sender, after: 0.05)
  }

  /// Gapla (G58, G60): holding a letter with alternates (Russian е → ё; Russian QWERTY й → ю я ё …) shows them above
  /// the key; the finger slides to one and lifting types it. The held press cancels the letter, as the held comma's
  /// full stop does (G39). Lifting without moving types the first, so a one-alternate key works on a plain hold.
  @objc private func handleAlternateLongPress(_ gesture: UILongPressGestureRecognizer) {
    guard let key = gesture.view as? KeyButton else { return }
    switch gesture.state {
    case .began:
      guard let output = key.output else { return }
      let shifted = layoutMode == .letters && isShiftEnabled
      let choices = keyboardLanguage.alternates(for: output).map { shifted ? keyboardLanguage.uppercased($0) : $0 }
      guard !choices.isEmpty else { return }
      playKeyClick()
      alternateHeldKey = key
      alternateChoices = choices
      keyPopup.hide(owner: key)
      alternatesPopup.show(
        choices,
        font: key.titleLabel?.font ?? metrics.keycaps.uppercase,
        keyFrame: key.convert(key.bounds, to: rootStack),
        container: rootStack.layoutMarginsGuide.layoutFrame
      )
    case .changed:
      guard alternateHeldKey === key else { return }
      alternatesPopup.select(alternatesPopup.index(atX: gesture.location(in: alternatesPopup).x))
    case .ended:
      guard alternateHeldKey === key else { return }
      let choices = alternateChoices
      let index = alternatesPopup.selectedIndex
      endAlternatePick()
      guard choices.indices.contains(index) else { return }
      let text = choices[index]
      if tavsiyaOn { tavsiyaTypedWord += text }
      typeText(text)
      // Shift ends after the letter, as after a tapped one.
      if layoutMode == .letters && !isCapsLocked {
        let shiftStaysOn = fieldCapitalization == .allCharacters
        if shiftStaysOn != isShiftEnabled {
          isShiftEnabled = shiftStaysOn
          refreshShiftState()
        }
      }
      refreshAfterEdit()
    case .cancelled, .failed:
      guard alternateHeldKey === key else { return }
      endAlternatePick()
    default:
      break
    }
  }

  private func endAlternatePick() {
    alternateHeldKey = nil
    alternateChoices = []
    alternatesPopup.hide()
  }

  @objc private func handleShiftTapped() {
    playKeyClick()
    let now = Date()

    if isCapsLocked {
      isCapsLocked = false
      isShiftEnabled = false
      lastShiftTapDate = nil
      refreshShiftState()
      return
    }

    if isShiftEnabled,
      let previousTap = lastShiftTapDate,
      now.timeIntervalSince(previousTap) < 0.33
    {
      isCapsLocked = true
      isShiftEnabled = true
    } else {
      isCapsLocked = false
      isShiftEnabled.toggle()
    }

    lastShiftTapDate = now
    refreshShiftState()
  }

  @objc private func handleBackspaceTapped() {
    playKeyClick()
    if isTranslatorOpen {
      deleteFromTranslator(word: false)
      return
    }
    textDocumentProxy.deleteBackward()
    if !tavsiyaTypedWord.isEmpty { tavsiyaTypedWord.removeLast() }
    // "Hello. W" ⌫ starts a sentence again.
    syncShiftWithContextIfNeeded()
    refreshAfterEdit()
  }

  @objc private func handleBackspaceLongPress(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      (gesture.view as? KeyButton)?.isLongPressed = true
      tavsiyaTypedWord = ""
      startDeleteRepeating()
    case .ended, .cancelled, .failed:
      (gesture.view as? KeyButton)?.isLongPressed = false
      stopDeleteRepeating()
      syncShiftWithContextIfNeeded()
      refreshAfterEdit()
    default:
      break
    }
  }

  /// Bottom row 123/ABC: letters ⇄ numbers.
  @objc private func handleModeKeyTapped() {
    playKeyClick()
    layoutMode = layoutMode == .letters ? .numbers : .letters
    typedOnSymbolPage = false
    isCapsLocked = false
    isShiftEnabled = layoutMode == .letters ? shouldAutoCapitalize() : false
    refreshVisibleKeyboardMode()
    refreshShiftState()
  }

  /// Row 3 #+= / 123: numbers ⇄ symbols.
  @objc private func handlePageKeyTapped() {
    playKeyClick()
    layoutMode = layoutMode == .numbers ? .symbols : .numbers
    refreshVisibleKeyboardMode()
  }

  @objc private func handleSpaceTapped() {
    playKeyClick()
    countTypedWordIfFinished()
    if !applyDoubleSpacePeriod() {
      typeText(" ")
    }
    if layoutMode != .letters && typedOnSymbolPage { returnToLetters() }
    syncShiftWithContextIfNeeded()
    refreshAfterEdit()
  }

  // Gapla (G37, owner 2026-11-11): hold the space bar, then slide left or right to move the
  // text cursor, as on Apple's keyboard. Every `spaceCursorStep` points of travel moves the
  // cursor one character; the held press cancels the space it would otherwise type.
  private static let spaceCursorStep: CGFloat = 9
  private var spaceCursorLastX: CGFloat = 0
  private var spaceCursorActive = false

  @objc private func handleSpaceLongPress(_ gesture: UILongPressGestureRecognizer) {
    let x = gesture.location(in: view).x
    switch gesture.state {
    case .began:
      // G56: the translator's line has no cursor to move.
      if isTranslatorOpen { return }
      spaceCursorActive = true
      spaceCursorLastX = x
      // The cursor leaves the word: it no longer counts as typed here.
      tavsiyaTypedWord = ""
      tavsiyaLastCounted = nil
      (gesture.view as? KeyButton)?.isLongPressed = true
      setSpaceCursorMode(true)
    case .changed:
      guard spaceCursorActive else { return }
      let steps = Int((x - spaceCursorLastX) / Self.spaceCursorStep)
      if steps != 0 {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: steps)
        spaceCursorLastX += CGFloat(steps) * Self.spaceCursorStep
      }
    case .ended, .cancelled, .failed:
      guard spaceCursorActive else { return }
      spaceCursorActive = false
      (gesture.view as? KeyButton)?.isLongPressed = false
      setSpaceCursorMode(false)
      syncShiftWithContextIfNeeded()
      refreshAfterEdit()
    default:
      break
    }
  }

  /// Dims the keys while the space bar steers the cursor, as Apple's keyboard blanks them.
  private func setSpaceCursorMode(_ on: Bool) {
    keyPopup.hide()
    for stack in [lettersRowsStack, numbersRowsStack, symbolsRowsStack] {
      stack.alpha = on ? 0.35 : 1
    }
  }

  /// Leaves the 123/#+= pages for letters, with shift following the text (after "e.g. " too).
  private func returnToLetters() {
    layoutMode = .letters
    typedOnSymbolPage = false
    isCapsLocked = false
    isShiftEnabled = shouldAutoCapitalize()
    refreshVisibleKeyboardMode()
    refreshShiftState()
  }

  @objc private func handleShortcutTapped(_ sender: KeyButton) {
    guard let output = sender.output else { return }
    playKeyClick()
    countTypedWordIfFinished()
    typeText(output)
    syncShiftWithContextIfNeeded()
    refreshAfterEdit()
  }

  @objc private func handleNextKeyboardTapped() {
    playKeyClick()
    advanceToNextInputMode()
  }

  @objc private func handleInputModeListButton(_ sender: UIButton, forEvent event: UIEvent) {
    handleInputModeList(from: sender, with: event)
  }

  private func applyDoubleSpacePeriod() -> Bool {
    // G56: the translator's text is not the field's.
    if isTranslatorOpen { return false }
    // Space over a selection replaces it with a space, never ". ".
    guard (textDocumentProxy.selectedText ?? "").isEmpty else { return false }
    let context = textDocumentProxy.documentContextBeforeInput ?? ""
    let chars = Array(context)
    guard chars.count >= 2 else { return false }
    guard chars.last == " " else { return false }
    let prior = chars[chars.count - 2]
    guard prior.isLetter || prior.isNumber else { return false }

    textDocumentProxy.deleteBackward()
    typeText(". ")
    return true
  }

  private func smartQuoteSubstitution(for character: String) -> String? {
    guard character == "\"" || character == "'", usesSmartQuotes else { return nil }
    let context = textDocumentProxy.documentContextBeforeInput ?? ""
    let opening = shouldUseOpeningQuote(context: context)
    if character == "\"" {
      return opening ? "\u{201C}" : "\u{201D}"
    }
    return opening ? "\u{2018}" : "\u{2019}"
  }

  /// The field's smart-quotes setting; by default off where a curly quote breaks the text
  /// (addresses, URLs, passwords), as UIKit's default depends on the keyboard type.
  private var usesSmartQuotes: Bool {
    switch textDocumentProxy.smartQuotesType ?? .default {
    case .no: return false
    case .yes: return true
    default: break
    }
    if textDocumentProxy.isSecureTextEntry == true { return false }
    switch textDocumentProxy.keyboardType ?? .default {
    case .URL, .emailAddress: return false
    default: return true
    }
  }

  private func shouldUseOpeningQuote(context: String) -> Bool {
    guard let last = context.last else { return true }
    if last.isWhitespace { return true }
    if last == "(" || last == "[" || last == "{" { return true }
    return false
  }

  @objc private func handleReturnTapped() {
    // G56: a line break in the translator's text, whatever the field allows.
    if isTranslatorOpen {
      playKeyClick()
      appendToTranslator("\n")
      return
    }
    // Greyed: Apple's does nothing. Asked fresh, as hasText may have changed since the redraw.
    guard !isReturnKeyDisabled else { return }
    playKeyClick()
    countTypedWordIfFinished()
    typeText("\n")
    syncShiftWithContextIfNeeded()
    refreshAfterEdit()
  }

  private func setupLayout() {
    // (Nearly) transparent so the system keyboard backdrop shows through, letting the
    // keyboard blend seamlessly with the system chrome above and below (the
    // candidate area and the globe/dictation safe-area bar) instead of sitting
    // on a mismatched grey panel. Keys keep their own backgrounds.
    // iOS sends a keyboard extension no touches where its pixels are fully transparent, so
    // a clear view drops every tap in the gaps and padding that KeyboardRowsStack routes.
    // 0.1% black is invisible (no pixel value changes) and keeps those taps.
    view.backgroundColor = UIColor(white: 0, alpha: 0.001)

    // The toolbar, then the gap to row 1, then the rows.
    rootStack.axis = .vertical
    rootStack.spacing = metrics.stripGapBelow
    // The padding is a layout margin, not an offset from the edges, so the stack
    // spans the whole keyboard and touches in the padding can reach the rows.
    rootStack.isLayoutMarginsRelativeArrangement = true
    rootStack.insetsLayoutMarginsFromSafeArea = false
    rootStack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(rootStack)

    // iOS first lays a third-party keyboard out at its own default height (444pt on a
    // 17 Pro) for a frame or two before adopting ours. The content keeps its own height
    // on the bottom edge, so keys never stretch; only the top constraint yields.
    rootHeightConstraint = rootStack.heightAnchor.constraint(equalToConstant: metrics.keyboardHeight)
    rootHeightConstraint?.priority = UILayoutPriority(999)
    let rootTopConstraint = rootStack.topAnchor.constraint(equalTo: view.topAnchor)
    rootTopConstraint.priority = .defaultHigh

    NSLayoutConstraint.activate([
      rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      rootTopConstraint,
      // A view shorter than the keyboard squeezes the rows (their heights yield) rather
      // than pushing the toolbar off the top, where it can't be tapped.
      rootStack.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor),
      rootHeightConstraint,
    ].compactMap { $0 })
    applyRootPadding()

    setupTopBar()
    setupKeyboardArea()
    setupRecordingCanvas()
    setupAgentReviewCanvas()
  }

  private func setupRecordingCanvas() {
    // Transparent like the root view, so the recording overlay sits directly on
    // the system keyboard backdrop (the keys are faded out while it's shown). It
    // still intercepts touches, so the hidden keys can't be tapped.
    recordingCanvas.backgroundColor = .clear
    recordingCanvas.translatesAutoresizingMaskIntoConstraints = false
    recordingCanvas.alpha = 0
    recordingCanvas.isUserInteractionEnabled = false
    view.addSubview(recordingCanvas)

    // The dimmed keys sit between the live keys and the orb.
    dimmedKeysView.isUserInteractionEnabled = false
    dimmedKeysView.alpha = 0
    view.insertSubview(dimmedKeysView, belowSubview: recordingCanvas)

    recordingOrb.translatesAutoresizingMaskIntoConstraints = false
    recordingOrb.isAccessibilityElement = true
    recordingOrb.accessibilityTraits = .button
    recordingOrb.accessibilityLabel = "Yozilmoqda"
    recordingOrb.accessibilityHint = "Yuborish uchun ikki marta bosing."
    recordingOrb.accessibilityCustomActions = [
      // G52: a tap only sends now; cancelling is this explicit action.
      UIAccessibilityCustomAction(name: "Yozishni bekor qilish") { [weak self] _ in
        guard let self, self.recordingOrb.isActive, self.recordingOrb.stage == .recording else { return false }
        self.handleCancelRecordingTapped()
        return true
      },
    ]
    recordingOrb.onAccessibilityActivate = { [weak self] in
      self?.handleRecordingOrbTap(insideCircle: true)
      return true
    }
    recordingOrb.onKeysReturn = { [weak self] in
      self?.restoreKeysAfterRecordingOrb()
    }
    // The app's level (~40 ms RMS → dB, -50 dB = 0, -15 dB = 1; AppGroupStorageModule.chunkLevel),
    // read by the orb itself every 40 ms and passed on as is — no gate, no curve.
    recordingOrb.levelSource = {
      CGFloat(KeyboardHandoffProvider.shared.currentAudioLevel())
    }
    // Notice level, so the line also reaches the device log over USB without a Mac.
    recordingOrb.onStats = { line in
      KeyboardLog.ui.notice("\(line, privacy: .public)")
      KeyboardLog.echo(line)
    }
    recordingCanvas.addSubview(recordingOrb)
    recordingCanvas.addGestureRecognizer(
      UITapGestureRecognizer(target: self, action: #selector(handleRecordingCanvasTapped(_:)))
    )

    recordingHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
    recordingHeaderLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
    recordingHeaderLabel.textColor = Palette.keyText
    recordingHeaderLabel.textAlignment = .center
    recordingHeaderLabel.adjustsFontSizeToFitWidth = true
    recordingHeaderLabel.minimumScaleFactor = 0.8
    recordingHeaderLabel.isHidden = true
    recordingCanvas.addSubview(recordingHeaderLabel)

    NSLayoutConstraint.activate([
      recordingCanvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      recordingCanvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      recordingCanvas.topAnchor.constraint(equalTo: view.topAnchor),
      recordingCanvas.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      recordingOrb.leadingAnchor.constraint(equalTo: recordingCanvas.leadingAnchor),
      recordingOrb.trailingAnchor.constraint(equalTo: recordingCanvas.trailingAnchor),
      recordingOrb.topAnchor.constraint(equalTo: recordingCanvas.topAnchor),
      recordingOrb.bottomAnchor.constraint(equalTo: recordingCanvas.bottomAnchor),

      recordingHeaderLabel.topAnchor.constraint(equalTo: recordingCanvas.topAnchor, constant: 20),
      recordingHeaderLabel.leadingAnchor.constraint(equalTo: recordingCanvas.leadingAnchor, constant: 16),
      recordingHeaderLabel.trailingAnchor.constraint(equalTo: recordingCanvas.trailingAnchor, constant: -16),
    ])
  }

  /// The agent review overlay: an alpha-swapped card (like recordingCanvas) at
  /// the existing keyboard height. Its top row mirrors the recording canvas (✕
  /// dismiss / ✓ insert in the corners) with the "Ask for changes" follow-up
  /// capsule centred between them; a scrollable read-only text view of the
  /// generated text; a bottom bar with ↻ regenerate leading and the 1/N pager
  /// centred. The header label is hidden by default and only surfaces to flash a
  /// transient note (see flashAgentReviewNote), swapping out with the capsule.
  private func setupAgentReviewCanvas() {
    agentReviewCanvas.backgroundColor = .clear
    agentReviewCanvas.translatesAutoresizingMaskIntoConstraints = false
    agentReviewCanvas.alpha = 0
    agentReviewCanvas.isUserInteractionEnabled = false
    view.addSubview(agentReviewCanvas)

    // Hidden until flashAgentReviewNote surfaces it: it shares the top-centre slot
    // with the follow-up capsule, hiding the capsule while a note is shown.
    agentReviewHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
    agentReviewHeaderLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
    agentReviewHeaderLabel.textColor = Palette.keyText.withAlphaComponent(0.55)
    agentReviewHeaderLabel.textAlignment = .center
    agentReviewHeaderLabel.adjustsFontSizeToFitWidth = true
    agentReviewHeaderLabel.minimumScaleFactor = 0.8
    agentReviewHeaderLabel.isHidden = true
    agentReviewCanvas.addSubview(agentReviewHeaderLabel)

    agentReviewTextView.translatesAutoresizingMaskIntoConstraints = false
    agentReviewTextView.backgroundColor = .clear
    // Read-only but scrollable: scrolling is a scroll-view behaviour independent
    // of text selection, so leaving it non-selectable avoids any selection UI
    // (which keyboard extensions can't present anyway) while still scrolling.
    agentReviewTextView.isEditable = false
    agentReviewTextView.isSelectable = false
    agentReviewTextView.isScrollEnabled = true
    agentReviewTextView.alwaysBounceVertical = true
    agentReviewTextView.showsVerticalScrollIndicator = true
    agentReviewTextView.textContainerInset = UIEdgeInsets(top: 4, left: 2, bottom: 4, right: 2)
    agentReviewTextView.font = UIFont.systemFont(ofSize: 16, weight: .regular)
    agentReviewTextView.textColor = Palette.keyText
    agentReviewCanvas.addSubview(agentReviewTextView)

    configureIconButton(
      agentReviewDismissButton,
      systemImage: "xmark",
      accessibilityLabel: "Yopish",
      action: #selector(handleAgentReviewDismissTapped)
    )
    agentReviewCanvas.addSubview(agentReviewDismissButton)

    configureIconButton(
      agentReviewInsertButton,
      systemImage: "checkmark",
      accessibilityLabel: "Joylash",
      action: #selector(handleAgentReviewInsertTapped)
    )
    agentReviewInsertButton.backgroundColor = Palette.cleanupAccent
    agentReviewInsertButton.tintColor = .white
    agentReviewCanvas.addSubview(agentReviewInsertButton)

    configureIconButton(
      agentReviewRegenerateButton,
      systemImage: "arrow.clockwise",
      accessibilityLabel: "Qayta yaratish",
      action: #selector(handleAgentReviewRegenerateTapped)
    )
    configureIconButton(
      agentReviewPagerPrevButton,
      systemImage: "chevron.left",
      accessibilityLabel: "Oldingi variant",
      action: #selector(handleAgentReviewPagerPrevTapped),
      symbolPointSize: 15
    )
    configureIconButton(
      agentReviewPagerNextButton,
      systemImage: "chevron.right",
      accessibilityLabel: "Keyingi variant",
      action: #selector(handleAgentReviewPagerNextTapped),
      symbolPointSize: 15
    )
    configureAgentReviewFollowUpCapsule()

    // The pager chevrons hug the "1/N" label with no pill background, reading as
    // a single control rather than three separate keys.
    agentReviewPagerPrevButton.backgroundColor = .clear
    agentReviewPagerNextButton.backgroundColor = .clear
    agentReviewPagerLabel.translatesAutoresizingMaskIntoConstraints = false
    agentReviewPagerLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
    agentReviewPagerLabel.textColor = Palette.keyText.withAlphaComponent(0.55)
    agentReviewPagerLabel.textAlignment = .center
    agentReviewPagerLabel.setContentHuggingPriority(.required, for: .horizontal)

    agentReviewActionStack.axis = .horizontal
    agentReviewActionStack.alignment = .center
    agentReviewActionStack.spacing = 2
    agentReviewActionStack.translatesAutoresizingMaskIntoConstraints = false
    agentReviewActionStack.addArrangedSubview(agentReviewPagerPrevButton)
    agentReviewActionStack.addArrangedSubview(agentReviewPagerLabel)
    agentReviewActionStack.addArrangedSubview(agentReviewPagerNextButton)
    agentReviewCanvas.addSubview(agentReviewActionStack)

    agentReviewRegenerateButton.translatesAutoresizingMaskIntoConstraints = false
    agentReviewCanvas.addSubview(agentReviewRegenerateButton)
    agentReviewCanvas.addSubview(agentReviewFollowUpButton)

    NSLayoutConstraint.activate([
      agentReviewCanvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      agentReviewCanvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      agentReviewCanvas.topAnchor.constraint(equalTo: view.topAnchor),
      agentReviewCanvas.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      // Top row mirrors the recording canvas: ✕ leading / ✓ trailing at 16,12.
      agentReviewDismissButton.leadingAnchor.constraint(equalTo: agentReviewCanvas.leadingAnchor, constant: 16),
      agentReviewDismissButton.topAnchor.constraint(equalTo: agentReviewCanvas.topAnchor, constant: 12),
      agentReviewDismissButton.widthAnchor.constraint(equalToConstant: Metrics.recordingActionButtonSize),
      agentReviewDismissButton.heightAnchor.constraint(equalToConstant: Metrics.recordingActionButtonSize),

      agentReviewInsertButton.trailingAnchor.constraint(equalTo: agentReviewCanvas.trailingAnchor, constant: -16),
      agentReviewInsertButton.topAnchor.constraint(equalTo: agentReviewCanvas.topAnchor, constant: 12),
      agentReviewInsertButton.widthAnchor.constraint(equalToConstant: Metrics.recordingActionButtonSize),
      agentReviewInsertButton.heightAnchor.constraint(equalToConstant: Metrics.recordingActionButtonSize),

      // Follow-up capsule fills the top-centre slot between ✕ and ✓. Leading/
      // trailing ≥ constraints keep it clear of both edge buttons on narrow widths.
      agentReviewFollowUpButton.heightAnchor.constraint(equalToConstant: Metrics.recordingActionButtonSize),
      agentReviewFollowUpButton.centerXAnchor.constraint(equalTo: agentReviewCanvas.centerXAnchor),
      agentReviewFollowUpButton.centerYAnchor.constraint(equalTo: agentReviewDismissButton.centerYAnchor),
      agentReviewFollowUpButton.leadingAnchor.constraint(
        greaterThanOrEqualTo: agentReviewDismissButton.trailingAnchor, constant: 8),
      agentReviewFollowUpButton.trailingAnchor.constraint(
        lessThanOrEqualTo: agentReviewInsertButton.leadingAnchor, constant: -8),

      // The header shares the capsule's slot: shown only while a note flashes.
      agentReviewHeaderLabel.centerYAnchor.constraint(equalTo: agentReviewDismissButton.centerYAnchor),
      agentReviewHeaderLabel.leadingAnchor.constraint(equalTo: agentReviewDismissButton.trailingAnchor, constant: 8),
      agentReviewHeaderLabel.trailingAnchor.constraint(equalTo: agentReviewInsertButton.leadingAnchor, constant: -8),

      // Bottom bar: ↻ regenerate leading, pager centred, bottom-right empty.
      agentReviewRegenerateButton.leadingAnchor.constraint(equalTo: agentReviewCanvas.leadingAnchor, constant: 16),
      agentReviewRegenerateButton.bottomAnchor.constraint(equalTo: agentReviewCanvas.bottomAnchor, constant: -12),
      agentReviewRegenerateButton.widthAnchor.constraint(equalToConstant: Metrics.recordingActionButtonSize),
      agentReviewRegenerateButton.heightAnchor.constraint(equalToConstant: Metrics.recordingActionButtonSize),

      agentReviewPagerPrevButton.widthAnchor.constraint(equalToConstant: 24),
      agentReviewPagerPrevButton.heightAnchor.constraint(equalToConstant: Metrics.recordingActionButtonSize),
      agentReviewPagerNextButton.widthAnchor.constraint(equalToConstant: 24),
      agentReviewPagerNextButton.heightAnchor.constraint(equalToConstant: Metrics.recordingActionButtonSize),

      // Pager centred on the regenerate button's baseline.
      agentReviewActionStack.centerXAnchor.constraint(equalTo: agentReviewCanvas.centerXAnchor),
      agentReviewActionStack.centerYAnchor.constraint(equalTo: agentReviewRegenerateButton.centerYAnchor),
      agentReviewActionStack.leadingAnchor.constraint(
        greaterThanOrEqualTo: agentReviewRegenerateButton.trailingAnchor, constant: 8),
      agentReviewActionStack.trailingAnchor.constraint(
        lessThanOrEqualTo: agentReviewCanvas.trailingAnchor, constant: -16),

      // Text view spans between the ✕ top row and the ↻ bottom bar.
      agentReviewTextView.topAnchor.constraint(equalTo: agentReviewDismissButton.bottomAnchor, constant: 10),
      agentReviewTextView.leadingAnchor.constraint(equalTo: agentReviewCanvas.leadingAnchor, constant: 18),
      agentReviewTextView.trailingAnchor.constraint(equalTo: agentReviewCanvas.trailingAnchor, constant: -18),
      agentReviewTextView.bottomAnchor.constraint(equalTo: agentReviewRegenerateButton.topAnchor, constant: -10),
    ])

    // G57 (analysis finding 3): the card's two wake-links (a SwiftUI hosting controller each,
    // and four private-API host lookups for their URLs) are made the first time the card shows
    // (refreshAgentReviewControls), not on every keyboard launch — Gapla rarely shows the card.
  }

  private var didSetupAgentReviewWakeLinks = false

  /// The follow-up control is a labelled capsule ("🎙 Ask for changes") rather
  /// than a bare icon button — built with UIButton.Configuration like the record
  /// button. It keeps the 36pt height/key styling; the mic glyph is tinted the
  /// Gapla accent while the label stays key-text.
  private func configureAgentReviewFollowUpCapsule() {
    agentReviewFollowUpButton.translatesAutoresizingMaskIntoConstraints = false
    agentReviewFollowUpButton.backgroundColor = Palette.keyBackground
    agentReviewFollowUpButton.layer.cornerRadius = Metrics.recordingActionButtonSize / 2
    agentReviewFollowUpButton.layer.cornerCurve = .continuous
    agentReviewFollowUpButton.accessibilityLabel = "O'zgartirish so'rash"

    var config = UIButton.Configuration.plain()
    config.title = "O'zgartirish so'rash"
    // The title tints key-text (baseForegroundColor); the mic glyph takes the Gapla accent through its own
    // colour transformer, which resolves light/dark with the button's traits (G54).
    config.baseForegroundColor = Palette.keyText
    config.image = UIImage(systemName: "mic.fill")
    config.imageColorTransformer = UIConfigurationColorTransformer { _ in Palette.accentTint }
    config.imagePadding = 6
    config.imagePlacement = .leading
    config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 14)
    config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var outgoing = incoming
      outgoing.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
      return outgoing
    }
    agentReviewFollowUpButton.configuration = config
    agentReviewFollowUpButton.addTarget(
      self, action: #selector(handleAgentReviewFollowUpTapped), for: .touchUpInside
    )
  }

  /// Overlays each app-requiring card control (regenerate, follow-up) with a
  /// SwiftUI Link to OpenWhispr, mirroring the entry button's handoff link. The
  /// links stay disabled while the app is alive; refreshAgentReviewControls
  /// enables them when the heartbeat goes stale so a tap wakes the app instead.
  ///
  /// Each button also gets a zero-duration press recogniser (like the record
  /// button's) that, when its wake-link is live, writes the request/action into
  /// the App Group *before* the Link opens the app — so the woken app performs
  /// the right work instead of an unrelated recording:
  ///   • follow-up → a recording-handoff URL; the gesture writes a follow_up
  ///     request + hides the card, so the recording becomes an agent follow-up.
  ///   • regenerate → an `intent=agent-action` URL the app short-circuits into
  ///     its cold-start `runAgentAction` replay; the gesture writes the action
  ///     + at-ms twin first (NO recording is started for a regenerate wake).
  private func setupAgentReviewWakeLinks() {
    guard let regenerateURL = makeReviewWakeURL(intent: "agent-action"),
          let followUpURL = makeReviewWakeURL(intent: nil) else { return }

    agentReviewRegenerateWakeLink = installWakeLink(url: regenerateURL, over: agentReviewRegenerateButton)
    agentReviewFollowUpWakeLink = installWakeLink(url: followUpURL, over: agentReviewFollowUpButton)

    let regeneratePress = UILongPressGestureRecognizer(
      target: self, action: #selector(handleRegenerateWakePress(_:))
    )
    regeneratePress.minimumPressDuration = 0
    regeneratePress.cancelsTouchesInView = false
    regeneratePress.delaysTouchesBegan = false
    regeneratePress.delegate = self
    agentReviewRegenerateButton.addGestureRecognizer(regeneratePress)

    let followUpPress = UILongPressGestureRecognizer(
      target: self, action: #selector(handleFollowUpWakePress(_:))
    )
    followUpPress.minimumPressDuration = 0
    followUpPress.cancelsTouchesInView = false
    followUpPress.delaysTouchesBegan = false
    followUpPress.delegate = self
    agentReviewFollowUpButton.addGestureRecognizer(followUpPress)
  }

  /// Builds a keyboard-dictation wake URL carrying the host return info. `intent`
  /// (e.g. "agent-action") lets the app's URL handler route the wake to a
  /// non-recording path; nil is the normal recording handoff.
  private func makeReviewWakeURL(intent: String?) -> URL? {
    let provider = KeyboardHandoffProvider.shared
    var components = URLComponents(string: "\(Self.appUrlScheme)://keyboard-dictation")!
    components.queryItems = [URLQueryItem(name: "source", value: "keyboard")]
    if let intent {
      components.queryItems?.append(URLQueryItem(name: "intent", value: intent))
    }
    if let scheme = provider.hostUrlScheme(from: self) {
      components.queryItems?.append(URLQueryItem(name: "returnScheme", value: scheme))
    }
    if let bundle = provider.detectHostBundleID(from: self) {
      components.queryItems?.append(URLQueryItem(name: "hostBundle", value: bundle))
    }
    return components.url
  }

  /// Regenerate wake: when the wake-link is live (app dead), write the action +
  /// at-ms twin so the woken app replays it via runAgentAction. The Link opens
  /// the `intent=agent-action` URL simultaneously; no recording is started.
  @objc private func handleRegenerateWakePress(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .ended,
          agentReviewRegenerateWakeLink?.view.isUserInteractionEnabled == true,
          !agentReviewSessionId.isEmpty else { return }
    KeyboardHandoffProvider.shared.writeAgentRegenerateAction(sessionId: agentReviewSessionId)
    logRecordMarker("handleRegenerateWakePress", extra: "session=\(agentReviewSessionId)")
  }

  /// Follow-up wake: when the wake-link is live, write a follow_up request and
  /// hide the card before the Link opens the recording-handoff URL — so the
  /// recording the woken app starts is a legitimate agent follow-up job.
  @objc private func handleFollowUpWakePress(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .ended,
          agentReviewFollowUpWakeLink?.view.isUserInteractionEnabled == true,
          !agentReviewSessionId.isEmpty else { return }
    KeyboardHandoffProvider.shared.writeAgentFollowUpRequest(sessionId: agentReviewSessionId)
    isAgentRecordingActive = true
    logRecordMarker("handleFollowUpWakePress", extra: "session=\(agentReviewSessionId)")
    hideAgentReviewCard(clearState: false)
  }

  private func installWakeLink(
    url: URL,
    over button: UIButton
  ) -> UIHostingController<DictationLinkView> {
    let hosting = UIHostingController(rootView: DictationLinkView(url: url))
    hosting.view.backgroundColor = .clear
    hosting.view.isOpaque = false
    hosting.view.isUserInteractionEnabled = false
    hosting.view.translatesAutoresizingMaskIntoConstraints = false
    addChild(hosting)
    button.addSubview(hosting.view)
    hosting.didMove(toParent: self)
    NSLayoutConstraint.activate([
      hosting.view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
      hosting.view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
      hosting.view.topAnchor.constraint(equalTo: button.topAnchor),
      hosting.view.bottomAnchor.constraint(equalTo: button.bottomAnchor),
    ])
    return hosting
  }

  private func configureIconButton(
    _ button: UIButton,
    systemImage: String,
    accessibilityLabel: String,
    action: Selector,
    size: CGFloat = Metrics.recordingActionButtonSize,
    symbolPointSize: CGFloat = 15
  ) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.backgroundColor = Palette.keyBackground
    button.layer.cornerRadius = size / 2
    button.layer.cornerCurve = .continuous
    button.tintColor = Palette.keyText
    button.setImage(UIImage(systemName: systemImage), for: .normal)
    button.setPreferredSymbolConfiguration(
      UIImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold),
      forImageIn: .normal
    )
    button.accessibilityLabel = accessibilityLabel
    button.addTarget(self, action: action, for: .touchUpInside)
  }

  private func setupFullAccessPanelIfNeeded() {
    guard !didSetupFullAccessPanel else { return }
    didSetupFullAccessPanel = true

    fullAccessPanel.backgroundColor = .clear
    fullAccessPanel.translatesAutoresizingMaskIntoConstraints = false
    fullAccessPanel.alpha = 0
    fullAccessPanel.isUserInteractionEnabled = false
    view.addSubview(fullAccessPanel)

    configureIconButton(
      fullAccessPanelCloseButton,
      systemImage: "xmark",
      accessibilityLabel: "Yopish",
      action: #selector(handleFullAccessPanelCloseTapped)
    )
    fullAccessPanel.addSubview(fullAccessPanelCloseButton)

    fullAccessPanelTitleLabel.translatesAutoresizingMaskIntoConstraints = false
    fullAccessPanelTitleLabel.text = "Diktovka uchun to'liq kirish kerak"
    fullAccessPanelTitleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
    fullAccessPanelTitleLabel.textColor = Palette.keyText
    fullAccessPanelTitleLabel.textAlignment = .center
    fullAccessPanelTitleLabel.adjustsFontSizeToFitWidth = true
    fullAccessPanelTitleLabel.minimumScaleFactor = 0.8
    fullAccessPanel.addSubview(fullAccessPanelTitleLabel)

    fullAccessPanelBodyLabel.translatesAutoresizingMaskIntoConstraints = false
    // Names the destination rather than promising the app will surface it: the
    // Home banner only fires when the app update boundary reveals the loss, and
    // a mid-version revoke (manual toggle, keyboard re-added, iOS upgrade) is
    // invisible to the probe — so this path is the only reliable way back.
    fullAccessPanelBodyLabel.text =
      "Gapla'da Hisob ▸ Afzalliklar ▸ Klaviatura bo'limini oching."
    fullAccessPanelBodyLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
    fullAccessPanelBodyLabel.textColor = Palette.keyText.withAlphaComponent(0.7)
    fullAccessPanelBodyLabel.textAlignment = .center
    fullAccessPanelBodyLabel.numberOfLines = 0
    fullAccessPanel.addSubview(fullAccessPanelBodyLabel)

    // Apple requires the keyboard-switching affordance even here; the factory
    // wires both input-mode targets and hides itself when iOS says no switcher
    // is needed.
    let globe = makeNextKeyboardButton()
    globe.translatesAutoresizingMaskIntoConstraints = false
    fullAccessPanelGlobeButton = globe
    fullAccessPanel.addSubview(globe)

    NSLayoutConstraint.activate([
      fullAccessPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      fullAccessPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      fullAccessPanel.topAnchor.constraint(equalTo: view.topAnchor),
      fullAccessPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      fullAccessPanelCloseButton.leadingAnchor.constraint(
        equalTo: fullAccessPanel.leadingAnchor, constant: 16
      ),
      fullAccessPanelCloseButton.topAnchor.constraint(
        equalTo: fullAccessPanel.topAnchor, constant: 12
      ),
      fullAccessPanelCloseButton.widthAnchor.constraint(
        equalToConstant: Metrics.recordingActionButtonSize
      ),
      fullAccessPanelCloseButton.heightAnchor.constraint(
        equalToConstant: Metrics.recordingActionButtonSize
      ),

      // Centered slightly high so the 187pt landscape height still clears
      // the ✕ above and the globe below.
      fullAccessPanelTitleLabel.centerXAnchor.constraint(equalTo: fullAccessPanel.centerXAnchor),
      fullAccessPanelTitleLabel.centerYAnchor.constraint(
        equalTo: fullAccessPanel.centerYAnchor, constant: -16
      ),
      fullAccessPanelTitleLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: fullAccessPanel.leadingAnchor, constant: 24
      ),
      fullAccessPanelTitleLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: fullAccessPanel.trailingAnchor, constant: -24
      ),

      fullAccessPanelBodyLabel.topAnchor.constraint(
        equalTo: fullAccessPanelTitleLabel.bottomAnchor, constant: 6
      ),
      fullAccessPanelBodyLabel.centerXAnchor.constraint(equalTo: fullAccessPanel.centerXAnchor),
      fullAccessPanelBodyLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: fullAccessPanel.leadingAnchor, constant: 32
      ),
      fullAccessPanelBodyLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: fullAccessPanel.trailingAnchor, constant: -32
      ),

      globe.leadingAnchor.constraint(equalTo: fullAccessPanel.leadingAnchor, constant: 6),
      globe.bottomAnchor.constraint(equalTo: fullAccessPanel.bottomAnchor, constant: -6),
      globe.widthAnchor.constraint(equalToConstant: 42),
      globe.heightAnchor.constraint(equalToConstant: 42),
    ])
  }

  private func showFullAccessPanel(animated: Bool) {
    setupFullAccessPanelIfNeeded()
    guard !fullAccessPanel.isUserInteractionEnabled else { return }
    fullAccessPanel.isUserInteractionEnabled = true
    view.bringSubviewToFront(fullAccessPanel)
    let apply = {
      self.fullAccessPanel.alpha = 1
      self.rootStack.alpha = 0
    }
    if animated {
      UIView.animate(withDuration: 0.18, delay: 0, options: .curveEaseOut, animations: apply)
    } else {
      apply()
    }
    UIAccessibility.post(notification: .screenChanged, argument: fullAccessPanelTitleLabel)
  }

  private func hideFullAccessPanel(animated: Bool) {
    guard didSetupFullAccessPanel, fullAccessPanel.isUserInteractionEnabled else { return }
    fullAccessPanel.isUserInteractionEnabled = false
    let apply = {
      self.fullAccessPanel.alpha = 0
      self.rootStack.alpha = 1
    }
    if animated {
      UIView.animate(withDuration: 0.18, delay: 0, options: .curveEaseOut, animations: apply)
    } else {
      apply()
    }
  }

  @objc private func handleFullAccessPanelCloseTapped() {
    didDismissFullAccessPanel = true
    hideFullAccessPanel(animated: true)
  }

  // The one thing the keyboard CAN do without Full Access: local UI. The pill
  // re-opens the panel, so it is honestly tappable again.
  @objc private func handleFullAccessPillTapped() {
    didDismissFullAccessPanel = false
    showFullAccessPanel(animated: true)
  }

  /// Gapla (G47): the orb appears in the keyboard's middle and the keys drop to 16 %, blurred
  /// 1.5 pt (0.4 s, as on the sample page). The orb then stays through processing until the
  /// text lands (endRecordingOrb).
  private func showRecordingCanvas() {
    recordingCanvas.isUserInteractionEnabled = true

    if isAgentRecordingActive {
      recordingHeaderLabel.text = agentRecordingHeaderText
        ?? "\(KeyboardHandoffProvider.shared.agentName()) nima yozsin?"
      recordingHeaderLabel.isHidden = false
    } else {
      recordingHeaderLabel.isHidden = true
    }

    // Gapla: the app's «Animatsiya sinovi» switch — the sample page's test voice drives the orb.
    recordingOrb.usesTestVoice = KeyboardHandoffProvider.shared.isOrbTestVoiceEnabled()
    recordingOrb.begin()
    recordingCanvas.alpha = 1
    // A picture is taken only of fully visible keys; a second start while the orb is up (or
    // still leaving) keeps the one taken then.
    if dimmedKeysView.image == nil || rootStack.alpha > 0.99 {
      dimmedKeysView.frame = rootStack.frame
      dimmedKeysView.image = RecordingOrbView.blurredSnapshot(of: rootStack)
    }
    UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: {
      self.dimmedKeysView.alpha = 0.16
      self.rootStack.alpha = 0
    })
  }

  /// Gapla (G47): ends the orb. `success` plays the done stage (0.9 s: the sphere gathers in,
  /// the tick draws on its dark badge) before the 0.4 s shrink; otherwise it just shrinks. The
  /// keys come back half-way through the shrink (restoreKeysAfterRecordingOrb). A second call
  /// while it is already ending does nothing.
  private func endRecordingOrb(success: Bool) {
    cancelProcessingKeysReturn()
    guard recordingOrb.isActive else { return }
    recordingCanvas.isUserInteractionEnabled = false
    let finished: () -> Void = { [weak self] in
      guard let self, !self.recordingOrb.isShowing else { return }
      self.recordingCanvas.alpha = 0
      self.recordingHeaderLabel.isHidden = true
    }
    if success {
      recordingOrb.finish(completion: finished)
    } else {
      recordingOrb.dismiss(completion: finished)
    }
  }

  private func restoreKeysAfterRecordingOrb() {
    // Another surface (the agent review card) may own the keys' alpha by now.
    guard !isAgentReviewShown else {
      dimmedKeysView.alpha = 0
      dimmedKeysView.image = nil
      return
    }
    UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: {
      self.dimmedKeysView.alpha = 0
      self.rootStack.alpha = 1
    }, completion: { [weak self] _ in
      guard let self, !self.recordingOrb.isShowing else { return }
      self.dimmedKeysView.image = nil
    })
  }

  /// The keyboard is closing: no orb animation, the keys back at once.
  private func resetRecordingOrbImmediately() {
    cancelProcessingKeysReturn()
    guard recordingOrb.isShowing || dimmedKeysView.image != nil else { return }
    recordingOrb.reset()
    recordingCanvas.isUserInteractionEnabled = false
    recordingCanvas.alpha = 0
    recordingHeaderLabel.isHidden = true
    dimmedKeysView.layer.removeAllAnimations()
    dimmedKeysView.alpha = 0
    dimmedKeysView.image = nil
    if !isAgentReviewShown {
      rootStack.layer.removeAllAnimations()
      rootStack.alpha = 1
    }
  }

  @objc private func handleRecordingCanvasTapped(_ gesture: UITapGestureRecognizer) {
    handleRecordingOrbTap(insideCircle: recordingOrb.circleContains(gesture.location(in: recordingOrb)))
  }

  /// Gapla (G52, owner 2026-11-12 on the iPad: [so'zlari: bilim/gapla-goyalar-royxati.md]): a tap on the circle
  /// or anywhere else on the keyboard stops the recording and sends it for text — a tap never
  /// cancels. Until then a tap beside the circle threw the recording away without a word
  /// (bilim/gapla-yozish-animatsiyasi-tanlov.md, «Joylashuv va boshqaruv»; Android 1.4.4 alike).
  /// VoiceOver keeps an explicit cancel action while recording.
  /// G57: while the text is being made, a tap (from a second after the stop on, so the stop's own double tap does not
  /// count) brings the keys back at once, as the 12 s timer would: the orb leaves, the pill keeps «Ishlanmoqda» with
  /// its ✕ to cancel, and the text is still inserted when it lands. A tap never cancels outright, so a dictation is not
  /// lost to a stray touch.
  private func handleRecordingOrbTap(insideCircle _: Bool) {
    guard recordingOrb.isActive else { return }
    switch recordingOrb.stage {
    case .recording:
      handleStopRecordingTapped()
    case .processing:
      guard CACurrentMediaTime() - processingOrbStartedAt >= 1.0 else { return }
      returnKeysDuringProcessing(reason: "tap")
    default:
      break
    }
  }

  // MARK: Gapla processing that takes long (G57)

  /// After this long in processing the keys, the globe and the pill's ✕ come back while the wait goes on.
  private static let processingKeysReturnDelay: TimeInterval = 12

  /// Recording → processing, and from then on at most `processingKeysReturnDelay` of the orb alone (analysis
  /// finding 1: a slow or dead app left nothing but a spinning orb for up to two minutes, five in Lokal mode).
  private func moveOrbToProcessing() {
    let wasRecording = recordingOrb.isActive && recordingOrb.stage == .recording
    recordingOrb.process()
    guard wasRecording else { return }
    processingOrbStartedAt = CACurrentMediaTime()
    processingKeysReturnTimer?.invalidate()
    let timer = Timer(timeInterval: Self.processingKeysReturnDelay, repeats: false) { [weak self] _ in
      self?.returnKeysDuringProcessing(reason: "timer")
    }
    RunLoop.main.add(timer, forMode: .common)
    processingKeysReturnTimer = timer
  }

  private func cancelProcessingKeysReturn() {
    processingKeysReturnTimer?.invalidate()
    processingKeysReturnTimer = nil
  }

  /// The orb leaves with its own shrink and the keys come back; the pill shows the processing step with its ✕. The
  /// wait for the text keeps running (waitForTranscript, the shared status and the poll), so a late text is still
  /// inserted, and the ✕ cancels it.
  private func returnKeysDuringProcessing(reason: String) {
    cancelProcessingKeysReturn()
    guard recordingOrb.isActive, recordingOrb.stage == .processing else { return }
    logRecordMarker("processing.keysReturn", extra: "reason=\(reason)")
    endRecordingOrb(success: false)
    let cleaning = KeyboardHandoffProvider.shared.transcriptionStatus() == "cleaning"
    showLongRunningRecordState(title: cleaning ? "Tozalanmoqda" : "Ishlanmoqda")
  }

  /// The toolbar: the tone menu on the left, the dictation pill centred, the agent wand on
  /// the right.
  private func setupTopBar() {
    topBar.translatesAutoresizingMaskIntoConstraints = false
    topBar.addLayoutGuide(stripGuide)

    // The pill background sits behind the button; the button itself is
    // transparent so its icon and label render on top. Corner radius is half the
    // height, giving a full pill in every state.
    recordButtonBackground.translatesAutoresizingMaskIntoConstraints = false
    recordButtonBackground.layer.cornerRadius = Metrics.dictationButtonSize / 2
    topBar.addSubview(recordButtonBackground)

    recordButton.translatesAutoresizingMaskIntoConstraints = false
    topBar.addSubview(recordButton)

    // Press feedback. The hand-off tap is handled by the SwiftUI link overlay,
    // so observe touches without consuming them (cancelsTouchesInView = false)
    // and recognise alongside the link's own gesture.
    let pressGesture = UILongPressGestureRecognizer(
      target: self,
      action: #selector(handleRecordButtonPress(_:))
    )
    pressGesture.minimumPressDuration = 0
    pressGesture.cancelsTouchesInView = false
    pressGesture.delaysTouchesBegan = false
    pressGesture.delegate = self
    recordButton.addGestureRecognizer(pressGesture)

    // Animated dots overlaid where the leading icon sits, shown only in the
    // "Processing"/"Starting"/"Stopping" states.
    processingDots.translatesAutoresizingMaskIntoConstraints = false
    processingDots.isHidden = true
    recordButton.addSubview(processingDots)
    NSLayoutConstraint.activate([
      processingDots.leadingAnchor.constraint(equalTo: recordButton.leadingAnchor, constant: Metrics.pillLeadingInset),
      processingDots.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
      processingDots.widthAnchor.constraint(equalToConstant: ProcessingDotsView.preferredSize.width),
      processingDots.heightAnchor.constraint(equalToConstant: ProcessingDotsView.preferredSize.height),
    ])

    // X to cancel an in-flight transcription, pinned just past the pill's
    // trailing edge; shown only in the "Transcribing"/"Cleaning up" states
    // (see showLongRunningRecordState).
    configureIconButton(
      processingCancelButton,
      systemImage: "xmark",
      accessibilityLabel: "Matnga aylantirishni bekor qilish",
      action: #selector(handleProcessingCancelTapped),
      size: Metrics.processingCancelSize,
      symbolPointSize: 13
    )
    processingCancelButton.isHidden = true
    topBar.addSubview(processingCancelButton)

    // gauge.with.dots.needle.bottom.50percent is iOS 16+; fall back to the classic
    // gauge on the extension's 15.1 deployment target.
    configureToolbarButton(
      toneButton,
      image: UIImage(systemName: "gauge.with.dots.needle.bottom.50percent") ?? UIImage(systemName: "gauge"),
      accessibilityLabel: "Rejim"
    )
    toneButton.showsMenuAsPrimaryAction = true
    refreshToneButton()

    // Gapla (G8): the shared clipboard, beside the tone menu — the left side holds the tools,
    // the right side dictation (the Gapla mark).
    configureToolbarButton(
      clipboardButton,
      image: UIImage(systemName: "doc.on.clipboard"),
      accessibilityLabel: "Bufer"
    )
    clipboardButton.addTarget(self, action: #selector(handleClipboardButtonTapped), for: .touchUpInside)

    // Gapla (G40, owner 2026-11-11): [so'zlari: bilim/gapla-goyalar-royxati.md]. The trailing button starts plain dictation like the pill;
    // the OpenWhispr voice assistant it opened is gone. It shows the Gapla mark, not a
    // microphone, so it isn't mistaken for Apple's dictation mic below the keys (owner chose
    // «Gapla belgisi qo'y»). A press gesture (not a tap target) so it can stamp the hand-off
    // before the Link overlay fires, as the record button does.
    configureToolbarButton(
      agentButton,
      image: CachedImages.brandLogoMark,
      accessibilityLabel: "Diktovka"
    )
    let agentPress = UILongPressGestureRecognizer(
      target: self,
      action: #selector(handleAgentButtonPress(_:))
    )
    agentPress.minimumPressDuration = 0
    agentPress.cancelsTouchesInView = false
    agentPress.delaysTouchesBegan = false
    agentPress.delegate = self
    agentButton.addGestureRecognizer(agentPress)

    // Gapla (G56, owner 2026-11-12/13): the translator, beside the dictation button. Its mark is 文A, not a globe: the
    // globe below the keys switches keyboards. A tap opens or closes the translator above the keys.
    configureToolbarButton(
      translateButton,
      image: UIImage(systemName: "translate") ?? UIImage(systemName: "character.bubble"),
      accessibilityLabel: "Tarjimon"
    )
    translateButton.addTarget(self, action: #selector(handleTranslateButtonTapped), for: .touchUpInside)
    processingCancelButton.onHiddenChanged = { [weak self] _ in self?.refreshTranslateButton() }

    // Gapla (G41, G55, owner 2026-11-11: the keyboard does not grow): while he types, the suggestions take the left
    // tools' place up to the dictation button, which stays (refreshTavsiya).
    tavsiyaBar.translatesAutoresizingMaskIntoConstraints = false
    tavsiyaBar.isHidden = true
    tavsiyaBar.onPick = { [weak self] word in self?.handleTavsiyaPicked(word) }
    tavsiyaBar.onForget = { [weak self] word in self?.handleTavsiyaForget(word) }
    topBar.addSubview(tavsiyaBar)

    let topBarHeight = topBar.heightAnchor.constraint(equalToConstant: metrics.stripTop + metrics.stripHeight)
    topBarHeightConstraint = topBarHeight
    stripConstraints = [
      stripGuide.topAnchor.constraint(equalTo: topBar.topAnchor, constant: metrics.stripTop),
      stripGuide.heightAnchor.constraint(equalToConstant: metrics.stripHeight),
      stripGuide.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: stripEdgeOffset),
      stripGuide.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -stripEdgeOffset),
    ]
    // The pill is centred in the strip and sizes itself to its content, capped so a
    // long label can't overflow the strip.
    NSLayoutConstraint.activate(stripConstraints + [
      topBarHeight,

      toneButton.leadingAnchor.constraint(equalTo: stripGuide.leadingAnchor, constant: Metrics.toolbarButtonInset),
      toneButton.centerYAnchor.constraint(equalTo: stripGuide.centerYAnchor),
      toneButton.widthAnchor.constraint(equalToConstant: Metrics.toolbarButtonSize),
      toneButton.heightAnchor.constraint(equalToConstant: Metrics.toolbarButtonSize),

      clipboardButton.leadingAnchor.constraint(equalTo: toneButton.trailingAnchor, constant: Metrics.toolbarButtonInset),
      clipboardButton.centerYAnchor.constraint(equalTo: stripGuide.centerYAnchor),
      clipboardButton.widthAnchor.constraint(equalToConstant: Metrics.toolbarButtonSize),
      clipboardButton.heightAnchor.constraint(equalToConstant: Metrics.toolbarButtonSize),

      agentButton.trailingAnchor.constraint(equalTo: stripGuide.trailingAnchor, constant: -Metrics.toolbarButtonInset),
      agentButton.centerYAnchor.constraint(equalTo: stripGuide.centerYAnchor),
      agentButton.widthAnchor.constraint(equalToConstant: Metrics.toolbarButtonSize),
      agentButton.heightAnchor.constraint(equalToConstant: Metrics.toolbarButtonSize),

      translateButton.trailingAnchor.constraint(equalTo: agentButton.leadingAnchor, constant: -Metrics.toolbarButtonInset),
      translateButton.centerYAnchor.constraint(equalTo: stripGuide.centerYAnchor),
      translateButton.widthAnchor.constraint(equalToConstant: Metrics.toolbarButtonSize),
      translateButton.heightAnchor.constraint(equalToConstant: Metrics.toolbarButtonSize),

      tavsiyaBar.leadingAnchor.constraint(equalTo: stripGuide.leadingAnchor),
      tavsiyaBar.trailingAnchor.constraint(equalTo: translateButton.leadingAnchor, constant: -Metrics.toolbarButtonInset),
      tavsiyaBar.topAnchor.constraint(equalTo: stripGuide.topAnchor),
      tavsiyaBar.bottomAnchor.constraint(equalTo: stripGuide.bottomAnchor),

      recordButton.centerXAnchor.constraint(equalTo: stripGuide.centerXAnchor),
      recordButton.centerYAnchor.constraint(equalTo: stripGuide.centerYAnchor),
      recordButton.heightAnchor.constraint(equalToConstant: Metrics.dictationButtonSize),
      recordButton.widthAnchor.constraint(lessThanOrEqualTo: stripGuide.widthAnchor, constant: -16),

      // Background tracks the button's frame exactly.
      recordButtonBackground.leadingAnchor.constraint(equalTo: recordButton.leadingAnchor),
      recordButtonBackground.trailingAnchor.constraint(equalTo: recordButton.trailingAnchor),
      recordButtonBackground.topAnchor.constraint(equalTo: recordButton.topAnchor),
      recordButtonBackground.bottomAnchor.constraint(equalTo: recordButton.bottomAnchor),

      processingCancelButton.leadingAnchor.constraint(equalTo: recordButton.trailingAnchor, constant: 8),
      processingCancelButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
      processingCancelButton.widthAnchor.constraint(equalToConstant: Metrics.processingCancelSize),
      processingCancelButton.heightAnchor.constraint(equalToConstant: Metrics.processingCancelSize),
    ])

    setupAgentLink()
    refreshAgentButton()
    setupDictationLink()

    rootStack.addArrangedSubview(topBar)
  }

  /// The round tone and agent buttons: a grey disc with a glass rim.
  private func configureToolbarButton(_ button: KeyButton, image: UIImage?, accessibilityLabel: String) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.tintColor = .label
    button.normalBackground = UIColor.secondarySystemBackground
    button.pressedBackground = UIColor { traits in
      let delta: CGFloat = traits.userInterfaceStyle == .dark ? 0.12 : -0.10
      return UIColor.secondarySystemBackground.resolvedColor(with: traits).brightened(by: delta)
    }
    button.layer.cornerRadius = Metrics.toolbarButtonSize / 2
    button.showsGlassRim = true
    button.setImage(image, for: .normal)
    button.setPreferredSymbolConfiguration(
      UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold),
      forImageIn: .normal
    )
    button.accessibilityLabel = accessibilityLabel
    topBar.addSubview(button)
  }

  /// The strip's inset from the bar, which starts at the keys' side margin.
  private var stripEdgeOffset: CGFloat { metrics.stripSideInset - metrics.sideMargin }

  private func updateStripConstraints() {
    let constants = [metrics.stripTop, metrics.stripHeight, stripEdgeOffset, -stripEdgeOffset]
    for (constraint, constant) in zip(stripConstraints, constants) {
      constraint.constant = constant
    }
  }

  private func refreshAfterEdit() {
    noteFieldReport()
    refreshReturnKey()
    refreshTavsiya()
  }

  private func typeText(_ text: String) {
    // G56: while the translator is open the keys type into its text, not the field.
    if isTranslatorOpen {
      appendToTranslator(text)
      return
    }
    textDocumentProxy.insertText(text)
    typedDocument = currentDocumentIdentifier
  }

  private func noteFieldReport() {
    let proxy = textDocumentProxy
    if proxy.hasText || proxy.documentContextBeforeInput?.isEmpty == false
      || proxy.documentContextAfterInput?.isEmpty == false
    {
      reportingDocument = currentDocumentIdentifier
    }
  }

  /// The field holds text it doesn't report: the keyboard typed into it and the host has
  /// reported no text in it since. Some hosts never report it, so shift and the return key
  /// can't go by it there. No field id yet: it can't tell, so no.
  private var fieldHidesItsText: Bool {
    guard let document = currentDocumentIdentifier else { return false }
    return typedDocument == document && reportingDocument != document
  }

  /// The field's id, or nil. UITextDocumentProxy declares documentIdentifier non-optional, but iOS hands back nil while
  /// a field is being set up (on opening, in textDidChange), and bridging that nil to UUID traps. That was the
  /// keyboard's one crash on the owner's iPhone: 34 reports, 2026-11-10 to 2026-11-14, all
  /// UUID._unconditionallyBridgeFromObjectiveC in fieldHidesItsText, under a second after launch — the keyboard
  /// "sometimes doesn't open" (G57). Read through Objective-C instead, where nil stays nil.
  private var currentDocumentIdentifier: UUID? {
    guard let proxy = textDocumentProxy as? NSObject,
          proxy.responds(to: NSSelectorFromString("documentIdentifier"))
    else { return nil }
    return proxy.value(forKey: "documentIdentifier") as? UUID
  }

  private static let toneMenuItems: [(value: String, title: String)] = [
    ("default", "Standart"),
    ("formal", "Rasmiy"),
    ("casual", "Oddiy"),
    ("very_casual", "Juda oddiy"),
    ("excited", "Hayajonli"),
  ]

  // Gapla: the toolbar's left menu picks the cleanup mode instead of OpenWhispr's tone, which
  // needs OpenWhispr Cloud and stays off on the Gapla bridge. Two taps: open, pick.
  private static let gaplaModeMenuItems: [(value: String, title: String, gauge: String)] = [
    ("tez", "Tez", "gauge.with.dots.needle.100percent"),
    ("orta", "O'rta", "gauge.with.dots.needle.50percent"),
    ("sekin", "Sekin", "gauge.with.dots.needle.0percent"),
    // Lokal: RubaiSTT on the Gapla server, slow (~22 s); the icon says "server", not speed.
    ("lokal", "Lokal", "server.rack"),
  ]

  private func refreshToneButton() {
    // Without Full Access the App Group is unreadable, so the mode cannot be saved.
    guard hasFullAccess else {
      toneButton.menu = nil
      toneButton.isUserInteractionEnabled = false
      toneButton.alpha = 0.4
      return
    }
    let current = KeyboardHandoffProvider.shared.currentGaplaMode()
    let actions: [UIAction] = Self.gaplaModeMenuItems.map { item in
      UIAction(title: item.title, state: item.value == current ? .on : .off) { [weak self] _ in
        KeyboardHandoffProvider.shared.setGaplaMode(item.value)
        self?.refreshToneButton()
      }
    }
    if let gauge = Self.gaplaModeMenuItems.first(where: { $0.value == current })?.gauge,
       let image = UIImage(systemName: gauge) {
      toneButton.setImage(image, for: .normal)
    }
    toneButton.accessibilityLabel = "Rejim"
    toneButton.menu = UIMenu(
      title: "Rejim: Tez — tezroq, Sekin — sifatliroq, Lokal — RubaiSTT (sekin)",
      children: actions
    )
    toneButton.isUserInteractionEnabled = true
    toneButton.alpha = 1.0
  }

  /// OpenWhispr's tone menu, kept for reference; Gapla shows the mode menu above instead.
  private func refreshOpenWhisprToneButton() {
    guard hasFullAccess else {
      toneButton.menu = nil
      toneButton.isUserInteractionEnabled = false
      toneButton.alpha = 0.4
      return
    }
    let provider = KeyboardHandoffProvider.shared
    let current = provider.currentTone()
    let applicable = provider.isToneApplicable()

    // When tone isn't applicable (private mode, or cleanup off) the styled tones
    // live behind Cloud. Lock every tone but Default so it reads as gated rather
    // than broken, and show the reason as a short, single-line header instead of
    // the old wrapping disabled row.
    let lockImage = applicable ? nil : UIImage(systemName: "lock.fill")
    let actions: [UIAction] = Self.toneMenuItems.map { item in
      let locked = !applicable && item.value != "default"
      let action = UIAction(
        title: item.title,
        image: locked ? lockImage : nil,
        state: item.value == current ? .on : .off
      ) { [weak self] _ in
        KeyboardHandoffProvider.shared.setTone(item.value)
        self?.refreshOpenWhisprToneButton()
      }
      if locked { action.attributes = [.disabled] }
      return action
    }

    // Label the menu in both states: its purpose when usable, the upgrade path
    // when locked. The header costs one row of the height-capped menu, so on
    // shorter keyboards the last tone ("Excited") can fall into the scroll
    // region instead of showing inline.
    let menuTitle = applicable ? "Diktovka ohangi" : "Lokal rejimda ohanglar o'chiq"
    toneButton.menu = UIMenu(title: menuTitle, children: actions)
    toneButton.isUserInteractionEnabled = true
    toneButton.alpha = applicable ? 1.0 : 0.4
  }

  /// The dictation deep link the agent button hands off with when the background
  /// session isn't ready — identical to the record button's, since the app keys
  /// the agent path off the presence of keyboard_agent_request, not the URL.
  private func setupAgentLink() {
    let provider = KeyboardHandoffProvider.shared
    var components = URLComponents(string: "\(Self.appUrlScheme)://keyboard-dictation")!
    components.queryItems = [URLQueryItem(name: "source", value: "keyboard")]
    if let scheme = provider.hostUrlScheme(from: self) {
      components.queryItems?.append(URLQueryItem(name: "returnScheme", value: scheme))
    }
    if let bundle = provider.detectHostBundleID(from: self) {
      components.queryItems?.append(URLQueryItem(name: "hostBundle", value: bundle))
    }
    guard let url = components.url else { return }

    let hosting = UIHostingController(rootView: DictationLinkView(url: url))
    hosting.view.backgroundColor = .clear
    hosting.view.isOpaque = false
    hosting.view.translatesAutoresizingMaskIntoConstraints = false

    addChild(hosting)
    agentButton.addSubview(hosting.view)
    hosting.didMove(toParent: self)

    NSLayoutConstraint.activate([
      hosting.view.leadingAnchor.constraint(equalTo: agentButton.leadingAnchor),
      hosting.view.trailingAnchor.constraint(equalTo: agentButton.trailingAnchor),
      hosting.view.topAnchor.constraint(equalTo: agentButton.topAnchor),
      hosting.view.bottomAnchor.constraint(equalTo: agentButton.bottomAnchor),
    ])

    agentLinkHosting = hosting
  }

  /// Gating mirrors refreshToneButton: hidden when the agent is disabled, dimmed
  /// (with a transient upgrade pill on tap) when Cloud isn't on. When usable, the
  /// Link overlay is enabled only for the handoff path — an in-place tap goes
  /// through requestStart() in the press handler instead.
  private func refreshAgentButton() {
    // isAgentEnabled() already fails closed on a dead App Group; stating it
    // makes the intent greppable rather than incidental.
    refreshTranslateButton()
    guard hasFullAccess else {
      agentButton.isHidden = true
      agentLinkHosting?.view.isUserInteractionEnabled = false
      return
    }
    // Gapla (G40): the button is now a dictation microphone, so it no longer follows the
    // voice-assistant switch or its account check; it is gated like the pill.
    let provider = KeyboardHandoffProvider.shared
    agentButton.isHidden = false
    agentButton.alpha = 1.0

    let recordsInPlace = provider.isBackgroundSessionReady()
      || hostIsOwnApp
      || provider.isContainingAppForeground()
    // The Link fires only for a hand-off tap; an in-place tap goes through the press handler.
    agentLinkHosting?.view.isUserInteractionEnabled = !recordsInPlace
  }


  /// Without Full Access the keyboard reaches no server, so the button is hidden, as the dictation button is. It also
  /// steps aside while the processing ✕ is up, which would overlap it. Lit while the translator is open.
  private func refreshTranslateButton() {
    translateButton.isHidden = !(hasFullAccess && processingCancelButton.isHidden)
    translateButton.isLongPressed = isTranslatorOpen
  }

  // MARK: Gapla translator inside the keyboard (G56)

  @objc private func handleTranslateButtonTapped() {
    playKeyClick()
    if isTranslatorOpen { closeTranslator() } else { openTranslator() }
  }

  /// The panel sits in the stack above the toolbar, so it fades with the keys under the recording orb; the results take
  /// the keys' place over the rows.
  private func installTranslatorViewsIfNeeded() {
    guard !translatorViewsInstalled else { return }
    translatorViewsInstalled = true
    let panel = translatorPanel
    panel.translatesAutoresizingMaskIntoConstraints = false
    panel.isHidden = true
    rootStack.insertArrangedSubview(panel, at: 0)
    let panelHeight = panel.heightAnchor.constraint(equalToConstant: GaplaTarjimonPanel.height)
    panelHeight.priority = UILayoutPriority(999)
    panelHeight.isActive = true

    let results = translatorResults
    results.translatesAutoresizingMaskIntoConstraints = false
    results.isHidden = true
    rootStack.addSubview(results)
    NSLayoutConstraint.activate([
      results.topAnchor.constraint(equalTo: keyboardRowsStack.topAnchor),
      results.bottomAnchor.constraint(equalTo: keyboardRowsStack.bottomAnchor),
      results.leadingAnchor.constraint(equalTo: keyboardRowsStack.leadingAnchor),
      results.trailingAnchor.constraint(equalTo: keyboardRowsStack.trailingAnchor),
    ])

    panel.onKeyClick = { [weak self] in self?.playKeyClick() }
    panel.onClose = { [weak self] in self?.closeTranslator() }
    panel.onTranslate = { [weak self] in self?.runTranslation() }
    panel.onPaste = { [weak self] in self?.pasteIntoTranslator() }
    panel.onClear = { [weak self] in self?.setTranslatorText("") }
    results.onEdit = { [weak self] in
      self?.playKeyClick()
      self?.showTranslatorResults(false)
    }
    results.onCopy = { [weak self] text in
      self?.playKeyClick()
      UIPasteboard.general.string = text
      self?.translatorResults.showNote("Nusxa olindi", isError: false)
    }
    results.onInsert = { [weak self] text in
      self?.playKeyClick()
      self?.insertTranslation(text)
    }
  }

  private func openTranslator() {
    installTranslatorViewsIfNeeded()
    if layoutMode != .letters { returnToLetters() }
    translatorText = ""
    // G67: every opening starts at O'zbekcha → Русский, with an empty text.
    translatorPanel.reset()
    translatorPanel.isHidden = false
    showTranslatorResults(false)
    applyTranslatorHeight()
    refreshTranslateButton()
    refreshTavsiya()
  }

  private func closeTranslator() {
    guard isTranslatorOpen else { return }
    translatorText = nil
    if translatorViewsInstalled {
      translatorClient.cancel()
      translatorPanel.setBusy(false)
      translatorPanel.isHidden = true
      showTranslatorResults(false)
    }
    applyTranslatorHeight()
    refreshTranslateButton()
    refreshTavsiya()
  }

  private func applyTranslatorHeight() {
    rootHeightConstraint?.constant = metrics.keyboardHeight + translatorExtraHeight
    applyKeyboardHeight()
  }

  private func showTranslatorResults(_ on: Bool) {
    guard translatorViewsInstalled else { return }
    translatorResults.isHidden = !on
    keyboardRowsStack.alpha = on ? 0 : 1
    keyboardRowsStack.isUserInteractionEnabled = !on
  }

  private func setTranslatorText(_ value: String) {
    guard isTranslatorOpen else { return }
    translatorText = value
    translatorPanel.setText(value)
    // G65: emptying the text drops the old translation; a new one comes only from the button.
    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      translatorClient.cancel()
      translatorPanel.setBusy(false)
      showTranslatorResults(false)
    }
  }

  /// Text from a key, the clipboard or dictation, added at the end — the line has no cursor of its own.
  private func appendToTranslator(_ piece: String, spaced: Bool = false) {
    guard var text = translatorText, !piece.isEmpty else { return }
    if spaced, let last = text.last, !last.isWhitespace, !piece.hasPrefix(" "), !piece.hasPrefix("\n") {
      text += " "
    }
    setTranslatorText(text + piece)
  }

  private func deleteFromTranslator(word: Bool) {
    guard var text = translatorText, !text.isEmpty else { return }
    if word {
      while let last = text.last, last.isWhitespace || last.isPunctuation { text.removeLast() }
      while let last = text.last, !(last.isWhitespace || last.isPunctuation) { text.removeLast() }
    } else {
      text.removeLast()
    }
    setTranslatorText(text)
  }

  private func pasteIntoTranslator() {
    guard let copied = UIPasteboard.general.string, !copied.isEmpty else {
      translatorPanel.setText(translatorText ?? "")
      return
    }
    appendToTranslator(copied, spaced: true)
  }

  /// Only from the «Tarjima» button (G65): typing, a language tap, a paste or dictation never translate.
  private func runTranslation() {
    guard let text = translatorText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
    translatorPanel.setBusy(true)
    let source = translatorPanel.source
    let target = translatorPanel.target
    translatorClient.translate(text, from: source, to: target) { [weak self] result in
      guard let self, self.isTranslatorOpen else { return }
      self.translatorPanel.setBusy(false)
      switch result {
      case .success(let natija):
        self.translatorResults.show(natija, from: source, to: target)
      case .failure(let error):
        self.translatorResults.showError(error.localizedDescription)
      }
      self.showTranslatorResults(true)
    }
  }

  /// «Joylash»: the translator closes and the chosen variant goes into the field the keyboard is typing in.
  private func insertTranslation(_ text: String) {
    closeTranslator()
    insertSmartText(text)
  }

  /// Gapla (G56): the translation picked with «Joylash» in the app's translator, typed into this field once.
  private func insertPendingTranslation() {
    guard let translation = KeyboardHandoffProvider.shared.consumePendingTranslation() else { return }
    insertSmartText(translation)
    refreshAfterEdit()
  }

  private func setupDictationLink() {
    let provider = KeyboardHandoffProvider.shared
    provider.storeHostReturnInfo(from: self)

    var components = URLComponents(string: "\(Self.appUrlScheme)://keyboard-dictation")!
    components.queryItems = [URLQueryItem(name: "source", value: "keyboard")]
    if let scheme = provider.hostUrlScheme(from: self) {
      components.queryItems?.append(URLQueryItem(name: "returnScheme", value: scheme))
    }
    if let bundle = provider.detectHostBundleID(from: self) {
      components.queryItems?.append(URLQueryItem(name: "hostBundle", value: bundle))
      hostIsOwnApp = provider.isContainingAppBundle(bundle)
    }

    guard let url = components.url else { return }

    let hosting = UIHostingController(rootView: DictationLinkView(url: url))
    hosting.view.backgroundColor = .clear
    hosting.view.isOpaque = false
    hosting.view.translatesAutoresizingMaskIntoConstraints = false

    addChild(hosting)
    recordButton.addSubview(hosting.view)
    hosting.didMove(toParent: self)

    NSLayoutConstraint.activate([
      hosting.view.leadingAnchor.constraint(equalTo: recordButton.leadingAnchor),
      hosting.view.trailingAnchor.constraint(equalTo: recordButton.trailingAnchor),
      hosting.view.topAnchor.constraint(equalTo: recordButton.topAnchor),
      hosting.view.bottomAnchor.constraint(equalTo: recordButton.bottomAnchor),
    ])

    dictationLinkHosting = hosting
  }

  private func setupKeyboardArea() {
    keyboardRowsStack.axis = .vertical
    keyboardRowsStack.spacing = metrics.rowGap
    keyboardRowsStack.translatesAutoresizingMaskIntoConstraints = false
    rootStack.addArrangedSubview(keyboardRowsStack)

    [lettersRowsStack, numbersRowsStack, symbolsRowsStack, emojiRowsStack, clipboardRowsStack].forEach { stack in
      stack.axis = .vertical
      stack.spacing = metrics.rowGap
      stack.translatesAutoresizingMaskIntoConstraints = false
    }

    keyboardRowsStack.addLayoutGuide(keyWidthGuide)
    let guideWidth = keyWidthGuide.widthAnchor.constraint(
      equalTo: keyboardRowsStack.widthAnchor,
      multiplier: 1 / Self.guideKeysPerRow,
      constant: -(Self.guideKeysPerRow - 1) / Self.guideKeysPerRow * metrics.keyGap
    )
    NSLayoutConstraint.activate([
      guideWidth,
      keyWidthGuide.leadingAnchor.constraint(equalTo: keyboardRowsStack.leadingAnchor),
      keyWidthGuide.topAnchor.constraint(equalTo: keyboardRowsStack.topAnchor),
      keyWidthGuide.heightAnchor.constraint(equalToConstant: 0),
    ])
    keyWidthGuideConstraint = guideWidth

    // Above the bar and the keys, and inside rootStack so it fades and locks with them
    // whenever a canvas covers the keyboard.
    rootStack.addSubview(keyPopup)
    rootStack.addSubview(alternatesPopup)
  }

  private func buildKeyboardIfNeeded() {
    guard !didBuildKeyboard else {
      refreshVisibleKeyboardMode()
      return
    }
    didBuildKeyboard = true
    rebuildKeyboard()
  }

  // Gapla (G38, owner 2026-11-11): one Uzbek Latin layout after the Turkish keyboard, without
  // the o' and g' keys — [so'zlari: bilim/gapla-goyalar-royxati.md]. As on the Turkish
  // keyboard: ğ after p, ş after l, ö ç after m. G59 (owner 2026-11-14: [so'zlari: bilim/gapla-goyalar-royxati.md]):
  // row 2 holds ten letters, so it sits half a key in from each edge, staggered under row 1 as on a real keyboard; the
  // comma left it for the bottom row, right of the space bar (makeCommaKey), where holding it still types a full stop
  // (G39). Row 3 keeps nine letters and full-width shift and delete keys. The apostrophe (ma'no, san'at) is on the 123
  // page, row 3. The Gapla Android keyboard gets the same order. The app's old «Klaviatura alifbosi» switch is gone; a
  // value it saved earlier changes nothing here.
  private static let letterRowsGapla: [[String]] = [
    ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "ğ"],
    ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ş"],
    ["z", "x", "c", "v", "b", "n", "m", "ö", "ç"],
  ]
  // Gapla (G58, owner 2026-11-14: [so'zlari: bilim/gapla-goyalar-royxati.md]): the other languages copy Apple's iPhone
  // layouts. Russian ЙЦУКЕН, with ё and ъ on the held е and ь (KeyboardLanguage.alternate); English QWERTY; Turkish Q,
  // with the dotless ı in row 1 and the dotted i at row 2's end. Their shift and delete follow addThirdRow's rule.
  private static let letterRowsRussian: [[String]] = [
    ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х"],
    ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
    ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"],
  ]
  private static let letterRowsEnglish: [[String]] = [
    ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
    ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
    ["z", "x", "c", "v", "b", "n", "m"],
  ]
  private static let letterRowsTurkish: [[String]] = [
    ["q", "w", "e", "r", "t", "y", "u", "ı", "o", "p", "ğ", "ü"],
    ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ş", "i"],
    ["z", "x", "c", "v", "b", "n", "m", "ö", "ç"],
  ]
  // Gapla (G60, owner 2026-11-14, approved sketch «taklif-3»: [so'zlari: bilim/gapla-goyalar-royxati.md]): the owner's
  // Russian on his laptop's QWERTY positions, laid out as G59's Uzbek — eleven keys, ten half a key in, nine between
  // shift and delete — with the comma right of the space bar. Rarer letters are held (KeyboardLanguage.alternates).
  private static let letterRowsRussianQwerty: [[String]] = [
    ["қ", "щ", "е", "р", "т", "й", "у", "и", "о", "п", "я"],
    ["а", "с", "д", "ф", "г", "ҳ", "ж", "к", "л", "ш"],
    ["з", "х", "ц", "в", "б", "н", "м", "ь", "ч"],
  ]

  /// keyWidthGuide is one of this many keys across the row in every language. Every width outside the letter rows
  /// (the 123 and #+= pages, the bottom row, the emoji page, the iPad's bottom row) is measured in it, so those keep
  /// their frames whatever the language (G58). It is the Uzbek letter key.
  private static let guideKeysPerRow: CGFloat = 11

  /// The keyboard language's letter rows.
  private var letterRows: [[String]] {
    switch keyboardLanguage {
    case .uz: return Self.letterRowsGapla
    case .ru: return Self.letterRowsRussian
    case .rq: return Self.letterRowsRussianQwerty
    case .en: return Self.letterRowsEnglish
    case .tr: return Self.letterRowsTurkish
    }
  }

  /// Letter keys across the language's widest row (11 Uzbek and Russian, 10 English, 12 Turkish): its letter key is
  /// the row less its gaps, divided by this (widthOfLetterKeys).
  private var lettersPerRow: CGFloat { CGFloat(letterRows.map { $0.count }.max() ?? 10) }
  // (display, output): the quote keys show curly marks and insert straight ones, which
  // smartQuoteSubstitution turns into context-aware curly quotes.
  // Gapla (G43, owner 2026-11-11, with screenshots of Apple's keyboard on his iPhone): [so'zlari: bilim/gapla-goyalar-royxati.md]. His region puts ₽ on the 123 page and $ € £ • on
  // the #+= page, so these rows copy that instead of Apple's US $ / € £ ¥.
  private static let numberRows: [[(display: String, output: String)]] = [
    "1234567890".map { (String($0), String($0)) },
    ["-", "/", ":", ";", "(", ")", "\u{20BD}", "&", "@"].map { ($0, $0) } + [("\u{201D}", "\"")],
  ]
  private static let symbolRows: [[(display: String, output: String)]] = [
    ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { ($0, $0) },
    ["_", "\\", "|", "~", "<", ">", "$", "\u{20AC}", "\u{00A3}", "\u{2022}"].map { ($0, $0) },
  ]
  private static let punctuationRow: [(display: String, output: String)] = [
    (".", "."), (",", ","), ("?", "?"), ("!", "!"), ("\u{2019}", "'"),
  ]

  private func rebuildKeyboard() {
    keyPopup.hide()
    for stack in [keyboardRowsStack, lettersRowsStack, numbersRowsStack, symbolsRowsStack, emojiRowsStack, clipboardRowsStack] {
      stack.arrangedSubviews.forEach { view in
        stack.removeArrangedSubview(view)
        view.removeFromSuperview()
      }
    }

    characterButtons.removeAll()
    shortcutButtons.removeAll()
    bottomRowConstraints = BottomRowConstraints()
    appliedBottomRowLayout = nil
    appliedReturnKeyState = nil
    keysBuiltWithGlobe = needsInputModeSwitchKey
    shiftButton = nil
    modeButton = nil
    spaceButton = nil
    returnButton = nil
    tabletExtraShiftButtons = []
    tabletExtraModeButtons = []
    tabletPageReturnButtons = []
    builtForTablet = appliedLayoutInputs?.tablet ?? false
    rowHeightConstraints.removeAll(keepingCapacity: true)

    // Pages first: key widths are constraints on keyWidthGuide, which can only be
    // activated once a row shares an ancestor with it.
    keyboardRowsStack.addArrangedSubview(lettersRowsStack)
    keyboardRowsStack.addArrangedSubview(numbersRowsStack)
    keyboardRowsStack.addArrangedSubview(symbolsRowsStack)
    keyboardRowsStack.addArrangedSubview(emojiRowsStack)
    keyboardRowsStack.addArrangedSubview(clipboardRowsStack)
    emojiButton = nil
    commaButton = nil
    clipboardPanel = nil
    alternateHeldKey = nil
    alternateChoices = []
    alternatesPopup.hide()

    let letters = letterRows.map { row in row.map { (display: $0, output: $0) } }
    if builtForTablet {
      addTabletLetterRows(letters, to: lettersRowsStack)
      addTabletBottomRow(to: keyboardRowsStack)
    } else {
      addCharacterRow(letters[0], to: lettersRowsStack, registersLetters: true)
      addCharacterRow(letters[1], to: lettersRowsStack, registersLetters: true)
      addLettersThirdRow(letters[2], to: lettersRowsStack)
      addMainBottomRow(to: keyboardRowsStack)
    }
    refreshVisibleKeyboardMode()
    refreshShiftState()
  }

  private func constrainRowHeight(_ row: UIView) {
    let constraint = row.heightAnchor.constraint(equalToConstant: metrics.keyHeight)
    // Below required so a view shorter than the keyboard squeezes the rows, not the toolbar.
    constraint.priority = UILayoutPriority(999)
    constraint.isActive = true
    rowHeightConstraints.append(constraint)
  }

  /// A width of `keys` letter keys plus `gaps` key gaps.
  /// Gapla (G46): a width in Apple's ten-letter key unit. Gapla's letter rows hold eleven keys
  /// (ğ, ş and the comma), so its letters are narrower, but the bottom row keeps Apple's
  /// widths — measured on the owner's iPhone: 123 46.7pt, emoji 47pt, return 100pt.
  /// G58: a ten-key row in the fixed guide unit, so it never changes with the keyboard's language.
  private func widthOfAppleKeys(
    _ view: UIView,
    keys: CGFloat,
    gaps: CGFloat = 0,
    priority: UILayoutPriority = .required
  ) -> NSLayoutConstraint {
    widthOfRowKeys(view, keys: keys, gaps: gaps, perRow: 10, priority: priority)
  }

  /// Gapla (G58): a width in the keyboard language's letter key — its widest row's keys share the row (lettersPerRow).
  private func widthOfLetterKeys(
    _ view: UIView,
    keys: CGFloat,
    gaps: CGFloat = 0,
    priority: UILayoutPriority = .required
  ) -> NSLayoutConstraint {
    widthOfRowKeys(view, keys: keys, gaps: gaps, perRow: lettersPerRow, priority: priority)
  }

  /// A width of `keys` keys plus `gaps` key gaps, where a key is one of `perRow` equal keys across the row. The row is
  /// guideKeysPerRow guide keys and (guideKeysPerRow − 1) gaps, or perRow keys and (perRow − 1) gaps, so one such key =
  /// (guideKeysPerRow / perRow) guide keys + ((guideKeysPerRow − perRow) / perRow) gaps.
  private func widthOfRowKeys(
    _ view: UIView,
    keys: CGFloat,
    gaps: CGFloat,
    perRow: CGFloat,
    priority: UILayoutPriority
  ) -> NSLayoutConstraint {
    let guideKeys = Self.guideKeysPerRow
    return widthOfKeys(
      view,
      keys: keys * guideKeys / perRow,
      gaps: gaps + keys * (guideKeys - perRow) / perRow,
      priority: priority
    )
  }

  private func widthOfKeys(
    _ view: UIView,
    keys: CGFloat,
    gaps: CGFloat = 0,
    priority: UILayoutPriority = .required
  ) -> NSLayoutConstraint {
    let constraint = view.widthAnchor.constraint(
      equalTo: keyWidthGuide.widthAnchor,
      multiplier: keys,
      constant: gaps * metrics.keyGap
    )
    constraint.priority = priority
    return constraint
  }

  /// A guide key's width at the current keyboard width, before layout has run.
  private var estimatedKeyWidth: CGFloat {
    let width = lastMetricsWidth > 0 ? lastMetricsWidth : UIScreen.main.bounds.width
    let keys = Self.guideKeysPerRow
    return max(0, (width - 2 * metrics.sideMargin - (keys - 1) * metrics.keyGap) / keys)
  }

  private func applyRootPadding() {
    rootStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: 0, leading: metrics.sideMargin, bottom: metrics.bottomPadding, trailing: metrics.sideMargin
    )
    rootStack.spacing = metrics.stripGapBelow
    // The rows take the padding at the keyboard's sides and bottom, and the half of the
    // gap below the toolbar that is nearer to them. The side margin is a half point, which
    // layout rounds to pixels; one more point reaches the screen edge whatever the scale.
    keyboardRowsStack.touchMargins = UIEdgeInsets(
      top: metrics.stripGapBelow / 2,
      left: metrics.sideMargin + 1,
      bottom: metrics.bottomPadding + 1,
      right: metrics.sideMargin + 1
    )
  }

  private func refreshMetricsIfNeeded() {
    let width = view.bounds.width
    guard width.isFinite, width > 0 else { return }
    // Orientation and the globe key count as well as width: a rotation can lay out at the
    // new width before the size class flips, and needsInputModeSwitchKey can settle late.
    let inputs = layoutInputs(width: width)
    if let appliedLayoutInputs, appliedLayoutInputs.matches(inputs) { return }
    appliedLayoutInputs = inputs
    let widthChanged = abs(width - lastMetricsWidth) > 1
    lastMetricsWidth = width

    let nextMetrics = KeyboardMetrics.current(for: inputs)
    let metricsChanged = nextMetrics != metrics
    if metricsChanged {
      metrics = nextMetrics
      applyRootPadding()
      rootHeightConstraint?.constant = metrics.keyboardHeight + translatorExtraHeight
      [keyboardRowsStack, lettersRowsStack, numbersRowsStack, symbolsRowsStack, emojiRowsStack, clipboardRowsStack].forEach {
        $0.spacing = metrics.rowGap
      }
      keyWidthGuideConstraint?.constant = -(Self.guideKeysPerRow - 1) / Self.guideKeysPerRow * metrics.keyGap
      topBarHeightConstraint?.constant = metrics.stripTop + metrics.stripHeight
      updateStripConstraints()
    }

    guard didBuildKeyboard else { return }
    if metricsChanged || keysBuiltWithGlobe != inputs.homeButton {
      rebuildKeyboard()
    } else if widthChanged {
      // The keys were built against an estimated width (the screen's, before the first
      // layout); their touch targets reach a key's width across the gaps.
      refreshKeyTouchOutsets()
    }
  }

  private var keyTouchOutsets: UIEdgeInsets {
    UIEdgeInsets(top: metrics.rowGap, left: estimatedKeyWidth, bottom: metrics.rowGap, right: estimatedKeyWidth)
  }

  private func refreshKeyTouchOutsets() {
    func visit(_ view: UIView) {
      if let key = view as? KeyButton {
        key.hitTestOutsets = keyTouchOutsets
        return
      }
      view.subviews.forEach(visit)
    }
    visit(keyboardRowsStack)
  }

  private func refreshVisibleKeyboardMode() {
    keyPopup.hide()
    tearDownEmojiPageIfLeft()
    buildPageIfNeeded()
    lettersRowsStack.isHidden = layoutMode != .letters
    numbersRowsStack.isHidden = layoutMode != .numbers
    symbolsRowsStack.isHidden = layoutMode != .symbols
    emojiRowsStack.isHidden = layoutMode != .emoji
    emojiButton?.isLongPressed = layoutMode == .emoji
    clipboardRowsStack.isHidden = layoutMode != .clipboard
    clipboardButton.isLongPressed = layoutMode == .clipboard
    let modeLabel = layoutMode == .letters ? metrics.keycaps.label123 : metrics.keycaps.labelABC
    // G46: the iPad's letters page says ".?123", as Apple's; the phone's says "123".
    let numbersTitle = builtForTablet ? ".?123" : "123"
    for button in [modeButton].compactMap({ $0 }) + tabletExtraModeButtons {
      button.setTitle(layoutMode == .letters ? numbersTitle : "ABC", for: .normal)
      button.accessibilityLabel = layoutMode == .letters ? "raqamlar" : "harflar"
      button.titleLabel?.font = modeLabel.font
      button.titleBaselineFromCenter = modeLabel.baseline
    }
    refreshFieldAwareKeys()
    refreshTavsiya()
  }

  /// The 123 and #+= pages are built the first time they show: built up front, they held
  /// about 2MB of the extension's memory while hidden.
  private func buildPageIfNeeded() {
    switch layoutMode {
    case .numbers where numbersRowsStack.arrangedSubviews.isEmpty && builtForTablet:
      addTabletSymbolRows(Self.numberRows, pageKeyTitle: "#+=", to: numbersRowsStack)
    case .numbers where numbersRowsStack.arrangedSubviews.isEmpty:
      addCharacterRow(Self.numberRows[0], to: numbersRowsStack, spansFullWidth: true)
      addCharacterRow(Self.numberRows[1], to: numbersRowsStack, spansFullWidth: true)
      addPunctuationThirdRow(pageKeyTitle: "#+=", to: numbersRowsStack)
    case .symbols where symbolsRowsStack.arrangedSubviews.isEmpty && builtForTablet:
      addTabletSymbolRows(Self.symbolRows, pageKeyTitle: "123", to: symbolsRowsStack)
    case .symbols where symbolsRowsStack.arrangedSubviews.isEmpty:
      addCharacterRow(Self.symbolRows[0], to: symbolsRowsStack, spansFullWidth: true)
      addCharacterRow(Self.symbolRows[1], to: symbolsRowsStack, spansFullWidth: true)
      addPunctuationThirdRow(pageKeyTitle: "123", to: symbolsRowsStack)
    case .emoji where emojiRowsStack.arrangedSubviews.isEmpty:
      addEmojiPage(to: emojiRowsStack)
    case .clipboard where clipboardRowsStack.arrangedSubviews.isEmpty:
      addClipboardPage(to: clipboardRowsStack)
    default:
      break
    }
  }

  // MARK: Gapla emoji page (G45)

  // Owner, 2026-11-11: [so'zlari: bilim/gapla-goyalar-royxati.md]. A custom keyboard can't open Apple's emoji
  // keyboard (advanceToNextInputMode only steps to the next keyboard in the list), so Gapla
  // draws its own page in the three letter rows' space: recently used first, then a scrolling
  // grid, and a delete key. ABC or the emoji key goes back to letters.
  private static let emojiColumns = 8
  private static let recentEmojiKey = "gapla_recent_emoji"
  private static let recentEmojiLimit = 16
  private static let emojiCatalog: [String] = (
    "😀😃😄😁😆😅😂🤣🥲☺️😊😇🙂🙃😉😌😍🥰😘😗😙😚😋😛😝😜🤪🤨🧐🤓😎🥸🤩🥳😏😒😞😔😟😕🙁☹️😣😖😫😩🥺😢😭😤😠😡🤬🤯😳🥵🥶😱😨😰😥😓🤗🤔🫡🤭🫢🤫🤥😶😐😑😬🙄😯😦😧😮😲🥱😴🤤😪😵🤐🥴🤢🤮🤧😷🤒🤕🤑🤠😈👿👻💀👽🤖💩"
      + "👋🤚🖐️✋🖖👌🤌🤏✌️🤞🫰🤟🤘🤙👈👉👆👇☝️👍👎✊👊🤛🤜👏🙌🫶👐🤲🤝🙏✍️💪"
      + "❤️🧡💛💚💙💜🖤🤍🤎💔❣️💕💞💓💗💖💘💝"
      + "🔥✨⭐️🌟💫🎉🎊🎁🎂🌹🌸🌷🌺🌻🌞🌙⚡️☀️🌧️❄️☕️🍵🍞🥖🍕🍔🍟🍉🍎🍇🍓🍒🍰🍫"
      + "🐱🐶🐭🐰🦊🐻🐼🐨🐯🦁🐮🐷🐸🐵🙈🙉🙊🐔🐧🐦🦋🐝"
      + "⚽️🏀🏆🥇🎵🎶🎧📱💻⌚️📷💡📚✏️📌📎✅❌⚠️❓❗️💯🆗🔔📍🏠🚗✈️🕌🤲"
  ).map { String($0) }

  private var recentEmoji: [String] {
    UserDefaults.standard.stringArray(forKey: Self.recentEmojiKey) ?? []
  }

  private func rememberEmoji(_ emoji: String) {
    var recent = recentEmoji.filter { $0 != emoji }
    recent.insert(emoji, at: 0)
    UserDefaults.standard.set(Array(recent.prefix(Self.recentEmojiLimit)), forKey: Self.recentEmojiKey)
  }

  private func addEmojiPage(to stack: UIStackView) {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(container)
    let pageHeight = container.heightAnchor.constraint(
      equalToConstant: 3 * metrics.keyHeight + 2 * metrics.rowGap
    )
    pageHeight.priority = UILayoutPriority(999)
    pageHeight.isActive = true

    // G57: a reusing grid (EmojiGridView) in place of a button per emoji; the page itself is
    // taken down when the keyboard leaves it (tearDownEmojiPageIfLeft).
    let recent = recentEmoji
    let emojis = recent + Self.emojiCatalog.filter { !recent.contains($0) }
    let cellHeight = max(36, (3 * metrics.keyHeight + 2 * metrics.rowGap - 6) / 4)
    let grid = EmojiGridView(emojis: emojis, columns: Self.emojiColumns, cellHeight: cellHeight, rowSpacing: 2)
    grid.onPick = { [weak self] emoji in
      self?.handleEmojiPicked(emoji)
    }
    grid.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(grid)

    let backspace = makeKeyButton(display: nil, imageSystemName: "delete.left", role: .utility)
    backspace.imageOffsetY = metrics.keycaps.edgeGlyphOffset
    backspace.accessibilityLabel = "o'chirish"
    backspace.addTarget(self, action: #selector(handleBackspaceTapped), for: .touchUpInside)
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleBackspaceLongPress(_:)))
    longPress.minimumPressDuration = 0.35
    backspace.addGestureRecognizer(longPress)
    container.addSubview(backspace)

    NSLayoutConstraint.activate([
      grid.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      grid.topAnchor.constraint(equalTo: container.topAnchor),
      grid.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      grid.trailingAnchor.constraint(equalTo: backspace.leadingAnchor, constant: -metrics.keyGap),
      backspace.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      backspace.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      backspace.heightAnchor.constraint(equalToConstant: metrics.keyHeight),
      widthOfKeys(backspace, keys: 1.5, gaps: 0),
    ])

    // After the page has laid out its first cells.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.logMemory("emoji-ochildi")
    }
  }

  /// G57: the emoji page is taken down as soon as the keyboard shows another page, so its views
  /// don't stay in the extension's memory while hidden; it is built again (recently used first) on
  /// the next open.
  private func tearDownEmojiPageIfLeft() {
    guard layoutMode != .emoji, !emojiRowsStack.arrangedSubviews.isEmpty else { return }
    emojiRowsStack.arrangedSubviews.forEach { view in
      emojiRowsStack.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.logMemory("emoji-yopildi")
    }
  }

  private func handleEmojiPicked(_ emoji: String) {
    playKeyClick()
    countTypedWordIfFinished()
    typeText(emoji)
    rememberEmoji(emoji)
    refreshAfterEdit()
  }

  /// The bottom row's emoji key: letters or a number page ⇄ the emoji page.
  @objc private func handleEmojiKeyTapped() {
    playKeyClick()
    if layoutMode == .emoji {
      returnToLetters()
    } else {
      layoutMode = .emoji
      typedOnSymbolPage = false
      isCapsLocked = false
      isShiftEnabled = false
      refreshVisibleKeyboardMode()
      refreshShiftState()
    }
  }

  // MARK: Gapla shared clipboard (G8)

  private func addClipboardPage(to stack: UIStackView) {
    let panel = GaplaClipboardPanel(
      client: GaplaClipboardClient(accessGroup: "group.\(Self.resolvedContainingAppBundleID)"),
      hasFullAccess: { [weak self] in self?.hasFullAccess ?? false },
      rowBackground: Palette.keyBackground,
      textColor: Palette.keyText,
      accent: Palette.accentTint
    )
    panel.onKeyClick = { [weak self] in self?.playKeyClick() }
    panel.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(panel)
    let pageHeight = panel.heightAnchor.constraint(equalToConstant: 3 * metrics.keyHeight + 2 * metrics.rowGap)
    pageHeight.priority = UILayoutPriority(999)
    pageHeight.isActive = true
    clipboardPanel = panel
    // Built while the page is showing (first open, or a rebuild on rotation): the saved list
    // only — the server is asked on the button tap alone.
    panel.showSaved()
  }

  /// The toolbar's clipboard button: letters or any page ⇄ the clipboard page. Each tap shows
  /// the saved list at once and refreshes it from the server; never in the background (owner's
  /// rule).
  @objc private func handleClipboardButtonTapped() {
    playKeyClick()
    if layoutMode == .clipboard {
      returnToLetters()
      return
    }
    layoutMode = .clipboard
    typedOnSymbolPage = false
    isCapsLocked = false
    isShiftEnabled = false
    refreshVisibleKeyboardMode() // builds the page the first time
    refreshShiftState()
    clipboardPanel?.open()
  }

  // MARK: Gapla word suggestions (G41, G55)

  /// While a word is being typed, or right after one and a space, the toolbar's left side shows up to three words from
  /// the owner's list (GaplaTavsiya.swift); otherwise the toolbar. The dictation button on the right always stays, and
  /// the keyboard keeps its height (owner, 2026-11-11).
  private func refreshTavsiya() {
    let shown = tavsiyaItems()
    tavsiyaBar.isHidden = shown == nil
    toneButton.isHidden = shown != nil
    clipboardButton.isHidden = shown != nil
    if let shown { tavsiyaBar.show(shown.words, literal: shown.literal) }
    logTavsiyaState(shown: shown != nil)
  }

  /// G55 diagnosis (owner 2026-11-14: «matn tavsiyasi ishlamayapti»): why the row shows or not, written to the device
  /// log when the reason changes — `pymobiledevice3 syslog live -m gapla-tavsiya`.
  private var lastTavsiyaReason: String?

  private func logTavsiyaState(shown: Bool) {
    let reason: String
    if shown {
      reason = "korinadi"
    } else if !hasFullAccess {
      reason = "full-access-yoq"
    } else if !recordButton.isHidden {
      reason = "pill-korinib-turibdi"
    } else if isAgentReviewShown || recordingOrb.isShowing {
      reason = "agent-yoki-shar"
    } else if !(layoutMode == .letters || layoutMode == .numbers || layoutMode == .symbols) {
      reason = "sahifa"
    } else if !tavsiyaShows {
      reason = "til-\(keyboardLanguage.rawValue)"
    } else if !tavsiyaFieldShows {
      reason = "maydon-parol"
    } else if !GaplaTavsiya.shared.hasWords {
      reason = "lugat-bosh"
    } else if !(textDocumentProxy.selectedText ?? "").isEmpty {
      reason = "tanlangan-matn"
    } else if textDocumentProxy.documentContextBeforeInput == nil {
      reason = "oldingi-matn-yoq"
    } else {
      reason = "soz-yoq"
    }
    guard reason != lastTavsiyaReason else { return }
    lastTavsiyaReason = reason
    KeyboardLog.ui.notice("gapla-tavsiya \(reason, privacy: .public)")
  }

  /// The words to show, best first; nil shows the toolbar. `literal`: nothing in the list matches the word being
  /// typed, so it is shown as typed, in quotes.
  private func tavsiyaItems() -> (words: [String], literal: Bool)? {
    guard hasFullAccess, recordButton.isHidden, !isAgentReviewShown, !recordingOrb.isShowing,
          layoutMode == .letters || layoutMode == .numbers || layoutMode == .symbols,
          tavsiyaFieldShows, GaplaTavsiya.shared.hasWords
    else { return nil }
    let proxy = textDocumentProxy
    guard (proxy.selectedText ?? "").isEmpty,
          let before = proxy.documentContextBeforeInput,
          let context = GaplaTavsiya.Context(before: before)
    else { return nil }
    // Letters after the cursor too: it stands inside a word, which a suggestion would split.
    if let next = proxy.documentContextAfterInput?.first, GaplaTavsiya.isWordCharacter(next) { return nil }
    let found = GaplaTavsiya.shared.suggest(partial: context.partial, previous: context.previous)
    if found.isEmpty {
      return context.partial.isEmpty ? nil : ([context.partial], true)
    }
    return (found.map { tavsiyaCased($0, partial: context.partial) }, false)
  }

  /// A suggestion takes the typed capitals: «Sal» → «Salom», «SG» → «SGBF», and a capital at a sentence's start.
  private func tavsiyaCased(_ word: String, partial: String) -> String {
    if isCapsLocked { return word.uppercased() }
    guard let first = partial.first else {
      return isShiftEnabled && layoutMode == .letters ? GaplaTavsiya.capitalizedFirst(word) : word
    }
    let letters = partial.filter { $0.isLetter }
    if letters.count > 1 && letters.allSatisfy({ $0.isUppercase }) { return word.uppercased() }
    return first.isUppercase ? GaplaTavsiya.capitalizedFirst(word) : word
  }

  /// Gapla (G58): words are counted toward the owner's list, and sent to the server, only from the Uzbek keyboard —
  /// the typed word, countTypedWordIfFinished, a picked suggestion and viewWillDisappear's flush ask this.
  private var tavsiyaOn: Bool { keyboardLanguage == .uz && !isTranslatorOpen }

  /// Gapla (G62, owner 2026-11-14: [so'zlari: bilim/gapla-goyalar-royxati.md], chose «O'zbekcha hamma tilda»): the
  /// Uzbek list is also suggested on the Turkish and English keyboards, where he types Uzbek too; nothing typed there
  /// is counted (tavsiyaOn). The Cyrillic keyboards show none: no Latin word can match them.
  private var tavsiyaShows: Bool {
    !isTranslatorOpen && (keyboardLanguage == .uz || keyboardLanguage == .tr || keyboardLanguage == .en)
  }

  /// G58/G62: the saved word list is read, and fetched again when due, while the keyboard suggests (tavsiyaShows).
  private func startTavsiyaIfOn() {
    guard hasFullAccess, tavsiyaShows else { return }
    GaplaTavsiya.shared.start(accessGroup: "group.\(Self.resolvedContainingAppBundleID)")
  }

  /// Gapla (G69, owner 2026-11-15: «hamma joyda chiqsin»; in Messages the row never showed, the device log said
  /// «maydon»): suggestions show in every field but a password one — e-mail, address, number fields and fields without
  /// autocorrection too. G62: Uzbek, Turkish and English keyboards (tavsiyaShows).
  private var tavsiyaFieldShows: Bool {
    tavsiyaShows && textDocumentProxy.isSecureTextEntry != true
  }

  /// Contract rule 6: nothing is counted (learned) in password, e-mail, address, number or name-and-phone fields, or
  /// where the field turns autocorrection off. Counting stays Uzbek (tavsiyaOn).
  private var tavsiyaFieldCounts: Bool {
    guard tavsiyaShows else { return false }
    let proxy = textDocumentProxy
    if proxy.isSecureTextEntry == true { return false }
    if (proxy.autocorrectionType ?? .default) == .no { return false }
    switch proxy.keyboardType ?? .default {
    case .emailAddress, .URL, .numberPad, .phonePad, .decimalPad, .numbersAndPunctuation, .asciiCapableNumberPad,
      .namePhonePad:
      return false
    default:
      return true
    }
  }

  /// A tap on a suggestion: it replaces the word being typed and a space follows; it counts as a word he wrote.
  private func handleTavsiyaPicked(_ word: String) {
    playKeyClick()
    let proxy = textDocumentProxy
    let before = proxy.documentContextBeforeInput ?? ""
    let context = GaplaTavsiya.Context(before: before)
    let partial = context?.partial ?? ""
    for _ in 0..<partial.count { proxy.deleteBackward() }
    if hasFullAccess && tavsiyaOn && tavsiyaFieldCounts {
      GaplaTavsiya.shared.countTyped(
        word,
        previous: context?.previous,
        sentenceStart: GaplaTavsiya.isSentenceStart(context?.textBefore ?? before)
      )
    }
    tavsiyaTypedWord = ""
    tavsiyaLastCounted = word
    // G69: an e-mail or web address takes no space after the picked word.
    let keyboardType = proxy.keyboardType ?? .default
    if keyboardType == .emailAddress || keyboardType == .URL {
      typeText(word)
    } else if proxy.documentContextAfterInput?.first == " " {
      typeText(word)
      proxy.adjustTextPosition(byCharacterOffset: 1)
    } else {
      typeText(word + " ")
    }
    if layoutMode != .letters { returnToLetters() }
    syncShiftWithContextIfNeeded()
    refreshAfterEdit()
  }

  /// Holding a suggestion (owner's «unut»): the word is not offered again, here or on his other devices.
  private func handleTavsiyaForget(_ word: String) {
    playKeyClick()
    GaplaTavsiya.shared.forget(word)
    tavsiyaBar.showNote("\u{00AB}\(word)\u{00BB} unutildi")
    refreshTavsiya()
  }

  /// A word typed on the keys has ended — space, return, punctuation or an emoji comes next. It counts toward the
  /// owner's list (contract: only counts, never the sentence) when the field shows the same letters before the cursor.
  private func countTypedWordIfFinished() {
    let typed = tavsiyaTypedWord
    tavsiyaTypedWord = ""
    guard !typed.isEmpty, hasFullAccess, tavsiyaOn, tavsiyaFieldCounts,
          let before = textDocumentProxy.documentContextBeforeInput,
          let context = GaplaTavsiya.Context(before: before),
          !context.partial.isEmpty,
          context.partial.lowercased() == typed.lowercased()
    else {
      tavsiyaLastCounted = nil
      return
    }
    // A pair only with the word counted just before, with nothing but spaces between them.
    var previous: String?
    if let candidate = context.previous, tavsiyaLastCounted?.lowercased() == candidate.lowercased() {
      previous = candidate
    }
    GaplaTavsiya.shared.countTyped(
      context.partial,
      previous: previous,
      sentenceStart: GaplaTavsiya.isSentenceStart(context.textBefore)
    )
    tavsiyaLastCounted = context.partial
  }

  private func refreshFieldAwareKeys() {
    refreshReturnKey()
    refreshBottomRow()
    refreshCommaKey()
  }

  /// G59: the bottom row's comma shows on the Uzbek letters page of an ordinary field only. The 123 and #+= pages have
  /// their own comma, and URL, e-mail, search and Twitter fields keep Apple's keys there (BottomRowLayout.shortcuts).
  private func refreshCommaKey() {
    guard let commaButton else { return }
    let layout = BottomRowLayout.forKeyboardType(textDocumentProxy.keyboardType, letters: layoutMode == .letters)
    let shows = keyboardLanguage.commaBesideSpace && layoutMode == .letters && layout.shortcuts.isEmpty && layout.showsSpace
    if commaButton.isHidden == shows { commaButton.isHidden = !shows }
  }

  private var isReturnKeyDisabled: Bool {
    // A field that hides its text can't show it's empty, so its return key stays usable.
    textDocumentProxy.enablesReturnKeyAutomatically == true && !textDocumentProxy.hasText && !fieldHidesItsText
  }

  private func refreshReturnKey() {
    guard let returnButton else { return }
    let style = ReturnKeyStyle.forReturnKeyType(textDocumentProxy.returnKeyType)
    let isDisabled = isReturnKeyDisabled
    let state = ReturnKeyState(style: style, isDisabled: isDisabled)
    guard state != appliedReturnKeyState else { return }
    appliedReturnKeyState = state
    // G46: on the iPad the 123 and #+= pages carry their own return keys.
    for key in [returnButton] + tabletPageReturnButtons {
      styleReturnKey(key, style: style, isDisabled: isDisabled)
    }
  }

  private func styleReturnKey(_ returnButton: KeyButton, style: ReturnKeyStyle, isDisabled: Bool) {
    returnButton.setImage(UIImage(systemName: style.symbolName)?.withRenderingMode(.alwaysTemplate), for: .normal)
    returnButton.imageOffsetY = style.glyphOffsetY
    returnButton.accessibilityLabel = style.accessibilityLabel
    // Neither isEnabled (UIKit would dim the glyph on top of Apple's disabled colours) nor
    // isUserInteractionEnabled: KeyboardRowsStack would pass the key over and give its taps
    // to the space or ".com" key beside it. The key keeps its taps; handleReturnTapped
    // ignores them while it's greyed.
    returnButton.accessibilityTraits = isDisabled ? [.button, .notEnabled] : .button
    if isDisabled {
      returnButton.normalBackground = Palette.keyDisabledBackground
      returnButton.pressedBackground = nil
      returnButton.pressedTint = nil
      returnButton.tintColor = Palette.keyDisabledText
    } else if style.isProminent {
      returnButton.normalBackground = Palette.returnKeyProminent
      returnButton.pressedBackground = Palette.keyBackground
      returnButton.pressedTint = Palette.keyText
      returnButton.tintColor = .white
    } else {
      returnButton.normalBackground = Palette.keyBackground
      returnButton.pressedBackground = Palette.keyPressedBackground
      returnButton.pressedTint = nil
      returnButton.tintColor = Palette.keyText
    }
  }

  private func refreshBottomRow() {
    let layout = BottomRowLayout.forKeyboardType(textDocumentProxy.keyboardType, letters: layoutMode == .letters)
    guard layout != appliedBottomRowLayout, shortcutButtons.count == 3, let spaceButton, let returnButton
    else { return }
    appliedBottomRowLayout = layout

    let constraints = bottomRowConstraints
    NSLayoutConstraint.deactivate(constraints.halfWidth + constraints.letterWidth + constraints.sharedWidth)
    for (index, button) in shortcutButtons.enumerated() {
      let value = layout.shortcuts.indices.contains(index) ? layout.shortcuts[index] : nil
      button.output = value
      button.setTitle(value, for: .normal)
      button.isHidden = value == nil
      guard let value else { continue }
      let isDomain = value.count > 1
      button.titleLabel?.font = isDomain ? KeyFont.domainLabel : metrics.keycaps.uppercase
      button.titleBaselineFromCenter = isDomain
        ? metrics.keycaps.domainBaseline
        : KeyFont.shortcutBaseline(for: value, raisesPeriod: layout.raisesPeriod)
      switch layout.shortcutWidth {
      case .shared:
        if index > 0 { constraints.sharedWidth[index - 1].isActive = true }
      case .half:
        constraints.halfWidth[index].isActive = true
      case .letter:
        constraints.letterWidth[index].isActive = true
      }
    }
    spaceButton.isHidden = !layout.showsSpace
    // G46: the iPad's return sits in row 2, where hiding it would leave a hole.
    if !builtForTablet {
      returnButton.isHidden = !layout.showsReturn
    }
    constraints.returnWidth?.isActive = !layout.narrowReturn
    constraints.narrowReturnWidth?.isActive = layout.narrowReturn
  }

  private func playKeyClick() {
    UIDevice.current.playInputClick()
  }

  /// A row container, already in `stack` so its keys can be sized against keyWidthGuide.
  private func addRowContainer(to stack: UIStackView) -> UIView {
    let rowContainer = UIView()
    rowContainer.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(rowContainer)
    constrainRowHeight(rowContainer)
    return rowContainer
  }

  /// One row of equal character keys. Rows shorter than ten keys are centred, which
  /// gives the A row Apple's half-key indent.
  /// Gapla (G57, owner 2026-11-13: the 123 and #+= keys «ikki yondan qisilib qolgan»): `spansFullWidth` stretches the
  /// row from edge to edge, as on Apple's keyboard — 6.5pt margin, 6pt gaps, equal keys. The phone's 123 and #+= rows
  /// hold ten keys; sized in the letters' eleven-key unit and centred, they left about 24pt empty at each side.
  private func addCharacterRow(
    _ keys: [(display: String, output: String)],
    to stack: UIStackView,
    registersLetters: Bool = false,
    spansFullWidth: Bool = false
  ) {
    let rowContainer = addRowContainer(to: stack)
    let rowStack = makeKeyStack(keys, registersLetters: registersLetters)
    rowContainer.addSubview(rowStack)
    let horizontal: [NSLayoutConstraint]
    if spansFullWidth {
      horizontal = [
        rowStack.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor),
        rowStack.trailingAnchor.constraint(equalTo: rowContainer.trailingAnchor),
      ]
    } else {
      // G58: letter rows, in the keyboard language's letter key.
      horizontal = [
        rowStack.centerXAnchor.constraint(equalTo: rowContainer.centerXAnchor),
        widthOfLetterKeys(rowStack, keys: CGFloat(keys.count), gaps: CGFloat(keys.count - 1)),
      ]
    }
    NSLayoutConstraint.activate(horizontal + [
      rowStack.topAnchor.constraint(equalTo: rowContainer.topAnchor),
      rowStack.bottomAnchor.constraint(equalTo: rowContainer.bottomAnchor),
    ])
  }

  private func makeKeyStack(
    _ keys: [(display: String, output: String)],
    registersLetters: Bool
  ) -> UIStackView {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = metrics.keyGap
    stack.distribution = .fillEqually
    stack.translatesAutoresizingMaskIntoConstraints = false
    for key in keys {
      let button = makeKeyButton(display: key.display, output: key.output, role: .character)
      // The face is a closing quote; what it types depends on the text before it.
      switch key.output {
      case "\"": button.accessibilityLabel = "qo'shtirnoq"
      case "'": button.accessibilityLabel = "apostrof"
      case ",":
        button.accessibilityLabel = "vergul"
        // Gapla (G39): only the letters-page comma turns into a full stop when held.
        if registersLetters {
          let commaPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleCommaLongPress(_:))
          )
          commaPress.minimumPressDuration = 0.4
          button.addGestureRecognizer(commaPress)
        }
      default:
        // Gapla (G58): letters with an Apple alternate type it when held (Russian е → ё, ь → ъ).
        if registersLetters, !keyboardLanguage.alternates(for: key.output).isEmpty {
          let alternatePress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleAlternateLongPress(_:))
          )
          alternatePress.minimumPressDuration = 0.4
          button.addGestureRecognizer(alternatePress)
        }
      }
      button.addTarget(self, action: #selector(handleCharacterKeyTapped(_:)), for: .touchUpInside)
      button.addTarget(self, action: #selector(handleCharacterKeyDown(_:)), for: .touchDown)
      button.addTarget(
        self,
        action: #selector(handleCharacterKeyReleased(_:)),
        for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
      )
      if registersLetters {
        characterButtons.append(button)
      }
      stack.addArrangedSubview(button)
    }
    return stack
  }

  private func addLettersThirdRow(_ keys: [(display: String, output: String)], to stack: UIStackView) {
    let shift = makeShiftKey()
    shiftButton = shift
    // Gapla: row 3 carries Uzbek letters too, so its keys keep a letter key's width each.
    addThirdRow(
      leadingKey: shift,
      keys: makeKeyStack(keys, registersLetters: true),
      letterSlots: max(7, keys.count),
      to: stack
    )
  }

  /// Row 3 of the phone's 123 and #+= pages, as on Apple's keyboard (G57): the page key and delete at the edges in
  /// Apple's shift width (`functionKeys` Apple keys), the five symbol keys sharing the rest equally, with ordinary key
  /// gaps between all seven. Centred in seven letter widths, as before, they left ~31pt holes beside the edge keys.
  private func addPunctuationThirdRow(pageKeyTitle: String, to stack: UIStackView) {
    let rowContainer = addRowContainer(to: stack)
    let pageKey = makePageKey(title: pageKeyTitle)
    let keys = makeKeyStack(Self.punctuationRow, registersLetters: false)
    let backspace = makeBackspaceKey()
    for item in [pageKey, keys, backspace] {
      rowContainer.addSubview(item)
      item.topAnchor.constraint(equalTo: rowContainer.topAnchor).isActive = true
      item.bottomAnchor.constraint(equalTo: rowContainer.bottomAnchor).isActive = true
    }
    NSLayoutConstraint.activate([
      pageKey.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor),
      widthOfAppleKeys(pageKey, keys: metrics.functionKeys),
      backspace.trailingAnchor.constraint(equalTo: rowContainer.trailingAnchor),
      widthOfAppleKeys(backspace, keys: metrics.functionKeys),
      keys.leadingAnchor.constraint(equalTo: pageKey.trailingAnchor, constant: metrics.keyGap),
      keys.trailingAnchor.constraint(equalTo: backspace.leadingAnchor, constant: -metrics.keyGap),
    ])
  }

  private func makeShiftKey() -> KeyButton {
    let shift = makeKeyButton(display: nil, imageSystemName: "shift", role: .utility)
    shift.imageOffsetY = metrics.keycaps.edgeGlyphOffset
    shift.addTarget(self, action: #selector(handleShiftTapped), for: .touchUpInside)
    return shift
  }

  /// The #+= key on the 123 page, the 123 key on the #+= page.
  private func makePageKey(title: String) -> KeyButton {
    let pageKey = makeKeyButton(display: title, role: .utility)
    pageKey.accessibilityLabel = title == "#+=" ? "boshqa belgilar" : "raqamlar"
    if title == "#+=" {
      pageKey.titleLabel?.font = KeyFont.moreSymbolsLabel
      pageKey.titleBaselineFromCenter = KeyFont.moreSymbolsBaseline
    } else {
      pageKey.titleLabel?.font = KeyFont.pageLabel
    }
    pageKey.addTarget(self, action: #selector(handlePageKeyTapped), for: .touchUpInside)
    return pageKey
  }

  private func makeBackspaceKey() -> KeyButton {
    let backspace = makeKeyButton(display: nil, imageSystemName: "delete.left", role: .utility)
    backspace.imageOffsetY = metrics.keycaps.edgeGlyphOffset
    backspace.accessibilityLabel = "o'chirish"
    backspace.addTarget(self, action: #selector(handleBackspaceTapped), for: .touchUpInside)
    let longPress = UILongPressGestureRecognizer(
      target: self,
      action: #selector(handleBackspaceLongPress(_:))
    )
    longPress.minimumPressDuration = 0.35
    backspace.addGestureRecognizer(longPress)
    return backspace
  }

  private func makeReturnKey() -> KeyButton {
    let returnKey = makeKeyButton(display: nil, imageSystemName: "return.left", role: .utility)
    returnKey.addTarget(self, action: #selector(handleReturnTapped), for: .touchUpInside)
    return returnKey
  }

  /// Row 3 of the phone's letters page: a function key at each edge and the letter keys
  /// centred between them (the 123 and #+= pages build theirs in addPunctuationThirdRow).
  private func addThirdRow(
    leadingKey: KeyButton,
    keys: UIStackView,
    letterSlots: Int = 7,
    to stack: UIStackView
  ) {
    let rowContainer = addRowContainer(to: stack)
    // Gapla: with more letters in the row, shift and delete give up width so the row fits. G58: all three in the
    // keyboard language's letter key — Uzbek and Russian 1 key each, English 1.35, Turkish 1.35 of its narrower key.
    let slots = CGFloat(letterSlots)
    let functionKeyWidth = min(metrics.functionKeys, (lettersPerRow - slots) / 2)

    let backspace = makeBackspaceKey()

    for item in [leadingKey, keys, backspace] {
      rowContainer.addSubview(item)
      item.topAnchor.constraint(equalTo: rowContainer.topAnchor).isActive = true
      item.bottomAnchor.constraint(equalTo: rowContainer.bottomAnchor).isActive = true
    }
    NSLayoutConstraint.activate([
      leadingKey.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor),
      widthOfLetterKeys(leadingKey, keys: functionKeyWidth),
      backspace.trailingAnchor.constraint(equalTo: rowContainer.trailingAnchor),
      widthOfLetterKeys(backspace, keys: functionKeyWidth),
      keys.centerXAnchor.constraint(equalTo: rowContainer.centerXAnchor),
      widthOfLetterKeys(keys, keys: slots, gaps: slots - 1),
    ])
  }

  // MARK: Gapla iPad layout (G46)

  // Owner, 2026-11-12, with photos of Gapla and of Apple's own keyboard on his iPad: [so'zlari: bilim/gapla-goyalar-royxati.md]. Apple's
  // iPad keyboard: row 1 ends with delete, row 2 with return, row 3 has a shift at each end, and
  // the bottom row is .?123 · globe · space · .?123 · hide keyboard. The Uzbek letters sit where
  // Apple's Turkish-Q iPad keyboard has them, as on the phone: ğ after p, ş after l, ö ç after m.
  // G59: the comma (held: full stop) sits right of the space bar, and row 2 is indented — see
  // addTabletLetterRows. Letter keys are equal in every row (12.5 letter widths).
  private static let tabletDeleteKeys: CGFloat = 1.5
  private static let tabletReturnKeys: CGFloat = 1.5
  private static let tabletShiftKeys: CGFloat = 1.25
  /// The bottom row's keys, in keyWidthGuide units (an eleventh of the row less gaps, about
  /// 1.14 iPad letter keys): .?123 and hide ≈ 1.5 letters, the globe ≈ 1.
  private static let tabletBottomSideKeys: CGFloat = 1.3
  private static let tabletBottomGlobeKeys: CGFloat = 0.9

  private func addTabletLetterRows(_ letters: [[(display: String, output: String)]], to stack: UIStackView) {
    // G58: every language keeps this shape — delete after row 1, return after row 2, a shift at each end of row 3 and
    // the full stop after its last letter. The three rows span as many letter widths as the widest needs at the sizes
    // above, and the function keys take what each row's letters leave, so letter keys stay equal across rows. Uzbek
    // and Russian keep 1.5 · 1.5 · 1.25 (12.5); English gets 1.5 · 2.5 · 1.75 (11.5), Turkish 1.5 · 2.5 · 1.75 (13.5).
    // G59 (owner 2026-11-14: [so'zlari: bilim/gapla-goyalar-royxati.md]): Uzbek's comma and full stop left the letter
    // rows for the bottom row's comma key (held: full stop), and row 2 starts half a key in, staggered under row 1 as
    // on Apple's Turkish iPad keyboard: 11 + delete (1.5) = half-key indent + 10 + return (2) = shift (1.75) + 9 +
    // shift (1.75) = 12.5 letter widths.
    let staggered = keyboardLanguage.commaBesideSpace  // G59 Uzbek, G60 Russian QWERTY
    let thirdRow = staggered ? letters[2] : letters[2] + [(display: ".", output: ".")]
    let secondRowIndent: CGFloat = staggered ? 0.5 : 0
    let secondRowLeading: [(key: KeyButton, keys: CGFloat)] =
      staggered ? [(key: makeRowIndent(), keys: secondRowIndent)] : []
    let rowKeys = max(
      CGFloat(letters[0].count) + Self.tabletDeleteKeys,
      secondRowIndent + CGFloat(letters[1].count) + Self.tabletReturnKeys,
      CGFloat(thirdRow.count) + 2 * Self.tabletShiftKeys
    )
    let deleteKeys = rowKeys - CGFloat(letters[0].count)
    let returnKeys = rowKeys - secondRowIndent - CGFloat(letters[1].count)
    let shiftKeys = (rowKeys - CGFloat(thirdRow.count)) / 2

    addTabletRow(
      keys: makeKeyStack(letters[0], registersLetters: true),
      trailing: [(makeBackspaceKey(), deleteKeys)],
      to: stack
    )
    let returnKey = makeReturnKey()
    returnButton = returnKey
    addTabletRow(
      leading: secondRowLeading,
      keys: makeKeyStack(letters[1], registersLetters: true),
      trailing: [(returnKey, returnKeys)],
      to: stack
    )
    let leftShift = makeShiftKey()
    let rightShift = makeShiftKey()
    shiftButton = leftShift
    tabletExtraShiftButtons = [rightShift]
    addTabletRow(
      leading: [(leftShift, shiftKeys)],
      keys: makeKeyStack(thirdRow, registersLetters: true),
      trailing: [(rightShift, shiftKeys)],
      to: stack
    )
  }

  /// The 123 and #+= pages on the iPad: delete ends row 1 and return row 2, as on the letters
  /// page, and the page key sits at both ends of row 3.
  private func addTabletSymbolRows(
    _ rows: [[(display: String, output: String)]],
    pageKeyTitle: String,
    to stack: UIStackView
  ) {
    addTabletRow(
      keys: makeKeyStack(rows[0], registersLetters: false),
      trailing: [(makeBackspaceKey(), Self.tabletDeleteKeys)],
      to: stack
    )
    let returnKey = makeReturnKey()
    tabletPageReturnButtons.append(returnKey)
    // A new return key takes the field's look on the next refreshReturnKey.
    appliedReturnKeyState = nil
    addTabletRow(
      keys: makeKeyStack(rows[1], registersLetters: false),
      trailing: [(returnKey, Self.tabletReturnKeys)],
      to: stack
    )
    addTabletRow(
      leading: [(makePageKey(title: pageKeyTitle), Self.tabletReturnKeys)],
      keys: makeKeyStack(Self.punctuationRow, registersLetters: false),
      trailing: [(makePageKey(title: pageKeyTitle), Self.tabletReturnKeys)],
      to: stack
    )
  }

  /// G59: an empty slot that indents an iPad row. Invisible and untouchable, so KeyboardRowsStack gives its taps to
  /// the nearest key, as it does for the phone's centred rows.
  private func makeRowIndent() -> KeyButton {
    let indent = KeyButton(type: .custom)
    indent.translatesAutoresizingMaskIntoConstraints = false
    indent.alpha = 0
    indent.isUserInteractionEnabled = false
    indent.isAccessibilityElement = false
    return indent
  }

  /// One iPad row across the full width: function keys sized in widths of the row's own keys,
  /// the keys sharing what is left equally.
  private func addTabletRow(
    leading: [(key: KeyButton, keys: CGFloat)] = [],
    keys: UIStackView,
    trailing: [(key: KeyButton, keys: CGFloat)] = [],
    to stack: UIStackView
  ) {
    guard let unitKey = keys.arrangedSubviews.first else { return }
    let rowContainer = addRowContainer(to: stack)
    let row = UIStackView(arrangedSubviews: leading.map { $0.key } + [keys] + trailing.map { $0.key })
    row.axis = .horizontal
    row.spacing = metrics.keyGap
    row.distribution = .fill
    row.translatesAutoresizingMaskIntoConstraints = false
    rowContainer.addSubview(row)
    var constraints = [
      row.leadingAnchor.constraint(equalTo: rowContainer.leadingAnchor),
      row.trailingAnchor.constraint(equalTo: rowContainer.trailingAnchor),
      row.topAnchor.constraint(equalTo: rowContainer.topAnchor),
      row.bottomAnchor.constraint(equalTo: rowContainer.bottomAnchor),
    ]
    for item in leading + trailing {
      constraints.append(item.key.widthAnchor.constraint(equalTo: unitKey.widthAnchor, multiplier: item.keys))
    }
    NSLayoutConstraint.activate(constraints)
  }

  /// .?123 · globe (or emoji) · language · space · field keys · .?123 · hide keyboard.
  private func addTabletBottomRow(to stack: UIStackView) {
    let row = UIStackView()
    row.axis = .horizontal
    row.spacing = metrics.keyGap
    row.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(row)
    constrainRowHeight(row)

    let leftMode = makeModeKey()
    let rightMode = makeModeKey()
    modeButton = leftMode
    tabletExtraModeButtons = [rightMode]

    let globeButton = makeNextKeyboardButton()
    // iPads without a Home button take no globe key; the emoji key (G45) shows there instead.
    let emojiButton = makeKeyButton(display: nil, imageSystemName: "face.smiling", role: .utility)
    emojiButton.accessibilityLabel = "Emoji"
    emojiButton.isHidden = needsInputModeSwitchKey
    emojiButton.addTarget(self, action: #selector(handleEmojiKeyTapped), for: .touchUpInside)
    self.emojiButton = emojiButton

    // G58: the language key, left of the space bar, as on the phone.
    let languageButton = makeLanguageKey()
    let spaceButton = makeSpaceKey()
    self.spaceButton = spaceButton
    // G59: Uzbek's comma, right of the space bar, as on the phone.
    let commaButton = makeCommaKey()
    let shortcuts = makeShortcutKeys()
    shortcutButtons = shortcuts

    let hideKey = makeKeyButton(display: nil, imageSystemName: "keyboard.chevron.compact.down", role: .utility)
    hideKey.accessibilityLabel = "Klaviaturani yopish"
    hideKey.addTarget(self, action: #selector(handleHideKeyboardTapped), for: .touchUpInside)

    ([leftMode, globeButton, emojiButton, languageButton, spaceButton, commaButton] + shortcuts + [rightMode, hideKey])
      .forEach(row.addArrangedSubview)

    let hideable = UILayoutPriority.required - 1
    bottomRowConstraints = BottomRowConstraints(
      halfWidth: shortcuts.map { widthOfKeys($0, keys: Self.tabletBottomGlobeKeys, priority: hideable) },
      letterWidth: shortcuts.map { widthOfKeys($0, keys: Self.tabletBottomGlobeKeys, priority: hideable) },
      sharedWidth: shortcuts.dropFirst().map {
        let constraint = $0.widthAnchor.constraint(equalTo: shortcuts[0].widthAnchor)
        constraint.priority = hideable
        return constraint
      },
      returnWidth: nil,
      narrowReturnWidth: nil
    )
    NSLayoutConstraint.activate([
      widthOfKeys(leftMode, keys: Self.tabletBottomSideKeys),
      widthOfKeys(rightMode, keys: Self.tabletBottomSideKeys),
      widthOfKeys(hideKey, keys: Self.tabletBottomSideKeys),
      widthOfKeys(globeButton, keys: Self.tabletBottomGlobeKeys, priority: hideable),
      widthOfKeys(emojiButton, keys: Self.tabletBottomGlobeKeys, priority: hideable),
      widthOfKeys(languageButton, keys: Self.tabletBottomGlobeKeys, priority: hideable),
      widthOfKeys(commaButton, keys: Self.tabletBottomGlobeKeys, priority: hideable),
    ])
  }

  @objc private func handleHideKeyboardTapped() {
    playKeyClick()
    dismissKeyboard()
  }

  private func makeModeKey() -> KeyButton {
    let button = makeKeyButton(display: layoutMode == .letters ? "123" : "ABC", role: .utility)
    button.addTarget(self, action: #selector(handleModeKeyTapped), for: .touchUpInside)
    return button
  }

  private func makeSpaceKey() -> KeyButton {
    let spaceButton = makeKeyButton(display: nil, role: .utility)
    spaceButton.addTarget(self, action: #selector(handleSpaceTapped), for: .touchUpInside)
    spaceButton.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
    spaceButton.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
    // Gapla (G58): the space bar names the keyboard's language, as Apple's does with several keyboards, at the size of
    // the 123 pages' "123" key and on the "123" label's baseline.
    spaceButton.setTitle(keyboardLanguage.name, for: .normal)
    spaceButton.titleLabel?.font = KeyFont.pageLabel
    spaceButton.titleBaselineFromCenter = metrics.keycaps.label123.baseline
    // G60: «Русский QWERTY» is longer than the space bar left beside the language and comma keys; it shrinks to fit.
    spaceButton.titleLabel?.adjustsFontSizeToFitWidth = true
    spaceButton.titleLabel?.minimumScaleFactor = 0.6
    spaceButton.accessibilityLabel = "bo'sh joy"
    spaceButton.accessibilityValue = keyboardLanguage.name
    let spaceCursorPress = UILongPressGestureRecognizer(
      target: self,
      action: #selector(handleSpaceLongPress(_:))
    )
    spaceCursorPress.minimumPressDuration = 0.35
    spaceCursorPress.allowableMovement = .greatestFiniteMagnitude
    spaceButton.addGestureRecognizer(spaceCursorPress)
    return spaceButton
  }

  /// Gapla (G59, owner 2026-11-14: [so'zlari: bilim/gapla-goyalar-royxati.md]): Uzbek's comma, right of the space bar
  /// and left of return, as on the Gapla Android keyboard. A tap types a comma, a held press a full stop (G39), as the
  /// letters-page comma did. refreshCommaKey shows it on the Uzbek letters page of ordinary fields only.
  private func makeCommaKey() -> KeyButton {
    let button = makeKeyButton(display: ",", output: ",", role: .character)
    button.accessibilityLabel = "vergul"
    button.isHidden = true
    let commaPress = UILongPressGestureRecognizer(target: self, action: #selector(handleCommaLongPress(_:)))
    commaPress.minimumPressDuration = 0.4
    button.addGestureRecognizer(commaPress)
    button.addTarget(self, action: #selector(handleCharacterKeyTapped(_:)), for: .touchUpInside)
    button.addTarget(self, action: #selector(handleCharacterKeyDown(_:)), for: .touchDown)
    button.addTarget(
      self,
      action: #selector(handleCharacterKeyReleased(_:)),
      for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
    )
    commaButton = button
    return button
  }

  /// The three field keys refreshBottomRow fills (URL ". / .com", email "@ .", …).
  private func makeShortcutKeys() -> [KeyButton] {
    (0..<3).map { _ in
      let button = makeKeyButton(display: nil, role: .utility)
      button.addTarget(self, action: #selector(handleShortcutTapped(_:)), for: .touchUpInside)
      return button
    }
  }

  /// 123 · globe or emoji · language (G58) · space · field keys · return. Widths follow Apple's: 123 ends under Z
  /// and return starts under M; the field keys and return change with the keyboard type.
  private func addMainBottomRow(to stack: UIStackView) {
    let row = UIStackView()
    row.axis = .horizontal
    row.spacing = metrics.keyGap
    row.translatesAutoresizingMaskIntoConstraints = false
    stack.addArrangedSubview(row)
    constrainRowHeight(row)

    let modeButton = makeModeKey()
    self.modeButton = modeButton

    // After 123, as Apple's; with it showing, 123 and the globe share one 123 width.
    let globeButton = makeNextKeyboardButton()

    // Gapla (G45): Apple's Face ID phones show 123 · emoji · space · return; the emoji key
    // takes the globe's half of the 123 width. Home-button phones keep the globe there.
    let emojiButton = makeKeyButton(display: nil, imageSystemName: "face.smiling", role: .utility)
    emojiButton.accessibilityLabel = "Emoji"
    emojiButton.isHidden = needsInputModeSwitchKey
    emojiButton.addTarget(self, action: #selector(handleEmojiKeyTapped), for: .touchUpInside)
    self.emojiButton = emojiButton

    // Gapla (G58): the language key, between the emoji (or globe) key and the space bar, which gives up its width.
    let languageButton = makeLanguageKey()

    let spaceButton = makeSpaceKey()
    self.spaceButton = spaceButton

    // G59: Uzbek's comma, right of the space bar, which gives up its width.
    let commaButton = makeCommaKey()

    let shortcuts = makeShortcutKeys()
    shortcutButtons = shortcuts

    let returnButton = makeReturnKey()
    self.returnButton = returnButton

    ([modeButton, globeButton, emojiButton, languageButton, spaceButton, commaButton] + shortcuts + [returnButton])
      .forEach(row.addArrangedSubview)

    // Keys that can hide in the stack get 999 widths, so the stack's own zero-width
    // hiding constraint wins without a conflict.
    let hideable = UILayoutPriority.required - 1
    let halfBottomKey = { (view: UIView) in
      self.widthOfAppleKeys(
        view, keys: self.metrics.bottomKeys / 2, gaps: (self.metrics.bottomGaps - 1) / 2, priority: hideable
      )
    }
    bottomRowConstraints = BottomRowConstraints(
      halfWidth: shortcuts.map(halfBottomKey),
      letterWidth: shortcuts.map { widthOfAppleKeys($0, keys: metrics.searchShortcutKeys, priority: hideable) },
      sharedWidth: shortcuts.dropFirst().map {
        let constraint = $0.widthAnchor.constraint(equalTo: shortcuts[0].widthAnchor)
        constraint.priority = hideable
        return constraint
      },
      returnWidth: widthOfAppleKeys(
        returnButton, keys: metrics.bottomKeys, gaps: metrics.bottomGaps, priority: hideable
      ),
      narrowReturnWidth: widthOfAppleKeys(
        returnButton, keys: metrics.narrowReturnKeys, gaps: metrics.narrowReturnGaps, priority: hideable
      )
    )
    // 123 always shares its width now: with the globe on home-button phones, with the emoji
    // key elsewhere (G45). G58: the language key is as wide as each half. G59: so is the comma.
    NSLayoutConstraint.activate([
      halfBottomKey(modeButton),
      halfBottomKey(globeButton),
      halfBottomKey(emojiButton),
      halfBottomKey(languageButton),
      halfBottomKey(commaButton),
    ])
  }

  // MARK: Gapla keyboard languages (G58)

  /// The language key: the language's short name, as text — on Home-button phones the system's globe key sits beside
  /// it, so it is never a globe. A tap steps to the next language on in the app; held, its menu lists them, as the
  /// toolbar's mode menu does. Hidden when the app has only Uzbek on.
  private func makeLanguageKey() -> KeyButton {
    let button = makeKeyButton(display: keyboardLanguage.keyLabel, role: .utility)
    button.accessibilityLabel = "Klaviatura tili"
    button.accessibilityValue = keyboardLanguage.name
    button.isHidden = enabledLanguages.count < 2
    button.addTarget(self, action: #selector(handleLanguageKeyTapped), for: .touchUpInside)
    let actions: [UIAction] = enabledLanguages.map { language in
      UIAction(title: language.name, state: language == keyboardLanguage ? .on : .off) { [weak self] _ in
        self?.selectKeyboardLanguage(language)
      }
    }
    button.menu = UIMenu(title: "Klaviatura tili", children: actions)
    button.showsMenuAsPrimaryAction = false
    return button
  }

  @objc private func handleLanguageKeyTapped() {
    playKeyClick()
    guard enabledLanguages.count > 1, let index = enabledLanguages.firstIndex(of: keyboardLanguage) else { return }
    selectKeyboardLanguage(enabledLanguages[(index + 1) % enabledLanguages.count])
  }

  /// The owner picked `language` on the language key. It is remembered for the next opening. The keys are rebuilt after
  /// this event, as the rebuild replaces the key that sent it.
  private func selectKeyboardLanguage(_ language: KeyboardLanguage) {
    guard language != keyboardLanguage, enabledLanguages.contains(language) else { return }
    DispatchQueue.main.async { [weak self] in self?.switchKeyboardLanguage(to: language) }
  }

  private func switchKeyboardLanguage(to language: KeyboardLanguage) {
    guard language != keyboardLanguage else { return }
    keyboardLanguage = language
    Self.rememberedKeyboardLanguage = language
    primaryLanguage = language.primaryLanguage
    applyKeyboardLanguageChange()
    startTavsiyaIfOn()
  }

  /// Reads the languages the app has on (App Group) and the one last used (this keyboard's own defaults). A language
  /// the app has since turned off falls back to Uzbek. True when either changed since the keys were last built.
  @discardableResult
  private func loadKeyboardLanguages() -> Bool {
    let enabled = KeyboardHandoffProvider.shared.keyboardLanguages()
    var language = Self.rememberedKeyboardLanguage
    if !enabled.contains(language) {
      language = .uz
      Self.rememberedKeyboardLanguage = .uz
    }
    let changed = enabled != enabledLanguages || language != keyboardLanguage
    enabledLanguages = enabled
    keyboardLanguage = language
    primaryLanguage = language.primaryLanguage
    return changed
  }

  /// The keys follow a new keyboard language: back to the letters page, its rows, its name on the space bar and the
  /// language key's list. The word being typed no longer counts toward the suggestions.
  private func applyKeyboardLanguageChange() {
    tavsiyaTypedWord = ""
    tavsiyaLastCounted = nil
    layoutMode = .letters
    typedOnSymbolPage = false
    isCapsLocked = false
    isShiftEnabled = shouldAutoCapitalize()
    if didBuildKeyboard {
      rebuildKeyboard()
    } else {
      refreshTavsiya()
    }
    logMemory("til-\(keyboardLanguage.rawValue)")
  }

  /// The language last picked on the language key, kept in the keyboard's own defaults (no Full Access needed).
  private static let keyboardLanguageKey = "gapla_klaviatura_til"
  private static var rememberedKeyboardLanguage: KeyboardLanguage {
    get {
      UserDefaults.standard.string(forKey: keyboardLanguageKey).flatMap(KeyboardLanguage.init(rawValue:)) ?? .uz
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: keyboardLanguageKey)
    }
  }

  private func makeNextKeyboardButton() -> KeyButton {
    let button = makeKeyButton(display: nil, imageSystemName: "globe", role: .utility)
    button.accessibilityLabel = "Keyingi klaviatura"
    button.isHidden = !needsInputModeSwitchKey
    button.addTarget(self, action: #selector(handleNextKeyboardTapped), for: .touchUpInside)
    button.addTarget(
      self,
      action: #selector(handleInputModeListButton(_:forEvent:)),
      for: .allTouchEvents
    )
    return button
  }

  private func makeKeyButton(
    display: String?,
    output: String? = nil,
    imageSystemName: String? = nil,
    role: KeyRole
  ) -> KeyButton {
    let button = KeyButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.output = output
    // Each key's target reaches across the gaps, Apple's half-key indent on the A row and
    // the keyboard's padding, so no gap or pixel-rounding sliver is dead;
    // KeyboardRowsStack gives every touch to the nearest key.
    button.hitTestOutsets = keyTouchOutsets
    button.layer.cornerRadius = metrics.keyCornerRadius
    button.layer.cornerCurve = .continuous

    // One colour for every key, as Apple's; no shadow. Character keys show a pop-up
    // instead of a pressed colour.
    button.normalBackground = Palette.keyBackground
    button.pressedBackground = role == .character ? nil : Palette.keyPressedBackground
    button.setTitleColor(Palette.keyText, for: .normal)

    if let display {
      button.setTitle(display, for: .normal)
      button.titleLabel?.font = role == .character ? metrics.keycaps.character(display) : metrics.keycaps.label123.font
      button.titleBaselineFromCenter =
        role == .character ? KeyFont.baseline(for: display) : metrics.keycaps.label123.baseline
    }

    if let imageSystemName {
      let image = UIImage(systemName: imageSystemName)?
        .withRenderingMode(.alwaysTemplate)
      button.setImage(image, for: .normal)
      button.tintColor = Palette.keyText
      button.imageView?.contentMode = .scaleAspectFit
      button.setPreferredSymbolConfiguration(KeyFont.glyph, forImageIn: .normal)
    }

    return button
  }

  private func refreshShiftState() {
    guard layoutMode == .letters else { return }

    for button in characterButtons {
      guard let output = button.output else { continue }
      // G58: capitals in the keyboard's language (Turkish i → İ).
      button.setTitle(isShiftEnabled ? keyboardLanguage.uppercased(output) : output, for: .normal)
      button.titleLabel?.font = isShiftEnabled ? metrics.keycaps.uppercase : metrics.keycaps.lowercase
      button.titleBaselineFromCenter =
        KeyFont.characterBaseline + (isShiftEnabled ? 0 : metrics.keycaps.lowercaseBaselineShift)
    }

    // Apple changes only the glyph; the key keeps its colour.
    let shiftImage = isCapsLocked
      ? CachedImages.capslockFill
      : (isShiftEnabled ? CachedImages.shiftFill : CachedImages.shift)
    // G46: the iPad has a second shift at row 3's right end.
    for shift in [shiftButton].compactMap({ $0 }) + tabletExtraShiftButtons {
      shift.setImage(shiftImage, for: .normal)
      shift.imageOffsetY = isCapsLocked ? KeyFont.capsLockGlyphOffset : metrics.keycaps.edgeGlyphOffset
      shift.accessibilityLabel = isCapsLocked ? "doimiy bosh harf" : "bosh harf"
      shift.accessibilityTraits = isShiftEnabled ? [.button, .selected] : .button
    }
    // Gapla (G41): the next-word suggestions follow shift's capitals.
    refreshTavsiya()
  }

  private func syncShiftWithContextIfNeeded() {
    guard layoutMode == .letters && !isCapsLocked else { return }
    // A field with text that reports none around the cursor hides it: leave shift as it is
    // rather than capitalising mid-word.
    let proxy = textDocumentProxy
    if proxy.documentContextBeforeInput == nil && proxy.documentContextAfterInput == nil
      && (proxy.hasText || fieldHidesItsText)
    {
      return
    }

    let shouldEnableShift = shouldAutoCapitalize()
    if shouldEnableShift != isShiftEnabled {
      isShiftEnabled = shouldEnableShift
      refreshShiftState()
    }
  }

  /// Follows the field's autocapitalization type, as Apple's keyboard does (URL and email
  /// fields start lowercase).
  private func shouldAutoCapitalize() -> Bool {
    fieldCapitalization.capitalizesNext(after: textDocumentProxy.documentContextBeforeInput)
  }

  private var fieldCapitalization: AutoCapitalization {
    switch textDocumentProxy.autocapitalizationType ?? .sentences {
    case .none: return .none
    case .words: return .words
    case .allCharacters: return .allCharacters
    default: return .sentences
    }
  }

  private func startDeleteRepeating() {
    stopDeleteRepeating()
    deleteRepeatCount = 0
    performRepeatingDelete()
  }

  private func stopDeleteRepeating() {
    deleteRepeatTimer?.invalidate()
    deleteRepeatTimer = nil
    deleteRepeatCount = 0
  }

  private func performRepeatingDelete() {
    playKeyClick()
    if isTranslatorOpen {
      deleteFromTranslator(word: deleteRepeatCount >= 24 && deleteRepeatCount % 6 == 0)
    } else if deleteRepeatCount >= 24 && deleteRepeatCount % 6 == 0 {
      deletePreviousWordChunk()
    } else {
      textDocumentProxy.deleteBackward()
    }
    deleteRepeatCount += 1
    scheduleNextDeleteRepeat()
  }

  private func scheduleNextDeleteRepeat() {
    let interval: TimeInterval
    if deleteRepeatCount < 6 {
      interval = 0.09
    } else if deleteRepeatCount < 18 {
      interval = 0.06
    } else {
      interval = 0.035
    }

    deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) {
      [weak self] _ in
      self?.performRepeatingDelete()
    }
    if let deleteRepeatTimer {
      RunLoop.main.add(deleteRepeatTimer, forMode: .common)
    }
  }

  private func deletePreviousWordChunk() {
    guard let context = textDocumentProxy.documentContextBeforeInput, !context.isEmpty else {
      textDocumentProxy.deleteBackward()
      return
    }

    let suffix = Array(context.reversed())
    var deleteCount = 0
    var hasSeenWordCharacter = false

    for character in suffix {
      if character.isWhitespace || character.isPunctuation {
        if hasSeenWordCharacter { break }
      } else {
        hasSeenWordCharacter = true
      }
      deleteCount += 1
    }

    for _ in 0..<max(1, deleteCount) {
      textDocumentProxy.deleteBackward()
    }
  }

  private func startRecordingPoll() {
    stopRecordingPoll()
    // G57 (analysis finding 6): with nothing recording, starting or awaited, only every fourth
    // tick (~0.5 s) reads the App Group — it then only watches for a recording the app started
    // itself. Starting and recording keep every 0.12 s tick (the start checks count ticks).
    var idleTicks = 0
    recordingPollTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
      guard let self else { return }
      if self.isRecordingPollIdle {
        idleTicks += 1
        if idleTicks < 4 { return }
      }
      idleTicks = 0
      self.pollRecordingState()
    }
    if let recordingPollTimer {
      RunLoop.main.add(recordingPollTimer, forMode: .common)
    }
  }

  private func stopRecordingPoll() {
    recordingPollTimer?.invalidate()
    recordingPollTimer = nil
  }

  private var isRecordingPollIdle: Bool {
    !isDarwinStartPending && !isRemoteRecordingActive && !recordingOrb.isShowing && waitForTranscriptTimer == nil
  }

  private func startHandoffObservers() {
    guard !isObservingHandoffNotifications else { return }
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = Unmanaged.passUnretained(self).toOpaque()
    let callback: CFNotificationCallback = { _, observer, _, _, _ in
      guard let observer else { return }
      let controller = Unmanaged<KeyboardViewController>.fromOpaque(observer).takeUnretainedValue()
      DispatchQueue.main.async {
        controller.handleHandoffNotification()
      }
    }

    CFNotificationCenterAddObserver(
      center,
      observer,
      callback,
      Self.darwinStatusNotificationName as CFString,
      nil,
      .deliverImmediately
    )
    CFNotificationCenterAddObserver(
      center,
      observer,
      callback,
      Self.darwinTranscriptReadyNotificationName as CFString,
      nil,
      .deliverImmediately
    )
    isObservingHandoffNotifications = true
  }

  private func stopHandoffObservers() {
    guard isObservingHandoffNotifications else { return }
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = Unmanaged.passUnretained(self).toOpaque()
    CFNotificationCenterRemoveObserver(
      center,
      observer,
      CFNotificationName(Self.darwinStatusNotificationName as CFString),
      nil
    )
    CFNotificationCenterRemoveObserver(
      center,
      observer,
      CFNotificationName(Self.darwinTranscriptReadyNotificationName as CFString),
      nil
    )
    isObservingHandoffNotifications = false
  }

  private func handleHandoffNotification() {
    // Once the review card is up, ignore status churn — the user is deciding
    // whether to insert; only their tap should dismiss it.
    if isAgentReviewShown { return }
    if consumePendingTranscriptIfAvailable(trigger: "darwinNotification") {
      waitForTranscriptTimer?.invalidate()
      waitForTranscriptTimer = nil
      return
    }
    applySharedHandoffStatus()
  }

  private func applySharedHandoffStatus() {
    let provider = KeyboardHandoffProvider.shared
    guard let status = provider.transcriptionStatus() else { return }
    switch status {
    case "transcribing", "cleaning":
      // The app flips the shared status to "transcribing" whenever it
      // finalizes a recording — including one the user just cancelled. Don't
      // let that Darwin echo resurrect the pill after cancel reset the button.
      if let cancelled = cancelledProcessingJobId,
         provider.currentRecordingJobId() == cancelled {
        logRecordMarker("handoffStatus.ignoredCancelledJob", extra: "job=\(cancelled)")
        return
      }
      showLongRunningRecordState(title: status == "cleaning" ? "Tozalanmoqda" : "Ishlanmoqda")
      // A Darwin-driven pill needs the transcript poll running — it is the
      // pill's only exit path (transcript, failure status, or timeout).
      if waitForTranscriptTimer == nil {
        waitForTranscript()
      }
    case "ready":
      showLongRunningRecordState(title: "Joylanmoqda")
    case "idle":
      // Cancel/discard resets the shared status to idle. Clear a waiting pill
      // instead of letting it spin against a job that no longer exists.
      if !isRemoteRecordingActive, !isDarwinStartPending, waitForTranscriptTimer != nil {
        logRecordMarker("handoffStatus.idleReset")
        waitForTranscriptTimer?.invalidate()
        waitForTranscriptTimer = nil
        endRecordingOrb(success: false)
        refreshRecordButton()
      }
    case "no_speech":
      surfaceHandoffFailure(title: "Gap eshitilmadi")
    case "setup_required":
      surfaceHandoffFailure(title: "Ilovada sozlang")
    case "error":
      surfaceHandoffFailure(title: "Qayta urining")
    case "agent_generating":
      // The Darwin notification for agent_generating can arrive before our own
      // exitRecordingMode has entered the state (or after returning from a
      // handoff). Show the "Writing" pill and start polling if we aren't already.
      if !isAgentGenerating {
        enterAgentGenerating()
      }
    case "agent_ready":
      // Respect an in-flight regenerate's freshness gate so a stale pre-action
      // result delivered on this Darwin poke can't close the action early, and
      // drop a result for a cancelled/timed-out generation the app raced to
      // finish (it would otherwise pop the card seconds after the user cancelled).
      if let result = KeyboardHandoffProvider.shared.readAgentResult() {
        if isAgentResultRejected(result) {
          logRecordMarker("applySharedHandoffStatus.rejected", extra: "job=\(result.jobId)")
          KeyboardHandoffProvider.shared.clearAgentResult()
          KeyboardHandoffProvider.shared.clearTranscriptionStatus()
        } else if agentResultSatisfiesAction(result) {
          handleAgentReady(result)
        }
      }
    case "agent_error":
      handleAgentError(detail: KeyboardHandoffProvider.shared.transcriptionError())
    default:
      break
    }
  }

  /// Terminal failure: stop waiting for a transcript, clear the shared status
  /// so it can't resurface as stale state later, and show the issue pill. Also
  /// tears down an in-flight agent wait: a silent agent recording writes
  /// `no_speech` (not `agent_error`), which routes here — without this the agent
  /// poll would keep ticking for ~75s and re-flash a spurious "Try again". A
  /// mid-action follow-up keeps its retained card (existing versions stay
  /// insertable) with a note, matching the agent_error/cancel behaviour.
  private func surfaceHandoffFailure(title: String) {
    waitForTranscriptTimer?.invalidate()
    waitForTranscriptTimer = nil
    if isAgentGenerating {
      stopWaitingForAgentResult()
      isAgentGenerating = false
      agentActionMinUpdatedAtMs = nil
      processingCancelButton.isHidden = true
      KeyboardHandoffProvider.shared.clearAgentRequest()
      KeyboardHandoffProvider.shared.clearTranscriptionStatus()
      if isAgentActionInFlight, !agentReviewVersions.isEmpty {
        isAgentActionInFlight = false
        restoreAgentReviewCard()
        flashAgentReviewNote(title)
        return
      }
      isAgentActionInFlight = false
      showIssueState(title: title)
      return
    }
    KeyboardHandoffProvider.shared.clearTranscriptionStatus()
    showIssueState(title: title)
  }

  /// When the keyboard reappears while the app is still working (the user
  /// switched fields or apps mid-transcription) or shortly after a failure it
  /// never saw, restore that state instead of silently resetting to idle.
  /// Returns false when there's nothing fresh to resume.
  private func resumeFreshHandoffState() -> Bool {
    let provider = KeyboardHandoffProvider.shared
    guard let status = provider.transcriptionStatus(),
          let ageMs = provider.transcriptionStatusAgeMs() else { return false }
    switch status {
    case "transcribing", "cleaning":
      guard ageMs < 120_000 else { return false }
      isDarwinStartPending = false
      darwinStartPendingTicks = 0
      darwinStartActiveTicks = 0
      didRequestStopForCurrentSession = false
      logRecordMarker("viewDidAppear.resumedStatus", extra: "status=\(status) ageMs=\(ageMs)")
      showLongRunningRecordState(title: status == "cleaning" ? "Tozalanmoqda" : "Ishlanmoqda")
      waitForTranscript()
      return true
    case "error":
      guard ageMs < 15_000 else { return false }
      logRecordMarker("viewDidAppear.resumedStatus", extra: "status=error ageMs=\(ageMs)")
      surfaceHandoffFailure(title: "Qayta urining")
      return true
    case "setup_required":
      guard ageMs < 15_000 else { return false }
      logRecordMarker("viewDidAppear.resumedStatus", extra: "status=setup_required ageMs=\(ageMs)")
      surfaceHandoffFailure(title: "Ilovada sozlang")
      return true
    case "no_speech":
      guard ageMs < 15_000 else { return false }
      logRecordMarker("viewDidAppear.resumedStatus", extra: "status=no_speech ageMs=\(ageMs)")
      surfaceHandoffFailure(title: "Gap eshitilmadi")
      return true
    case "agent_generating":
      // The app is still transcribing/generating — resume the "Writing" state and
      // its poll (which owns the app-death and timeout fallbacks).
      guard ageMs < 120_000 else { return false }
      logRecordMarker("viewDidAppear.resumedStatus", extra: "status=agent_generating ageMs=\(ageMs)")
      enterAgentGenerating()
      return true
    case "agent_ready":
      // Re-open into the review card only while the result is fresh (<10 min);
      // anything older — or a result for a generation cancelled/timed-out this
      // session — is discarded so a stale reply can't ambush a later field.
      if let result = provider.readAgentResult(),
         !isAgentResultRejected(result),
         let updatedAtMs = result.updatedAtMs,
         Date().timeIntervalSince1970 * 1000 - updatedAtMs < 600_000 {
        logRecordMarker("viewDidAppear.resumedStatus", extra: "status=agent_ready")
        showAgentReviewCard(result)
        return true
      }
      provider.clearAgentResult()
      provider.clearTranscriptionStatus()
      return false
    case "agent_error":
      guard ageMs < 15_000 else { return false }
      logRecordMarker("viewDidAppear.resumedStatus", extra: "status=agent_error ageMs=\(ageMs)")
      handleAgentError(detail: provider.transcriptionError())
      return true
    default:
      return false
    }
  }

  private func logRecordMarker(_ marker: String, extra: String = "") {
    let sharedState = KeyboardHandoffProvider.shared.recordingStateSnapshot()
    let suffix = extra.isEmpty ? "" : " \(extra)"
    KeyboardLog.echo(
      "MARKER \(marker) localActive=\(isRemoteRecordingActive) pending=\(isDarwinStartPending) pendingTicks=\(darwinStartPendingTicks) activeTicks=\(darwinStartActiveTicks) requestedStop=\(didRequestStopForCurrentSession) sharedActive=\(sharedState.active) sharedReady=\(sharedState.ready) sharedWarm=\(sharedState.warmMic) stopReq=\(sharedState.stopRequested)\(suffix)"
    )
  }

  private func refreshRecordButton() {
    issueResetTimer?.invalidate()
    issueResetTimer = nil

    isDarwinStartPending = false
    darwinStartPendingTicks = 0
    darwinStartActiveTicks = 0
    didRequestStopForCurrentSession = false
    isAgentRecordingActive = false
    agentRecordingHeaderText = nil
    agentRecordingHint = nil

    recordButton.removeTarget(self, action: #selector(handleDarwinRecordTapped), for: .touchUpInside)
    recordButton.removeTarget(self, action: #selector(handleStopRecordingTapped), for: .touchUpInside)
    recordButton.removeTarget(
      self, action: #selector(handleFullAccessPillTapped), for: .touchUpInside
    )

    // Full Access is off: every UserDefaults(suiteName:) read no-ops, so
    // dictation is dead while typing keeps working — the keyboard looks healthy
    // and the pill silently does nothing. Convert the dead control into the fix.
    // The extension cannot report this to the app (reporting needs the shared
    // container the loss takes away), so the message has to be drawn here.
    //
    // Persistent, unlike showIssueState / showTransientRecordState: no timer
    // reverts it. The pill cannot link anywhere — an extension without Full
    // Access cannot open any URL — so it opens the explanatory panel instead,
    // which is local UI and therefore the one thing that still works. This must
    // precede the recordsInPlace computation — hostIsOwnApp comes from bundle
    // detection, not the App Group, so it can be true here and would otherwise
    // offer "Tap to speak" into a dead recorder.
    guard hasFullAccess else {
      dictationLinkHosting?.view.isUserInteractionEnabled = false
      applyRecordButtonStyle(
        title: "To'liq kirishni yoqing",
        systemImage: "exclamationmark.triangle.fill",
        solidBackground: Palette.issue,
        foreground: Palette.issueInk
      )
      recordButton.addTarget(
        self, action: #selector(handleFullAccessPillTapped), for: .touchUpInside
      )
      // Unanimated before the window exists (viewDidLoad path): the panel should
      // be the first frame, not a flash of keys that then fade.
      if !didDismissFullAccessPanel {
        showFullAccessPanel(animated: view.window != nil)
      }
      resetVoiceMeterBars()
      // Neither control can reach the App Group either; refreshToneButton is
      // not part of the normal refresh path, so call it explicitly.
      refreshToneButton()
      refreshAgentButton()
      logRecordMarker("refreshRecordButton.noFullAccess")
      return
    }
    // Full Access is back (iOS relaunches the extension when it's granted, but
    // belt-and-braces for an in-place flip): the panel has nothing to say.
    hideFullAccessPanel(animated: false)

    // Inside OpenWhispr itself, tapping records in place (the app's URL handler
    // detects the self-hosted case and starts recording without switching apps),
    // so show "Tap to speak" with a mic. Elsewhere, a tap hands off to the app,
    // so show "Activate" with the brand logo.
    let backgroundReady = KeyboardHandoffProvider.shared.isBackgroundSessionReady()
    // Bundle-id detection (hostIsOwnApp) misses often; the app's foreground
    // heartbeat is the reliable "we're inside OpenWhispr" signal. Either one
    // means a tap records in place instead of bouncing to the handoff screen.
    let containingAppForeground = KeyboardHandoffProvider.shared.isContainingAppForeground()
    let selfHosted = hostIsOwnApp || containingAppForeground
    let recordsInPlace = backgroundReady || selfHosted
    dictationLinkHosting?.view.isUserInteractionEnabled = !recordsInPlace

    if recordsInPlace {
      recordButton.addTarget(self, action: #selector(handleDarwinRecordTapped), for: .touchUpInside)
    }

    if recordsInPlace {
      applyRecordButtonStyle(title: "Bosing va gapiring", image: CachedImages.brandLogoMark)
    } else {
      applyRecordButtonStyle(
        title: "Faollashtirish",
        image: CachedImages.brandLogoMark,
        gradient: [Palette.brandGradientStart, Palette.brandGradientEnd]
      )
    }
    // Gapla (G40, owner 2026-11-12 on the iPad: [so'zlari: bilim/gapla-goyalar-royxati.md]): the round microphone on the right is the one record button,
    // starting dictation both ways (handleTrailingMicTapped). The pill stays hidden while it would
    // only offer to record; it comes back for the states it reports — Full Access off, the
    // processing steps, «Gap eshitilmadi» and other issues (applyRecordButtonStyle shows it).
    recordButton.isHidden = true
    recordButtonBackground.isHidden = true
    resetVoiceMeterBars()
    refreshAgentButton()
    // Gapla (G41): the pill is gone, so the suggestions may come back.
    refreshTavsiya()
    logRecordMarker(
      "refreshRecordButton",
      extra:
        "backgroundReady=\(backgroundReady) hostIsOwnApp=\(hostIsOwnApp) containingAppForeground=\(containingAppForeground) selfHosted=\(selfHosted)"
    )
  }

  private func showTransientRecordState(
    title: String,
    systemImage: String,
    background: UIColor,
    duration: TimeInterval
  ) {
    issueResetTimer?.invalidate()
    issueResetTimer = nil
    dictationLinkHosting?.view.isUserInteractionEnabled = false
    applyRecordButtonStyle(
      title: title,
      systemImage: systemImage,
      solidBackground: background
    )
    issueResetTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) {
      [weak self] _ in
      self?.refreshRecordButton()
    }
    if let issueResetTimer {
      RunLoop.main.add(issueResetTimer, forMode: .common)
    }
  }

  private func showLongRunningRecordState(title: String) {
    issueResetTimer?.invalidate()
    issueResetTimer = nil
    dictationLinkHosting?.view.isUserInteractionEnabled = false
    // Cleanup and the other long-running states share the Gapla accent (G54), as the desktop app does.
    applyRecordButtonStyle(
      title: title,
      systemImage: "ellipsis",
      solidBackground: title == "Tozalanmoqda" ? Palette.cleanupAccent : Palette.accent
    )
    // "Inserting" is too brief and effect-less to cancel; only the waiting
    // states offer the X.
    processingCancelButton.isHidden = !(title == "Ishlanmoqda" || title == "Tozalanmoqda")
  }

  private func showIssueState(title: String) {
    KeyboardLog.ui.error("Issue state shown: \(title, privacy: .public)")
    KeyboardLog.echo("Issue state shown: \(title)")
    // Gapla (G47): on a failure the orb leaves and the error pill stays, as before.
    endRecordingOrb(success: false)
    dictationLinkHosting?.view.isUserInteractionEnabled = false
    applyRecordButtonStyle(
      title: title,
      systemImage: "exclamationmark",
      solidBackground: Palette.issue
    )

    issueResetTimer?.invalidate()
    // G52: 2 s (was 1.2) so a short note such as «Gap eshitilmadi» can be read before it goes.
    issueResetTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
      self?.refreshRecordButton()
    }
    if let issueResetTimer {
      RunLoop.main.add(issueResetTimer, forMode: .common)
    }
  }

  private func applyRecordButtonStyle(
    title: String,
    systemImage: String? = nil,
    image: UIImage? = nil,
    solidBackground: UIColor? = nil,
    gradient: [UIColor]? = nil,
    // Tints title and symbol together via baseForegroundColor. Defaults to
    // white so every existing call site is unchanged; only the persistent
    // Full Access state needs dark ink for contrast on amber.
    foreground: UIColor = .white
  ) {
    // The "ellipsis" states (Processing/Starting/Stopping) use the animated dots
    // overlay instead of a static symbol; the image is then a transparent spacer
    // that reserves the dots' space in the layout.
    let useDots = systemImage == "ellipsis"
    // G40: every state drawn here is a report; the idle record offer hides the pill again
    // (refreshRecordButton).
    recordButton.isHidden = false
    recordButtonBackground.isHidden = false
    // Gapla (G41): a report in the pill (processing, an issue) takes the strip from the suggestions.
    refreshTavsiya()

    // Plain config so the button draws no background of its own — the pill
    // background view behind the content provides it.
    var config = UIButton.Configuration.plain()
    config.title = title
    if useDots {
      config.image = CachedImages.processingDotsSpacer
    } else if let image {
      config.image = image
    } else if let systemImage {
      config.image = UIImage(systemName: systemImage)
    }
    config.imagePadding = 7
    config.imagePlacement = .leading
    config.baseForegroundColor = foreground
    config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: Metrics.pillLeadingInset, bottom: 8, trailing: 18)
    config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var outgoing = incoming
      outgoing.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
      return outgoing
    }
    recordButton.configuration = config

    // "Activate" uses the brand gradient; transient/issue states pass a solid
    // colour; everything else (incl. "Tap to speak") uses the adaptive pill.
    let pillStyle: PillBackgroundView.Style
    if let gradient {
      pillStyle = .gradient(gradient)
    } else if let solidBackground {
      pillStyle = .solid(solidBackground)
    } else {
      pillStyle = .adaptive
    }
    recordButtonBackground.setStyle(pillStyle)

    // Run the animated dots only while an "ellipsis" state is showing.
    if useDots {
      processingDots.isHidden = false
      processingDots.startAnimating()
    } else {
      processingDots.stopAnimating()
      processingDots.isHidden = true
    }

    // Cancel is only valid mid-transcription; every other style hides it. The
    // cancellable states re-show it after this call (showLongRunningRecordState).
    processingCancelButton.isHidden = true

    recordButton.accessibilityLabel = title
    switch title {
    case "Faollashtirish":
      recordButton.accessibilityHint = "Diktovka uchun Gapla'ni ochadi"
    case "To'liq kirishni yoqing":
      recordButton.accessibilityHint = "To'liq kirishni qanday yoqishni ko'rsatadi"
    default:
      recordButton.accessibilityHint = "Diktovkani boshlaydi"
    }
  }

  @objc private func handleRecordButtonPress(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      setRecordButtonPressed(true)
    case .ended:
      setRecordButtonPressed(false)
      // In "Activate" mode the tap itself is handled by the SwiftUI link
      // overlay, which gives no callback. Stamp the tap in the App Group so
      // the app can recover the handoff when the deep link never reaches JS
      // (cold-launch getInitialURL races deliver null and the tap dies).
      if dictationLinkHosting?.view.isUserInteractionEnabled == true {
        KeyboardHandoffProvider.shared.markHandoffIntent()
      }
    case .cancelled, .failed:
      setRecordButtonPressed(false)
    default:
      break
    }
  }

  // Pressed state: the pill lights up and scales down slightly for a tactile feel.
  private func setRecordButtonPressed(_ pressed: Bool) {
    recordButtonBackground.setPressed(pressed)
    UIView.animate(
      withDuration: 0.09,
      delay: 0,
      options: [.allowUserInteraction, .beginFromCurrentState]
    ) {
      let transform = pressed ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
      self.recordButton.transform = transform
      self.recordButtonBackground.transform = transform
    }
  }

  @objc private func handleAgentButtonPress(_ gesture: UILongPressGestureRecognizer) {
    switch gesture.state {
    case .began:
      UIView.animate(withDuration: 0.09, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
        self.agentButton.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
      }
    case .ended:
      UIView.animate(withDuration: 0.09, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
        self.agentButton.transform = .identity
      }
      handleTrailingMicTapped()
    case .cancelled, .failed:
      UIView.animate(withDuration: 0.09, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
        self.agentButton.transform = .identity
      }
    default:
      break
    }
  }

  /// Gapla (G40): the trailing microphone starts dictation the same two ways as the pill —
  /// in place when the app's session is warm, otherwise its Link overlay opens the app (the
  /// URL is the dictation one; no voice-assistant request is written, so the app dictates).
  private func handleTrailingMicTapped() {
    guard hasFullAccess else { return }
    let provider = KeyboardHandoffProvider.shared
    let recordsInPlace = provider.isBackgroundSessionReady()
      || hostIsOwnApp
      || provider.isContainingAppForeground()
    if recordsInPlace {
      playKeyClick()
      handleDarwinRecordTapped()
    } else if agentLinkHosting?.view.isUserInteractionEnabled == true {
      provider.markHandoffIntent()
    }
  }

  /// Fired when the agent button is released. Captures the field selection (and,
  /// if opted in, the surrounding context), writes the one-shot compose request,
  /// then starts recording via the same two paths as the record button: an
  /// in-place requestStart when the background session is warm, else a deep-link
  /// handoff (the Link overlay opens the URL; here we only stamp intent).
  private func handleAgentButtonTapped() {
    guard !isDarwinStartPending, !isRemoteRecordingActive, !isAgentGenerating else { return }
    let provider = KeyboardHandoffProvider.shared
    guard provider.isAgentEnabled() else { return }

    // Not applicable ⇒ the voice assistant can't run: it needs an account or its own provider key.
    // Point at it, swallow the tap.
    guard provider.isAgentApplicable() else {
      playKeyClick()
      showTransientRecordState(
        title: "Hisobga kiring",
        systemImage: "lock.fill",
        background: Palette.issue,
        duration: 1.6
      )
      return
    }

    playKeyClick()

    // Capture from the live proxy before any handoff drops focus. selectedText is
    // usually nil outside our own app (degrade silently); context only on opt-in.
    let selectedText = textDocumentProxy.selectedText
    var contextBefore: String?
    var contextAfter: String?
    if provider.agentSharesContext() {
      contextBefore = textDocumentProxy.documentContextBeforeInput
      contextAfter = textDocumentProxy.documentContextAfterInput
    }
    provider.writeAgentComposeRequest(
      selectedText: selectedText,
      contextBefore: contextBefore,
      contextAfter: contextAfter
    )

    let recordsInPlace = provider.isBackgroundSessionReady()
      || hostIsOwnApp
      || provider.isContainingAppForeground()

    // When text is selected, cue the recording canvas with "Rewriting Selection"
    // so the user knows the instruction will rewrite that text. Degrade silently
    // when selectedText is nil (most third-party apps don't expose it).
    let selectionCaption: String? = (selectedText?.isEmpty == false) ? "Belgilangan matn qayta yoziladi" : nil
    agentRecordingHint = agentHint(from: Self.agentComposeHints)

    if recordsInPlace {
      isAgentRecordingActive = true
      logRecordMarker("handleAgentButtonTapped.inPlace")
      startAgentRecordingInPlace(caption: selectionCaption)
    } else {
      // The Link overlay opens the dictation URL; stamp intent so the app can
      // recover the handoff if the deep link races to null on cold launch. The
      // recording that follows becomes an agent job because the request is set.
      isAgentRecordingActive = true
      logRecordMarker("handleAgentButtonTapped.handoff")
      provider.markHandoffIntent()
    }
  }

  /// Starts an in-place agent recording. Mirrors handleDarwinRecordTapped's
  /// requestStart handshake and "Starting" pill; enterRecordingMode then swaps in
  /// the agent header because isAgentRecordingActive is set. `caption` overrides
  /// the recording-canvas header (a follow-up passes "Describe your changes").
  private func startAgentRecordingInPlace(caption: String? = nil) {
    agentRecordingHeaderText = caption
    recordButton.removeTarget(self, action: #selector(handleDarwinRecordTapped), for: .touchUpInside)
    recordButton.removeTarget(self, action: #selector(handleStopRecordingTapped), for: .touchUpInside)

    cancelledProcessingJobId = nil
    isRemoteRecordingActive = false
    didRequestStopForCurrentSession = false
    KeyboardHandoffProvider.shared.requestStart()
    isDarwinStartPending = true
    darwinStartPendingTicks = 0
    darwinStartActiveTicks = 0

    showTransientRecordState(
      title: "Boshlanmoqda",
      systemImage: "ellipsis",
      background: Palette.cleanupAccent,
      duration: 3.0
    )
  }

  // Allow the press gesture to coexist with the link overlay's own recogniser.
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool {
    true
  }

  private func formatTranscription(_ text: String) -> String {
    text
      .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func insertSmartText(_ text: String) {
    guard !text.isEmpty else { return }
    // G56: dictation while the translator is open fills its text.
    if isTranslatorOpen {
      appendToTranslator(text, spaced: true)
      return
    }
    // Gapla (G41): dictated text is not counted here — the server learns it itself.
    tavsiyaTypedWord = ""
    tavsiyaLastCounted = nil

    let context = textDocumentProxy.documentContextBeforeInput ?? ""
    let needsLeadingSpace =
      !context.isEmpty
      && !context.hasSuffix(" ")
      && !context.hasSuffix("\n")
      && !text.hasPrefix("\n")
      && !text.hasPrefix(",")
      && !text.hasPrefix(".")

    let insertion = needsLeadingSpace ? " \(text)" : text
    typeText(insertion)
    // Shift follows the text (it was synced before the text arrived).
    syncShiftWithContextIfNeeded()
    refreshAfterEdit()
  }

  @discardableResult
  private func consumePendingTranscriptIfAvailable(trigger: String) -> Bool {
    // A transcript that lands for a cancelled job (the app raced past its cancel
    // checkpoint) must be dropped, never inserted into the field.
    if let cancelledProcessingJobId,
       KeyboardHandoffProvider.shared.discardPendingTranscriptIfMatches(jobId: cancelledProcessingJobId) {
      logRecordMarker("consumePending.discardedCancelled", extra: "job=\(cancelledProcessingJobId)")
      self.cancelledProcessingJobId = nil
      return false
    }

    guard let pending = KeyboardHandoffProvider.shared.consumePendingTranscript() else {
      return false
    }

    let text = formatTranscription(pending)
    guard !text.isEmpty else {
      return false
    }

    KeyboardLog.transcription.info(
      "Inserted pending transcript from app. trigger=\(trigger, privacy: .public) chars=\(text.count, privacy: .public)"
    )
    KeyboardLog.echo("Inserted pending transcript from app. chars=\(text.count)")
    insertSmartText(text)
    KeyboardHandoffProvider.shared.gaplaVaqt(
      "matn-kiritildi",
      job: KeyboardHandoffProvider.lastConsumedJobId,
      extra: "belgi=\(text.count) yol=\(trigger)"
    )
    // Gapla (G47): the text is in; the orb plays done (the tick) and leaves.
    endRecordingOrb(success: true)
    showTransientRecordState(
      title: "Joylandi",
      systemImage: "checkmark",
      background: Palette.accent,
      duration: 1.1
    )
    // The keyboard stays up after inserting so the user can keep dictating or
    // editing; they dismiss it themselves when done.
    return true
  }

  private func pollRecordingState() {
    if isAgentReviewShown { return }
    let provider = KeyboardHandoffProvider.shared

    if isDarwinStartPending {
      darwinStartPendingTicks += 1
      if provider.isRecordingActive() {
        darwinStartActiveTicks += 1
        if darwinStartActiveTicks == 1 {
          logRecordMarker("poll.pendingActiveDetected")
        }
        if darwinStartActiveTicks < 2 {
          return
        }
        isDarwinStartPending = false
        darwinStartPendingTicks = 0
        darwinStartActiveTicks = 0
        isRemoteRecordingActive = true
        logRecordMarker("poll.pendingConfirmedActive")
        enterRecordingMode()
        return
      }
      darwinStartActiveTicks = 0
      // A dead app can't ack the start: after a force-quit the heartbeat
      // freezes and goes stale within seconds, and an interruption drops the
      // ready flag. Bail to the handoff fallback then, instead of stranding
      // the user on "Starting" for the full timeout.
      if darwinStartPendingTicks >= 4, !provider.isBackgroundSessionReady() {
        logRecordMarker("poll.pendingAbortNotReady", extra: "ticks=\(darwinStartPendingTicks)")
        handleDarwinStartFallback()
        return
      }
      if darwinStartPendingTicks >= 20 {
        logRecordMarker("poll.pendingTimeout")
        handleDarwinStartFallback()
        return
      }
      return
    }

    let active = provider.isRecordingActive()

    if active && !isRemoteRecordingActive {
      isRemoteRecordingActive = true
      // A recording we didn't start locally (handoff): recover whether it's an
      // agent job so the canvas and post-stop path match.
      if !isAgentRecordingActive {
        isAgentRecordingActive = provider.hasAgentJobForCurrentRecording()
      }
      logRecordMarker("poll.transitionToActive")
      enterRecordingMode()
    } else if !active && isRemoteRecordingActive {
      isRemoteRecordingActive = false
      if didRequestStopForCurrentSession {
        didRequestStopForCurrentSession = false
        logRecordMarker("poll.transitionToInactive.expected")
        exitRecordingMode()
      } else {
        logRecordMarker("poll.transitionToInactive.unexpected")
        if !consumePendingTranscriptIfAvailable(trigger: "unexpectedInactive") {
          showIssueState(title: "Yozish uzildi")
        }
      }
      return
    }
    // The orb reads the voice itself, every 40 ms (recordingOrb.levelSource).
  }

  private func enterRecordingMode() {
    issueResetTimer?.invalidate()
    issueResetTimer = nil
    // G57: the keys can come back while an earlier text is still awaited; a new recording
    // supersedes it, and that wait must not end the new recording's orb with its own failure.
    waitForTranscriptTimer?.invalidate()
    waitForTranscriptTimer = nil

    dictationLinkHosting?.view.isUserInteractionEnabled = false
    isDarwinStartPending = false
    darwinStartPendingTicks = 0
    darwinStartActiveTicks = 0
    didRequestStopForCurrentSession = false
    didRequestCancelForCurrentSession = false

    recordButton.removeTarget(self, action: #selector(handleDarwinRecordTapped), for: .touchUpInside)
    recordButton.removeTarget(self, action: #selector(handleStopRecordingTapped), for: .touchUpInside)

    showRecordingCanvas()
    logRecordMarker("enterRecordingMode")
  }

  private func exitRecordingMode() {
    isDarwinStartPending = false
    darwinStartPendingTicks = 0
    darwinStartActiveTicks = 0

    let wasCancel = didRequestCancelForCurrentSession
    didRequestCancelForCurrentSession = false

    recordButton.removeTarget(self, action: #selector(handleDarwinRecordTapped), for: .touchUpInside)
    recordButton.removeTarget(self, action: #selector(handleStopRecordingTapped), for: .touchUpInside)

    if wasCancel {
      endRecordingOrb(success: false)
      logRecordMarker("exitRecordingMode.canceled")
      // Cancelling an agent recording also drops the pending request so the app
      // won't produce a result for it. refreshRecordButton clears the flag.
      if isAgentRecordingActive {
        KeyboardHandoffProvider.shared.clearAgentRequest()
      }
      agentRecordingHeaderText = nil
      agentRecordingHint = nil
      // A cancelled follow-up returns to the card it came from (existing versions
      // stay insertable); a cancelled first-time recording returns to idle.
      if isAgentActionInFlight, !agentReviewVersions.isEmpty {
        isAgentActionInFlight = false
        isAgentRecordingActive = false
        restoreAgentReviewCard()
        return
      }
      isAgentActionInFlight = false
      refreshRecordButton()
      return
    }

    // Agent recordings transcribe → generate; enter the "Writing" state and poll
    // the agent result instead of the plain transcript.
    if isAgentRecordingActive {
      logRecordMarker("exitRecordingMode.agent")
      agentRecordingHeaderText = nil
      endRecordingOrb(success: false)
      enterAgentGenerating()
      return
    }

    // Gapla (G47): the orb stays up, spinning, until the text lands (a stop the app made
    // itself reaches here still recording, so it is moved on to processing). G57: for at most
    // 12 s; then the keys come back while the wait goes on.
    moveOrbToProcessing()
    showLongRunningRecordState(title: "Ishlanmoqda")

    logRecordMarker("exitRecordingMode")
    waitForTranscript()
  }

  private func resetVoiceMeterBars() {
    recordingOrb.setLevel(0)
  }

  @objc private func handleStopRecordingTapped() {
    didRequestStopForCurrentSession = true
    didRequestCancelForCurrentSession = false
    logRecordMarker("handleStopRecordingTapped.beforeRequest")
    KeyboardHandoffProvider.shared.requestStop()
    recordButton.removeTarget(self, action: #selector(handleStopRecordingTapped), for: .touchUpInside)

    // Gapla (G47): the orb settles and spins until the text arrives.
    moveOrbToProcessing()

    // G57 (analysis finding 2): no reset timer here. The old 5 s transient state ran
    // refreshRecordButton, which cleared didRequestStopForCurrentSession and
    // isAgentRecordingActive while the app was still stopping; a stop acknowledged after
    // that read as unexpected and showed «Yozish uzildi». This state ends when the session
    // really ends — the poll sees the recording stop (exitRecordingMode), a failure status, or
    // a stale heartbeat — and the keys come back after 12 s anyway (moveOrbToProcessing).
    issueResetTimer?.invalidate()
    issueResetTimer = nil
    dictationLinkHosting?.view.isUserInteractionEnabled = false
    applyRecordButtonStyle(
      title: "To'xtatilmoqda",
      systemImage: "ellipsis",
      solidBackground: isAgentRecordingActive ? Palette.cleanupAccent : Palette.accent
    )
    logRecordMarker("handleStopRecordingTapped.afterRequest")
  }

  @objc private func handleCancelRecordingTapped() {
    didRequestStopForCurrentSession = true
    didRequestCancelForCurrentSession = true
    // Remember the job so the app's follow-up writes for it (the shared
    // "transcribing" status from its stopRecording, or a late transcript)
    // can't resurrect UI for a dictation the user just abandoned.
    cancelledProcessingJobId = KeyboardHandoffProvider.shared.currentRecordingJobId()
    logRecordMarker("handleCancelRecordingTapped")
    KeyboardHandoffProvider.shared.requestCancel()
    // Defensively flip the active flag locally — if the host app isn't
    // actually recording (e.g., a stale flag put us in the canvas), the
    // metering tick won't observe stop_requested, so nothing else would
    // clear this. Without this we'd be stuck on the canvas.
    KeyboardHandoffProvider.shared.forceClearActiveFlag()
    recordButton.removeTarget(self, action: #selector(handleStopRecordingTapped), for: .touchUpInside)

    // Gapla (G47): the orb shrinks away at once; the keys come back with it.
    endRecordingOrb(success: false)
  }

  /// Cancel from the processing pill (post-recording). The app honours the
  /// cancel flag at its transcription checkpoints; here we also stop waiting,
  /// remember the job so a late transcript can't slip in, and return to idle.
  @objc private func handleProcessingCancelTapped() {
    let provider = KeyboardHandoffProvider.shared

    // G57: the keys (and this ✕) come back 12 s after a stop even when the app has not yet
    // confirmed it. The recording is then still live in the shared state, so cancel it as a
    // recording: the poll sees it end and exitRecordingMode returns to idle without «Yozish uzildi».
    if isRemoteRecordingActive {
      logRecordMarker("handleProcessingCancelTapped.stillRecording")
      handleCancelRecordingTapped()
      return
    }

    // During agent generation the same X aborts the compose. The app's currency
    // check / cancel flag drops any result for this job; we clear the local
    // expectation and the agent keys. An in-flight action (regenerate/follow-up)
    // returns to the card — its existing versions stay insertable — instead of
    // idle; a first-time compose has no card, so it returns to idle.
    if isAgentGenerating {
      logRecordMarker("handleProcessingCancelTapped.agent")
      stopWaitingForAgentResult()
      // Remember this generation so a result the app writes after racing past its
      // own cancel checkpoint is dropped, not shown, at any later adoption point.
      rememberRejectedAgentGeneration()
      isAgentGenerating = false
      agentActionMinUpdatedAtMs = nil
      provider.cancelProcessingJob()
      provider.clearAgentRequest()
      if isAgentActionInFlight, !agentReviewVersions.isEmpty {
        isAgentActionInFlight = false
        isAgentRecordingActive = false
        restoreAgentReviewCard()
        return
      }
      isAgentActionInFlight = false
      provider.clearAgentResult()
      refreshRecordButton()
      return
    }

    cancelledProcessingJobId = provider.currentRecordingJobId()
    logRecordMarker(
      "handleProcessingCancelTapped",
      extra: "job=\(cancelledProcessingJobId ?? "-")"
    )
    provider.cancelProcessingJob()
    waitForTranscriptTimer?.invalidate()
    waitForTranscriptTimer = nil
    endRecordingOrb(success: false)
    refreshRecordButton()
  }

  @objc private func handleDarwinRecordTapped() {
    guard !isDarwinStartPending, !isRemoteRecordingActive else { return }

    recordButton.removeTarget(self, action: #selector(handleDarwinRecordTapped), for: .touchUpInside)
    recordButton.removeTarget(self, action: #selector(handleStopRecordingTapped), for: .touchUpInside)

    cancelledProcessingJobId = nil
    isRemoteRecordingActive = false
    didRequestStopForCurrentSession = false
    // G57: a text still awaited from the previous recording (the keys came back during its
    // processing) is superseded by this one; its late arrival is dropped by job id.
    waitForTranscriptTimer?.invalidate()
    waitForTranscriptTimer = nil
    logRecordMarker("handleDarwinRecordTapped.beforeRequest")
    KeyboardHandoffProvider.shared.requestStart()
    isDarwinStartPending = true
    darwinStartPendingTicks = 0
    darwinStartActiveTicks = 0
    logRecordMarker("handleDarwinRecordTapped.afterRequest")

    showTransientRecordState(
      title: "Boshlanmoqda",
      systemImage: "ellipsis",
      background: Palette.accent,
      duration: 3.0
    )
  }

  private func handleDarwinStartFallback() {
    isDarwinStartPending = false
    darwinStartPendingTicks = 0
    darwinStartActiveTicks = 0
    didRequestStopForCurrentSession = false

    KeyboardHandoffProvider.shared.clearBackgroundSessionReady()

    // A follow-up recording failed to start: the existing card versions are still
    // insertable, so restore the card instead of abandoning them to idle.
    if isAgentActionInFlight, !agentReviewVersions.isEmpty {
      isAgentActionInFlight = false
      isAgentRecordingActive = false
      restoreAgentReviewCard()
      flashAgentReviewNote(hostIsOwnApp ? "Qayta urining" : "Ilovani ochish uchun bosing")
      logRecordMarker("handleDarwinStartFallback.restoreCard")
      return
    }
    isAgentActionInFlight = false
    agentReviewVersions = []
    refreshRecordButton()
    showIssueState(title: hostIsOwnApp ? "Qayta urining" : "Ilovani oching")
    logRecordMarker("handleDarwinStartFallback")
  }

  /// G57: how long the app's heartbeat (written every 1 s while its session runs) may stand still while a text is
  /// awaited before the wait ends. 20 s, not less: a briefly suspended app must not be called dead — the keys
  /// already come back after 12 s (processingKeysReturnDelay), so the user is never stuck meanwhile.
  private static let appSilenceLimitMs: Double = 20_000

  private func waitForTranscript() {
    var attempts = 0
    logRecordMarker("waitForTranscript.start")
    waitForTranscriptTimer?.invalidate()
    waitForTranscriptTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] t in
      guard let self else {
        t.invalidate()
        return
      }
      attempts += 1
      if self.consumePendingTranscriptIfAvailable(trigger: "waitForTranscript") {
        self.logRecordMarker("waitForTranscript.consumed", extra: "attempts=\(attempts)")
        t.invalidate()
        self.waitForTranscriptTimer = nil
        return
      }
      // The app reports failures through the shared status, but Darwin
      // delivery isn't guaranteed — poll it here rather than spinning on
      // "Transcribing" until the timeout.
      let status = KeyboardHandoffProvider.shared.transcriptionStatus()
      if status == "error" || status == "no_speech" || status == "setup_required" {
        self.logRecordMarker(
          "waitForTranscript.failedStatus",
          extra: "status=\(status ?? "-") attempts=\(attempts)"
        )
        let failureTitle: String
        switch status {
        case "no_speech": failureTitle = "Gap eshitilmadi"
        case "setup_required": failureTitle = "Ilovada sozlang"
        default: failureTitle = "Qayta urining"
        }
        self.surfaceHandoffFailure(title: failureTitle)
      } else if status == "idle", attempts > 4 {
        // Cancel/discard ended the job without a transcript; stop waiting
        // instead of spinning until the two-minute timeout. Grace ticks cover
        // the moment before the app stamps "transcribing" on a normal stop.
        self.logRecordMarker("waitForTranscript.idleReset", extra: "attempts=\(attempts)")
        t.invalidate()
        self.waitForTranscriptTimer = nil
        self.endRecordingOrb(success: false)
        self.refreshRecordButton()
      } else if KeyboardHandoffProvider.shared.hasAppStoppedResponding(staleMs: Self.appSilenceLimitMs) {
        // G57 (analysis finding 1): the app's heartbeat has stood still for over 20 s — it was
        // killed (memory, force quit) or suspended, and no text is coming. Say so now instead
        // of spinning until the two- or five-minute timeout.
        self.logRecordMarker("waitForTranscript.appSilent", extra: "attempts=\(attempts)")
        self.surfaceHandoffFailure(title: "Gapla ilovasi javob bermadi")
      } else if attempts > (KeyboardHandoffProvider.shared.currentGaplaMode() == "lokal" ? 400 : 160) {
        // Gapla: Lokal runs RubaiSTT on the server (~22 s for a short clip, against 1–2 s for
        // the other modes), so the keyboard waits 5 minutes instead of 2 before giving up.
        self.logRecordMarker("waitForTranscript.timeout")
        self.surfaceHandoffFailure(title: "Qayta urining")
      }
    }
    if let waitForTranscriptTimer {
      RunLoop.main.add(waitForTranscriptTimer, forMode: .common)
    }
  }

  // MARK: - Agent generating + review

  /// Post-recording state for an agent job: the app is transcribing the spoken
  /// instruction and generating a reply. Shows the accent "Writing" pill with a
  /// cancel X and polls for the result.
  private func enterAgentGenerating() {
    isAgentGenerating = true
    agentActionMinUpdatedAtMs = nil
    showAgentWritingState()
    waitForAgentResult()
  }

  /// Regenerate path: the card's session is unchanged and no new recording runs,
  /// so the pre-action result is still readable. Fade the card out to the Phase 2
  /// "Writing" pill (keeping the local versions so error/cancel can restore it),
  /// then wait for a result the app wrote no earlier than the action's timestamp
  /// (agentActionMinUpdatedAtMs gates both the poll and the Darwin ready path).
  private func enterAgentRegenerating(minUpdatedAtMs: Int64) {
    isAgentGenerating = true
    isAgentActionInFlight = true
    agentActionMinUpdatedAtMs = minUpdatedAtMs
    hideAgentReviewCard(clearState: false)
    showAgentWritingState()
    waitForAgentResult()
  }

  private func showAgentWritingState() {
    issueResetTimer?.invalidate()
    issueResetTimer = nil
    dictationLinkHosting?.view.isUserInteractionEnabled = false
    applyRecordButtonStyle(
      title: "Tayyorlanmoqda",
      systemImage: "ellipsis",
      solidBackground: Palette.cleanupAccent
    )
    processingCancelButton.isHidden = false
  }

  /// Belt-and-suspenders poll (Darwin delivery of agent_ready/agent_error isn't
  /// guaranteed). Clone of waitForTranscript: 0.75s ticks, resolves on the shared
  /// status, additionally detects app death via a stale heartbeat and caps at ~75s.
  /// Adoption is gated by agentActionMinUpdatedAtMs: for a regenerate (session /
  /// recording-job unchanged, so the pre-action result is still readable) a result
  /// is accepted only once the app rewrites it at/after the action timestamp; for
  /// compose/follow-up it's nil and the first readable, non-superseded result wins.
  private func waitForAgentResult() {
    var attempts = 0
    logRecordMarker("waitForAgentResult.start")
    waitForAgentResultTimer?.invalidate()
    waitForAgentResultTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] t in
      guard let self else {
        t.invalidate()
        return
      }
      guard self.isAgentGenerating else {
        t.invalidate()
        self.waitForAgentResultTimer = nil
        return
      }
      attempts += 1

      let provider = KeyboardHandoffProvider.shared
      let status = provider.transcriptionStatus()

      if status == "agent_ready" {
        if let result = provider.readAgentResult() {
          if self.isAgentResultRejected(result) {
            // A cancelled/timed-out generation the app finished anyway. Drop the
            // stale result + status so it can't open a card; keep polling in case
            // a newer, legitimate result for this wait is still coming.
            self.logRecordMarker("waitForAgentResult.rejected", extra: "job=\(result.jobId)")
            provider.clearAgentResult()
            provider.clearTranscriptionStatus()
            return
          }
          if self.agentResultSatisfiesAction(result) {
            self.logRecordMarker("waitForAgentResult.ready", extra: "attempts=\(attempts)")
            self.handleAgentReady(result)
            return
          }
          // Action wait only: the readable result is the pre-action one the app
          // hasn't rewritten yet. Keep waiting (the app-death/timeout guards
          // below still apply) rather than treating this as a missing result.
          return
        }
        // Status says ready but no readable result; keep polling a few ticks
        // (Darwin/write races), then give up.
        if attempts > 8 {
          self.handleAgentError(detail: nil)
        }
        return
      }

      if status == "agent_error" {
        self.logRecordMarker("waitForAgentResult.error", extra: "attempts=\(attempts)")
        self.handleAgentError(detail: provider.transcriptionError())
        return
      }

      // App-death detection: still generating but no fresh heartbeat ⇒ the app
      // process was jetsam'd mid-job; no result will ever land.
      if status == "agent_generating", !provider.isAppHeartbeatFresh() {
        self.logRecordMarker("waitForAgentResult.appDied", extra: "attempts=\(attempts)")
        self.surfaceAgentFailure(title: "Gapla'ni oching")
        return
      }

      // ~75s hard timeout (0.75s × 100). JS worst case (transcribe + 55s stream +
      // retry + 55s retry) can exceed this, so remember the job/action first: a
      // slow-but-successful result that lands later must be dropped, not shown.
      if attempts > 100 {
        self.logRecordMarker("waitForAgentResult.timeout")
        self.rememberRejectedAgentGeneration()
        self.surfaceAgentFailure(title: "Qayta urining")
      }
    }
    if let waitForAgentResultTimer {
      RunLoop.main.add(waitForAgentResultTimer, forMode: .common)
    }
  }

  private func stopWaitingForAgentResult() {
    waitForAgentResultTimer?.invalidate()
    waitForAgentResultTimer = nil
  }

  /// Result landed: stop polling, clear the "generating" flags, and show the card
  /// on the newest result (its activeIndex). The new result supersedes any
  /// versions retained for an in-flight action.
  private func handleAgentReady(_ result: AgentResult) {
    stopWaitingForAgentResult()
    isAgentGenerating = false
    isAgentActionInFlight = false
    agentActionMinUpdatedAtMs = nil
    processingCancelButton.isHidden = true
    showAgentReviewCard(result)
  }

  /// agent_error routing. Mid-action (regenerate/follow-up) the existing versions
  /// stay insertable: restore the card and flash a transient note instead of
  /// dropping to idle; usage_limit still reads "Limit reached", others "Try
  /// again". With no card to keep, fall back to the Phase 2 issue pill.
  private func handleAgentError(detail: String?) {
    stopWaitingForAgentResult()
    isAgentGenerating = false
    agentActionMinUpdatedAtMs = nil
    processingCancelButton.isHidden = true
    KeyboardHandoffProvider.shared.clearTranscriptionStatus()
    KeyboardHandoffProvider.shared.clearAgentRequest()
    // session_expired means the session TTL lapsed — retrying the same session
    // can't succeed, so prompt a fresh start instead of the retryable "Try again".
    let title: String
    switch detail {
    case "usage_limit": title = "Limit tugadi"
    case "session_expired": title = "Boshidan boshlang"
    // An anonymous onboarding session; only creating an account clears it.
    case "account_required": title = "Hisob yarating"
    // No agent provider is chosen for the Providers mode; retrying can't help.
    case "agent_setup_required": title = "Ilovada sozlang"
    default: title = "Qayta urining"
    }
    if isAgentActionInFlight, !agentReviewVersions.isEmpty {
      isAgentActionInFlight = false
      restoreAgentReviewCard()
      flashAgentReviewNote(title)
      return
    }
    isAgentActionInFlight = false
    showIssueState(title: title)
  }

  /// Terminal agent failure that isn't a plain retry (app died, missing result).
  /// Mid-action, keep the card (existing versions insertable) with a note; else
  /// stop the shared status resurfacing, clear the request, and show the pill.
  private func surfaceAgentFailure(title: String) {
    stopWaitingForAgentResult()
    isAgentGenerating = false
    agentActionMinUpdatedAtMs = nil
    processingCancelButton.isHidden = true
    KeyboardHandoffProvider.shared.clearTranscriptionStatus()
    KeyboardHandoffProvider.shared.clearAgentRequest()
    if isAgentActionInFlight, !agentReviewVersions.isEmpty {
      isAgentActionInFlight = false
      restoreAgentReviewCard()
      flashAgentReviewNote(title)
      return
    }
    isAgentActionInFlight = false
    showIssueState(title: title)
  }

  /// Briefly flashes a transient note (an action error) in the top-centre slot,
  /// hiding the follow-up capsule while it shows, then restores the capsule. The
  /// card's versions stay insertable throughout — this is the card-scoped
  /// analogue of showTransientRecordState.
  private func flashAgentReviewNote(_ text: String) {
    agentReviewNoteResetTimer?.invalidate()
    agentReviewHeaderLabel.text = text
    agentReviewHeaderLabel.isHidden = false
    agentReviewFollowUpButton.isHidden = true
    agentReviewNoteResetTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
      guard let self, self.isAgentReviewShown else { return }
      self.agentReviewHeaderLabel.isHidden = true
      self.agentReviewFollowUpButton.isHidden = false
    }
    if let agentReviewNoteResetTimer {
      RunLoop.main.add(agentReviewNoteResetTimer, forMode: .common)
    }
  }

  /// Shows the card on the given result, adopting its versions and (newest)
  /// active index. Seeds the local pager/session state the middle controls act on.
  private func showAgentReviewCard(_ result: AgentResult) {
    isAgentReviewShown = true
    applyKeyboardHeight()
    agentReviewVersions = result.versions
    agentReviewActiveIndex = result.activeIndex
    agentReviewSessionId = result.sessionId
    // Clear any transient note left over from a prior session so the capsule (not
    // a stale header note) shows on a fresh card.
    agentReviewNoteResetTimer?.invalidate()
    agentReviewHeaderLabel.isHidden = true
    agentReviewFollowUpButton.isHidden = false
    displayActiveAgentVersion()
    refreshAgentReviewControls()
    // Reset any lingering transient state on the (now hidden) record button.
    issueResetTimer?.invalidate()
    issueResetTimer = nil
    processingCancelButton.isHidden = true

    agentReviewCanvas.isUserInteractionEnabled = true
    UIView.animate(withDuration: 0.18, delay: 0, options: .curveEaseOut, animations: {
      self.agentReviewCanvas.alpha = 1
      self.rootStack.alpha = 0
    })
  }

  /// Loads the currently-paged version into the read-only text view, scrolled to
  /// the top. Pure UI — no App Group writes.
  private func displayActiveAgentVersion() {
    guard agentReviewVersions.indices.contains(agentReviewActiveIndex) else { return }
    agentReviewTextView.text = agentReviewVersions[agentReviewActiveIndex]
    agentReviewTextView.setContentOffset(.zero, animated: false)
  }

  /// Updates the 1/N pager (hidden when a single version) and gates the
  /// regenerate/follow-up controls on app-heartbeat freshness: fresh ⇒ the button
  /// handlers run; stale ⇒ the "Open OpenWhispr" wake-link overlay takes the tap.
  private func refreshAgentReviewControls() {
    if !didSetupAgentReviewWakeLinks {
      didSetupAgentReviewWakeLinks = true
      setupAgentReviewWakeLinks()
    }
    let count = agentReviewVersions.count
    let showPager = count > 1
    agentReviewPagerPrevButton.isHidden = !showPager
    agentReviewPagerNextButton.isHidden = !showPager
    agentReviewPagerLabel.isHidden = !showPager
    if showPager {
      agentReviewPagerLabel.text = "\(agentReviewActiveIndex + 1)/\(count)"
      agentReviewPagerPrevButton.isEnabled = agentReviewActiveIndex > 0
      agentReviewPagerNextButton.isEnabled = agentReviewActiveIndex < count - 1
      agentReviewPagerPrevButton.alpha = agentReviewPagerPrevButton.isEnabled ? 1.0 : 0.35
      agentReviewPagerNextButton.alpha = agentReviewPagerNextButton.isEnabled ? 1.0 : 0.35
    }

    // Regenerate/follow-up need the app alive. When its heartbeat is stale the
    // wake-link overlays each button (like the entry button's handoff link) so a
    // tap opens OpenWhispr instead of writing an action the dead app can't serve.
    let appAlive = KeyboardHandoffProvider.shared.isAppHeartbeatFresh()
    agentReviewRegenerateWakeLink?.view.isUserInteractionEnabled = !appAlive
    agentReviewFollowUpWakeLink?.view.isUserInteractionEnabled = !appAlive
  }

  /// Fades the card out. Fully dismisses (clearState: true) after insert/dismiss;
  /// a regenerate keeps the local versions/session so error or cancel can restore
  /// the card without a re-read (clearState: false).
  private func hideAgentReviewCard(clearState: Bool = true) {
    isAgentReviewShown = false
    applyKeyboardHeight()
    agentReviewCanvas.isUserInteractionEnabled = false
    if clearState {
      agentReviewTextView.text = ""
      agentReviewVersions = []
      agentReviewActiveIndex = 0
      agentReviewSessionId = ""
    }
    UIView.animate(withDuration: 0.18, delay: 0, options: .curveEaseOut, animations: {
      self.agentReviewCanvas.alpha = 0
      self.rootStack.alpha = 1
    })
  }

  /// Restores the card from the retained local versions (used when a regenerate
  /// is cancelled or errors — the existing versions stay viewable/insertable).
  private func restoreAgentReviewCard() {
    guard !agentReviewVersions.isEmpty else { return }
    isAgentReviewShown = true
    applyKeyboardHeight()
    displayActiveAgentVersion()
    refreshAgentReviewControls()
    processingCancelButton.isHidden = true
    agentReviewCanvas.isUserInteractionEnabled = true
    UIView.animate(withDuration: 0.18, delay: 0, options: .curveEaseOut, animations: {
      self.agentReviewCanvas.alpha = 1
      self.rootStack.alpha = 0
    })
  }

  /// ✓ insert: drop the generated text into the field (natively replacing a
  /// still-live selection), flash "Inserted", clear the result, return to idle.
  @objc private func handleAgentReviewInsertTapped() {
    let text = agentReviewTextView.text ?? ""
    playKeyClick()
    hideAgentReviewCard()
    insertSmartText(text)
    KeyboardHandoffProvider.shared.clearAgentResult()
    KeyboardHandoffProvider.shared.clearTranscriptionStatus()
    logRecordMarker("handleAgentReviewInsertTapped", extra: "chars=\(text.count)")
    showTransientRecordState(
      title: "Joylandi",
      systemImage: "checkmark",
      background: Palette.accent,
      duration: 1.1
    )
  }

  /// ✕ dismiss: discard the result and return to idle without inserting.
  @objc private func handleAgentReviewDismissTapped() {
    playKeyClick()
    hideAgentReviewCard()
    KeyboardHandoffProvider.shared.clearAgentResult()
    KeyboardHandoffProvider.shared.clearTranscriptionStatus()
    logRecordMarker("handleAgentReviewDismissTapped")
    refreshRecordButton()
  }

  /// ↻ regenerate: ask the app for a fresh version of the same session. The wake
  /// link handles the app-dead case, but re-check freshness here (the button may
  /// have been tapped in the same tick the app died). Writes the action, pokes
  /// the app, and transitions to "Writing" waiting for a result newer than now.
  @objc private func handleAgentReviewRegenerateTapped() {
    guard isAgentReviewShown, !isAgentGenerating else { return }
    let provider = KeyboardHandoffProvider.shared
    guard provider.isAppHeartbeatFresh() else {
      // App went stale between the layout refresh and this tap; re-gate so the
      // wake link takes over on the next interaction.
      refreshAgentReviewControls()
      return
    }
    playKeyClick()
    let atMs = provider.writeAgentRegenerateAction(sessionId: agentReviewSessionId)
    logRecordMarker("handleAgentReviewRegenerateTapped", extra: "session=\(agentReviewSessionId)")
    enterAgentRegenerating(minUpdatedAtMs: atMs)
  }

  /// Follow-up mic: refine the last reply by voice. Writes a follow-up request
  /// (reusing the session; no context re-capture) and starts recording in place
  /// with the "Describe your changes" caption. The normal pipeline then runs
  /// (transcribe → generate) and the card returns with the updated version.
  @objc private func handleAgentReviewFollowUpTapped() {
    guard isAgentReviewShown, !isAgentGenerating, !isDarwinStartPending, !isRemoteRecordingActive else { return }
    let provider = KeyboardHandoffProvider.shared
    guard provider.isAppHeartbeatFresh() else {
      refreshAgentReviewControls()
      return
    }
    playKeyClick()
    provider.writeAgentFollowUpRequest(sessionId: agentReviewSessionId)
    logRecordMarker("handleAgentReviewFollowUpTapped", extra: "session=\(agentReviewSessionId)")
    // Keep the versions so an error/cancel during the follow-up restores the card.
    isAgentActionInFlight = true
    isAgentRecordingActive = true
    hideAgentReviewCard(clearState: false)
    agentRecordingHint = agentHint(from: Self.agentFollowUpHints)
    startAgentRecordingInPlace(caption: "Nimani o'zgartirishni ayting")
  }

  @objc private func handleAgentReviewPagerPrevTapped() {
    guard agentReviewActiveIndex > 0 else { return }
    playKeyClick()
    agentReviewActiveIndex -= 1
    displayActiveAgentVersion()
    refreshAgentReviewControls()
  }

  @objc private func handleAgentReviewPagerNextTapped() {
    guard agentReviewActiveIndex < agentReviewVersions.count - 1 else { return }
    playKeyClick()
    agentReviewActiveIndex += 1
    displayActiveAgentVersion()
    refreshAgentReviewControls()
  }

  /// Whether a readable result may be adopted for the current wait. A regenerate
  /// (agentActionMinUpdatedAtMs set) requires the app to have rewritten the result
  /// at/after the action timestamp; compose/follow-up accept the first readable,
  /// non-superseded result. Gates both the poll and the Darwin agent_ready path.
  private func agentResultSatisfiesAction(_ result: AgentResult) -> Bool {
    guard let minUpdatedAtMs = agentActionMinUpdatedAtMs else { return true }
    guard let updatedAtMs = result.updatedAtMs else { return false }
    return Int64(updatedAtMs) >= minUpdatedAtMs
  }

  /// Records the in-flight generation as rejected so a late agent_ready/result
  /// the app writes after we stopped waiting (cancel or timeout) can never open a
  /// card. A regenerate is keyed by its action timestamp (the result jobId is
  /// "<atMs>-<uuid>"); a compose/follow-up by the current recording jobId.
  private func rememberRejectedAgentGeneration() {
    if let atMs = agentActionMinUpdatedAtMs {
      rejectedAgentActionAtMs.insert(atMs)
    }
    if let jobId = KeyboardHandoffProvider.shared.currentRecordingJobId(),
       !jobId.isEmpty {
      rejectedAgentJobIds.insert(jobId)
    }
  }

  /// True when the result belongs to a generation the user cancelled or that the
  /// keyboard timed out on. Consulted at every adoption point (poll, Darwin
  /// agent_ready, resume-on-reopen) so a stale result is dropped, not shown.
  private func isAgentResultRejected(_ result: AgentResult) -> Bool {
    if rejectedAgentJobIds.contains(result.jobId) { return true }
    if let dash = result.jobId.firstIndex(of: "-"),
       let atMs = Int64(result.jobId[..<dash]),
       rejectedAgentActionAtMs.contains(atMs) {
      return true
    }
    return false
  }
}

/// A validated snapshot of `keyboard_agent_result`: every generated version and
/// the app's chosen active index (for the 1/N pager), the session the reply
/// belongs to (for follow-up/regenerate actions), the recording job it belongs
/// to (for currency checks), and when the app wrote it (for the resume-on-reopen
/// freshness window and action-driven result waits).
private struct AgentResult {
  let versions: [String]
  let activeIndex: Int
  let sessionId: String
  let jobId: String
  let updatedAtMs: Double?
}

private struct KeyboardHandoffProvider {
  static let shared = KeyboardHandoffProvider()

  private static func infoString(_ key: String) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static var resolvedContainingAppBundleID: String {
    if let configured = infoString("OpenWhisprContainingAppBundleIdentifier") {
      return configured
    }
    let bundleID = Bundle.main.bundleIdentifier ?? "com.gizmolabs.openwhispr.keyboard"
    let suffix = ".keyboard"
    return bundleID.hasSuffix(suffix) ? String(bundleID.dropLast(suffix.count)) : bundleID
  }

  // Matches the app-side probe's identity exactly (nativeApplicationVersion +
  // nativeBuildVersion). A TestFlight rebuild bumps only CFBundleVersion, and
  // that alone must break equality — iOS can reset Full Access on any native
  // install, not just marketing releases.
  private static let bundleVersionIdentity: String = {
    let short = infoString("CFBundleShortVersionString") ?? "unknown"
    let build = infoString("CFBundleVersion") ?? "unknown"
    return "\(short)+\(build)"
  }()

  /// Gapla (G57, analysis finding 6): one App Group store for every read and write here, made
  /// once, instead of a new UserDefaults object on each call (the 0.12 s poll alone made several a
  /// second). Same suite, same data: other processes' writes still show up through it.
  private static let sharedDefaults = UserDefaults(suiteName: "group.\(resolvedContainingAppBundleID)")

  /// Gapla (G64): the job whose text was handed to the keyboard last, for its «matn-kiritildi» line.
  static var lastConsumedJobId: String?
  private static let gaplaVaqtQueue = DispatchQueue(label: "uz.gapla.vaqt.klaviatura", qos: .utility)

  /// Gapla (G64): one dictation timing line from the keyboard — the same shape and file as the
  /// app's (modules/app-group-storage/ios/GaplaVaqt.swift): the device log (`syslog live -m
  /// gapla-vaqt`) and `gapla-vaqt.log` in the App Group, which the app trims. Never the text.
  func gaplaVaqt(_ qadam: String, job: String?, extra: String = "") {
    let jobPart = (job?.isEmpty == false) ? job! : "-"
    let extraPart = extra.isEmpty ? "" : " \(extra)"
    let line = "gapla-vaqt job=\(jobPart) qadam=\(qadam) ms=\(Int64(Date().timeIntervalSince1970 * 1000))\(extraPart)"
    KeyboardLog.ui.notice("\(line, privacy: .public)")
    let groupId = "group.\(Self.resolvedContainingAppBundleID)"
    Self.gaplaVaqtQueue.async {
      guard let directory = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: groupId
      ) else { return }
      let url = directory.appendingPathComponent("gapla-vaqt.log")
      let data = Data((line + "\n").utf8)
      if let handle = try? FileHandle(forWritingTo: url) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
      } else {
        try? data.write(to: url, options: .atomic)
      }
    }
  }

  private let pendingTranscriptKey = "keyboard_pending_transcript"
  private let pendingTranscriptJobIdKey = "keyboard_pending_transcript_job_id"
  // Gapla (G56): written by the app's translator on «Joylash» (src/screens/TarjimonScreen.tsx).
  private let pendingTranslationKey = "gapla_tarjima_joylash"
  private let pendingTranslationAtMsKey = "gapla_tarjima_joylash_ms"

  /// The translation the app's translator handed over, taken once. Older than two minutes it is dropped, so it never
  /// lands late in some other field.
  func consumePendingTranslation() -> String? {
    guard let defaults = Self.sharedDefaults,
          let text = defaults.string(forKey: pendingTranslationKey) else { return nil }
    let atMs = Double(defaults.string(forKey: pendingTranslationAtMsKey) ?? "") ?? 0
    defaults.removeObject(forKey: pendingTranslationKey)
    defaults.removeObject(forKey: pendingTranslationAtMsKey)
    let ageMs = Date().timeIntervalSince1970 * 1000 - atMs
    guard ageMs >= 0, ageMs < 120_000, !text.isEmpty else { return nil }
    return text
  }

  private let orphanedRawTranscriptKey = "keyboard_orphaned_raw_transcript"
  private let orphanedRawTranscriptJobIdKey = "keyboard_orphaned_raw_transcript_job_id"
  private let recordingJobIdKey = "keyboard_recording_job_id"
  private let recordingActiveKey = "keyboard_recording_active"
  private let audioLevelKey = "keyboard_audio_level"
  private let orbTestVoiceKey = "gapla_orb_test_voice"
  private let stopRequestedKey = "keyboard_stop_requested"
  private let stopRequestedAtMsKey = "keyboard_stop_requested_at_ms"
  private let cancelRequestedKey = "keyboard_cancel_requested"
  private let shownAtMsKey = "keyboard_shown_at_ms"
  private let shownAtVersionKey = "keyboard_shown_version"
  private let handoffIntentAtMsKey = "keyboard_handoff_intent_at_ms"
  private let backgroundSessionReadyKey = "background_session_ready"
  private let backgroundSessionWarmMicKey = "background_session_warm_mic"
  private let backgroundSessionHeartbeatKey = "background_session_heartbeat"
  private let transcriptionStatusKey = "keyboard_transcription_status"
  private let transcriptionErrorKey = "keyboard_transcription_error"
  private let transcriptionStatusUpdatedAtMsKey = "keyboard_transcription_status_updated_at_ms"
  private let dictationToneKey = "keyboard_dictation_tone"
  private let toneApplicableKey = "keyboard_tone_applicable"
  // Dictation-agent mirror keys (app-written, persist across launches) and the
  // one-shot request / result channels shared with the main app.
  private let agentEnabledKey = "keyboard_agent_enabled"
  private let agentApplicableKey = "keyboard_agent_applicable"
  private let agentShareContextKey = "keyboard_agent_share_context"
  private let agentNameKey = "keyboard_agent_name"
  private let agentRequestKey = "keyboard_agent_request"
  private let agentJobKey = "keyboard_agent_job"
  private let agentResultKey = "keyboard_agent_result"
  private let agentActionKey = "keyboard_agent_action"
  private let agentActionAtMsKey = "keyboard_agent_action_at_ms"
  private let agentHintsHiddenUntilMsKey = "keyboard_agent_hints_hidden_until_ms"
  static let toneValues = ["default", "formal", "casual", "very_casual", "excited"]
  private static var darwinStartNotificationName: String {
    "\(resolvedContainingAppBundleID).startRecording"
  }
  private static var darwinStopNotificationName: String {
    "\(resolvedContainingAppBundleID).stopRecording"
  }
  private static var darwinAgentActionNotificationName: String {
    "\(resolvedContainingAppBundleID).agentAction"
  }

  private static let bundleToScheme: [String: String] = [
    "com.whatsapp.WhatsApp": "whatsapp://send",
    "net.whatsapp.WhatsApp": "whatsapp://send",
    "net.whatsapp.WhatsAppSMB": "whatsapp-business://",
    "com.burbn.instagram": "instagram://",
    "com.atebits.Tweetie2": "twitter://",
    "com.facebook.Facebook": "fb://",
    "com.facebook.Messenger": "fb-messenger://",
    "com.tinyspeck.chatlyio": "slack://",
    "com.skype.skype": "skype://",
    "ph.telegra.Telegraph": "tg://",
    "org.whispersystems.signal": "sgnl://",
    "com.viber": "viber://",
    "jp.naver.line": "line://",
    "com.google.Gmail": "googlegmail://",
    "com.google.Docs": "googledocs://",
    "com.microsoft.Office.Outlook": "ms-outlook://",
    "com.microsoft.skype.teams": "msteams://",
    "com.apple.mobilemail": "message://",
    "com.apple.MobileSMS": "sms://",
    "com.apple.mobilenotes": "mobilenotes://",
    "com.microsoft.teams": "msteams://",
    "notion.id": "notion://",
    "com.discord.Discord": "discord://",
    "com.linkedin.LinkedIn": "linkedin://",
    "com.reddit.Reddit": "reddit://",
    "com.hammerandchisel.discord": "discord://",
    "us.zoom.videomeetings": "zoomus://",
    "com.openai.chat": "chatgpt://",
    "com.google.chrome.ios": "googlechrome://",
    "com.apple.mobilesafari": "x-web-search://",
    "com.zhiliaoapp.musically": "snssdk1128://",
    "com.snapchat.snapchat": "snapchat://",
    "com.toyopagroup.picaboo": "snapchat://",
  ]

  private static let normalizedBundleToScheme: [String: String] = {
    var normalized: [String: String] = [:]
    for (bundle, scheme) in bundleToScheme {
      normalized[bundle.lowercased()] = scheme
    }
    return normalized
  }()

  func consumePendingTranscript() -> String? {
    guard let sharedDefaults = Self.sharedDefaults else {
      KeyboardLog.storage.error("Unable to open app-group defaults for keyboard handoff.")
      KeyboardLog.echo("Unable to open app-group defaults for keyboard handoff.")
      return nil
    }

    guard let raw = sharedDefaults.string(forKey: pendingTranscriptKey) else {
      return nil
    }

    let pendingJobId = sharedDefaults.string(forKey: pendingTranscriptJobIdKey)
    let activeJobId = sharedDefaults.string(forKey: recordingJobIdKey)
    if let pendingJobId,
       let activeJobId,
       !pendingJobId.isEmpty,
       !activeJobId.isEmpty,
       pendingJobId != activeJobId,
       isPendingSuperseded(pendingJobId: pendingJobId, activeJobId: activeJobId) {
      sharedDefaults.removeObject(forKey: pendingTranscriptKey)
      sharedDefaults.removeObject(forKey: pendingTranscriptJobIdKey)
      KeyboardLog.echo("MARKER consumePendingTranscript.stale pendingJob=\(pendingJobId) activeJob=\(activeJobId)")
      return nil
    }

    Self.lastConsumedJobId = pendingJobId ?? activeJobId
    sharedDefaults.removeObject(forKey: pendingTranscriptKey)
    sharedDefaults.removeObject(forKey: pendingTranscriptJobIdKey)
    sharedDefaults.removeObject(forKey: recordingJobIdKey)
    sharedDefaults.set("idle", forKey: transcriptionStatusKey)
    sharedDefaults.removeObject(forKey: transcriptionErrorKey)
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  func currentTone() -> String {
    guard let defaults = Self.sharedDefaults,
          let raw = defaults.string(forKey: dictationToneKey),
          Self.toneValues.contains(raw) else {
      return "default"
    }
    return raw
  }

  func setTone(_ tone: String) {
    guard Self.toneValues.contains(tone),
          let defaults = Self.sharedDefaults else { return }
    defaults.set(tone, forKey: dictationToneKey)
    defaults.synchronize()
  }

  // Gapla: the cleanup mode (Tez, O'rta, Sekin). The app reads the same App Group key
  // (src/lib/gaplaMode.ts) and sends the mode to the Gapla bridge with each recording.
  private let gaplaModeKey = "gapla_rejim"
  static let gaplaModeValues = ["tez", "orta", "sekin", "lokal"]
  static let gaplaDefaultMode = "orta"

  func currentGaplaMode() -> String {
    guard let defaults = Self.sharedDefaults,
          let raw = defaults.string(forKey: gaplaModeKey),
          Self.gaplaModeValues.contains(raw) else {
      return Self.gaplaDefaultMode
    }
    return raw
  }

  func setGaplaMode(_ mode: String) {
    guard Self.gaplaModeValues.contains(mode),
          let defaults = Self.sharedDefaults else { return }
    defaults.set(mode, forKey: gaplaModeKey)
    defaults.synchronize()
  }

  func isToneApplicable() -> Bool {
    guard let defaults = Self.sharedDefaults else { return false }
    return defaults.string(forKey: toneApplicableKey) != "0"
  }

  // Gapla (G58): the keyboard languages the app has on, saved as "uz,ru,en,tr" (src/lib/keyboardLanguages.ts). Not
  // saved yet, or no App Group (Full Access off): all four, the default. Uzbek is always on; the order is the key's.
  private let keyboardLanguagesKey = "gapla_klaviatura_tillari"

  func keyboardLanguages() -> [KeyboardLanguage] {
    guard let raw = Self.sharedDefaults?.string(forKey: keyboardLanguagesKey) else { return KeyboardLanguage.allCases }
    let saved = Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    return KeyboardLanguage.allCases.filter { $0 == .uz || saved.contains($0.rawValue) }
  }

  // MARK: Dictation agent

  /// The dictation agent is off entirely unless the app has mirrored enabled=1.
  func isAgentEnabled() -> Bool {
    Self.sharedDefaults?.string(forKey: agentEnabledKey) == "1"
  }

  /// Applicable = the voice assistant can run: an account for Cloud, or its own
  /// provider. Not applicable ⇒ the entry button is dimmed and points the user at
  /// the app, mirroring tone.
  func isAgentApplicable() -> Bool {
    Self.sharedDefaults?.string(forKey: agentApplicableKey) == "1"
  }

  /// Only when the user has opted in do we share the surrounding field text.
  func agentSharesContext() -> Bool {
    Self.sharedDefaults?.string(forKey: agentShareContextKey) == "1"
  }

  /// Display name shown in the recording/review headers ("Tell {name}…").
  func agentName() -> String {
    guard let raw = Self.sharedDefaults?.string(forKey: agentNameKey) else {
      return "Agent"
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Agent" : trimmed
  }

  /// The app hides the example instructions until this deadline while its own walkthrough says
  /// what to dictate (onboarding's voice assistant step). A deadline, so a step the app never left
  /// (killed mid-onboarding) stops hiding them on its own.
  func agentHintsHidden() -> Bool {
    guard let raw = Self.sharedDefaults?.string(forKey: agentHintsHiddenUntilMsKey),
          let untilMs = Double(raw) else { return false }
    return Date().timeIntervalSince1970 * 1000 < untilMs
  }

  /// True when the app has written its heartbeat within the last 5s (same rule
  /// used for recording-active). While the agent is generating, a stale/missing
  /// heartbeat means the app process died mid-job and no result is coming.
  func isAppHeartbeatFresh() -> Bool {
    guard let defaults = Self.sharedDefaults,
          let raw = defaults.string(forKey: backgroundSessionHeartbeatKey),
          let heartbeatMs = Double(raw) else { return false }
    return Date().timeIntervalSince1970 * 1000 - heartbeatMs <= 5_000
  }

  /// Gapla (G57): while the keyboard waits for a transcript — true when the app's keep-alive
  /// heartbeat (written every 1 s) has stood still for more than `staleMs` and the app is not in
  /// the foreground either (its own 2 s stamp): it was killed or suspended, and no text is coming.
  /// A missing heartbeat does not count: the app removes it itself when its microphone stops
  /// (stopRecording with the engine down, an interruption) and may still be finishing the text.
  func hasAppStoppedResponding(staleMs: Double) -> Bool {
    guard let defaults = Self.sharedDefaults else { return false }
    let nowMs = Date().timeIntervalSince1970 * 1000
    if let raw = defaults.string(forKey: "containing_app_foreground_at_ms"),
       let foregroundAtMs = Double(raw),
       nowMs - foregroundAtMs <= staleMs {
      return false
    }
    guard let raw = defaults.string(forKey: backgroundSessionHeartbeatKey),
          let heartbeatMs = Double(raw) else { return false }
    return nowMs - heartbeatMs > staleMs
  }

  /// Writes the one-shot compose request the app consumes at recording start.
  /// selectedText is always captured; the before/after context only when the
  /// user opted in. Mirrors keyboardAgentSync's KeyboardAgentRequest shape.
  func writeAgentComposeRequest(
    selectedText: String?,
    contextBefore: String?,
    contextAfter: String?
  ) {
    guard let defaults = Self.sharedDefaults else { return }
    var payload: [String: Any] = [
      "kind": "compose",
      "requestedAtMs": Int(Date().timeIntervalSince1970 * 1000),
    ]
    if let selectedText, !selectedText.isEmpty { payload["selectedText"] = selectedText }
    if let contextBefore, !contextBefore.isEmpty { payload["contextBefore"] = contextBefore }
    if let contextAfter, !contextAfter.isEmpty { payload["contextAfter"] = contextAfter }
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let json = String(data: data, encoding: .utf8) else { return }
    defaults.set(json, forKey: agentRequestKey)
    defaults.synchronize()
    KeyboardLog.echo("MARKER provider.writeAgentComposeRequest chars=\(json.count)")
  }

  func clearAgentRequest() {
    guard let defaults = Self.sharedDefaults else { return }
    defaults.removeObject(forKey: agentRequestKey)
    defaults.synchronize()
  }

  /// Writes a follow-up compose request that rides the existing recording flow:
  /// the app reuses `sessionId` so the reply threads onto the same session. No
  /// selectedText/context is re-captured — the follow-up refines the last reply.
  func writeAgentFollowUpRequest(sessionId: String) {
    guard let defaults = Self.sharedDefaults else { return }
    let payload: [String: Any] = [
      "kind": "follow_up",
      "sessionId": sessionId,
      "requestedAtMs": Int(Date().timeIntervalSince1970 * 1000),
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let json = String(data: data, encoding: .utf8) else { return }
    defaults.set(json, forKey: agentRequestKey)
    defaults.synchronize()
    KeyboardLog.echo("MARKER provider.writeAgentFollowUpRequest session=\(sessionId)")
  }

  /// Writes the one-shot regenerate action + its epoch-ms twin, then pokes the
  /// app via the `.agentAction` Darwin notification. `requestId` uses the job-id
  /// timestamp-prefix style so the app can apply its timestamp-supersede rule;
  /// returns `atMs` so the caller can wait for a result written no earlier.
  @discardableResult
  func writeAgentRegenerateAction(sessionId: String) -> Int64 {
    let atMs = Int64(Date().timeIntervalSince1970 * 1000)
    guard let defaults = Self.sharedDefaults else { return atMs }
    let requestId = "\(atMs)-\(UUID().uuidString)"
    let payload: [String: Any] = [
      "type": "regenerate",
      "sessionId": sessionId,
      "requestId": requestId,
      "atMs": atMs,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let json = String(data: data, encoding: .utf8) else { return atMs }
    defaults.set(json, forKey: agentActionKey)
    defaults.set(String(atMs), forKey: agentActionAtMsKey)
    defaults.synchronize()
    postDarwinNotification(Self.darwinAgentActionNotificationName)
    KeyboardLog.echo("MARKER provider.writeAgentRegenerateAction session=\(sessionId) requestId=\(requestId)")
    return atMs
  }

  /// True when the app has snapshotted an agent job whose id matches the current
  /// recording. Lets the keyboard recover "this recording is an agent one" after
  /// it was rebuilt mid-recording (a common jetsam case on the handoff path).
  func hasAgentJobForCurrentRecording() -> Bool {
    guard let defaults = Self.sharedDefaults,
          let activeJobId = defaults.string(forKey: recordingJobIdKey),
          !activeJobId.isEmpty,
          let raw = defaults.string(forKey: agentJobKey),
          let data = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let jobId = object["jobId"] as? String else {
      return false
    }
    return jobId == activeJobId
  }

  /// Reads (without clearing) the agent result. Returns nil on absence/invalid
  /// JSON, or when the result's job is superseded by a newer recording — reusing
  /// the same timestamp-prefix staleness rule as pending transcripts.
  func readAgentResult() -> AgentResult? {
    guard let defaults = Self.sharedDefaults,
          let raw = defaults.string(forKey: agentResultKey),
          let data = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let versions = object["versions"] as? [String],
          !versions.isEmpty,
          let jobId = object["jobId"] as? String else {
      return nil
    }
    let activeIndex = object["activeIndex"] as? Int ?? 0
    let clampedIndex = min(max(activeIndex, 0), versions.count - 1)
    let updatedAtMs = (object["updatedAtMs"] as? NSNumber)?.doubleValue
    // Session identity drives follow-up/regenerate; fall back to the job id for
    // legacy writes that predate the session field.
    let sessionId = (object["sessionId"] as? String) ?? jobId

    let activeJobId = defaults.string(forKey: recordingJobIdKey)
    if let activeJobId, !activeJobId.isEmpty, !jobId.isEmpty, activeJobId != jobId,
       isPendingSuperseded(pendingJobId: jobId, activeJobId: activeJobId) {
      KeyboardLog.echo("MARKER provider.readAgentResult.stale resultJob=\(jobId) activeJob=\(activeJobId)")
      return nil
    }

    return AgentResult(
      versions: versions,
      activeIndex: clampedIndex,
      sessionId: sessionId,
      jobId: jobId,
      updatedAtMs: updatedAtMs
    )
  }

  func clearAgentResult() {
    guard let defaults = Self.sharedDefaults else { return }
    defaults.removeObject(forKey: agentResultKey)
    defaults.synchronize()
  }

  /// Job IDs embed their creation time ("<ms>-<rand>") in every generator, so
  /// staleness is decided by age: a pending transcript is superseded only when
  /// the active job is strictly newer. A bookkeeping mismatch caused by the
  /// cross-process write race over the shared job-id key must not throw away
  /// the transcript the user is waiting on.
  private func isPendingSuperseded(pendingJobId: String, activeJobId: String) -> Bool {
    guard let pendingMs = jobCreationMs(pendingJobId),
          let activeMs = jobCreationMs(activeJobId) else {
      return true  // unparsable → keep the old strict-mismatch behaviour
    }
    return activeMs > pendingMs
  }

  private func jobCreationMs(_ jobId: String) -> Double? {
    guard let prefix = jobId.split(separator: "-").first else { return nil }
    return Double(prefix)
  }

  /// Stamps the App Group with the moment the keyboard came on screen so the
  /// main app can detect a successful keyboard switch during onboarding.
  func markShown() {
    guard let defaults = Self.sharedDefaults else { return }
    defaults.set(String(Int(Date().timeIntervalSince1970 * 1000)), forKey: shownAtMsKey)
    defaults.set(Self.bundleVersionIdentity, forKey: shownAtVersionKey)
    defaults.synchronize()
  }

  func isRecordingActive() -> Bool {
    guard let defaults = Self.sharedDefaults else { return false }
    guard defaults.string(forKey: recordingActiveKey) == "1" else { return false }

    // The host app writes a heartbeat every 1s while alive. If it's missing
    // or stale (>5s), the flag is a leftover from a crashed or killed session;
    // clear it so the keyboard doesn't get stuck showing the recording canvas.
    if let rawHeartbeat = defaults.string(forKey: backgroundSessionHeartbeatKey),
       let heartbeatMs = Double(rawHeartbeat) {
      let ageMs = Date().timeIntervalSince1970 * 1000 - heartbeatMs
      if ageMs <= 5_000 {
        return true
      }
      KeyboardLog.echo("MARKER isRecordingActive.staleHeartbeat clearing ageMs=\(Int(ageMs))")
    } else {
      KeyboardLog.echo("MARKER isRecordingActive.noHeartbeat clearing")
    }
    defaults.set("0", forKey: recordingActiveKey)
    defaults.synchronize()
    return false
  }

  func forceClearActiveFlag() {
    guard let defaults = Self.sharedDefaults else { return }
    defaults.set("0", forKey: recordingActiveKey)
  }

  func clearBackgroundSessionReady() {
    guard let defaults = Self.sharedDefaults else { return }
    defaults.set("0", forKey: backgroundSessionReadyKey)
    defaults.synchronize()
  }

  func currentAudioLevel() -> Float {
    guard let defaults = Self.sharedDefaults,
          let raw = defaults.string(forKey: audioLevelKey),
          let value = Float(raw) else { return 0 }
    return min(max(value, 0), 1)
  }

  /// Gapla: the app's «Animatsiya sinovi» switch (PreferencesScreen) is on.
  func isOrbTestVoiceEnabled() -> Bool {
    Self.sharedDefaults?.string(forKey: orbTestVoiceKey) == "1"
  }

  func requestStop() {
    guard let defaults = Self.sharedDefaults else { return }
    gaplaVaqt("toxtat-bosildi", job: defaults.string(forKey: recordingJobIdKey))
    defaults.set("1", forKey: stopRequestedKey)
    defaults.set(String(Int(Date().timeIntervalSince1970 * 1000)), forKey: stopRequestedAtMsKey)
    defaults.set("transcribing", forKey: transcriptionStatusKey)
    defaults.set(
      String(Int(Date().timeIntervalSince1970 * 1000)),
      forKey: transcriptionStatusUpdatedAtMsKey
    )
    postDarwinNotification(Self.darwinStopNotificationName)
    let state = recordingStateSnapshot()
    KeyboardLog.echo(
      "MARKER provider.requestStop sharedActive=\(state.active) sharedReady=\(state.ready) sharedWarm=\(state.warmMic) stopReq=\(state.stopRequested)"
    )
  }

  func requestCancel() {
    guard let defaults = Self.sharedDefaults else { return }
    defaults.set("1", forKey: cancelRequestedKey)
    requestStop()
    KeyboardLog.echo("MARKER provider.requestCancel")
  }

  func currentRecordingJobId() -> String? {
    Self.sharedDefaults?.string(forKey: recordingJobIdKey)
  }

  /// Cancel during the transcription phase (recording already stopped). Raises
  /// the cancel flag the app polls at its checkpoints and clears any transcript
  /// already written for this job, leaving the status idle.
  func cancelProcessingJob() {
    guard let defaults = Self.sharedDefaults else { return }
    defaults.set("1", forKey: cancelRequestedKey)
    defaults.removeObject(forKey: pendingTranscriptKey)
    defaults.removeObject(forKey: pendingTranscriptJobIdKey)
    defaults.removeObject(forKey: orphanedRawTranscriptKey)
    defaults.removeObject(forKey: orphanedRawTranscriptJobIdKey)
    defaults.set("idle", forKey: transcriptionStatusKey)
    defaults.removeObject(forKey: transcriptionErrorKey)
    defaults.synchronize()
    KeyboardLog.echo("MARKER provider.cancelProcessingJob")
  }

  /// Drops a pending transcript that belongs to a cancelled job. Returns true
  /// when it discarded one, so the caller knows not to insert anything.
  func discardPendingTranscriptIfMatches(jobId: String) -> Bool {
    guard let defaults = Self.sharedDefaults,
          defaults.string(forKey: pendingTranscriptKey) != nil,
          defaults.string(forKey: pendingTranscriptJobIdKey) == jobId else { return false }
    defaults.removeObject(forKey: pendingTranscriptKey)
    defaults.removeObject(forKey: pendingTranscriptJobIdKey)
    defaults.set("idle", forKey: transcriptionStatusKey)
    defaults.removeObject(forKey: transcriptionErrorKey)
    KeyboardLog.echo("MARKER provider.discardPendingTranscriptIfMatches job=\(jobId)")
    return true
  }

  /// The bundle identifier of the app that contains this keyboard extension
  /// (the extension's own bundle id minus the ".keyboard" suffix).
  private var containingAppBundleID: String {
    Self.resolvedContainingAppBundleID
  }

  /// True when `bundle` is OpenWhispr itself (or one of its extensions), meaning
  /// the keyboard is running inside the app and a tap records in place rather
  /// than handing off. Mirrors the JS `isSelfHosted` check in useKeyboardHandoff.
  func isContainingAppBundle(_ bundle: String) -> Bool {
    let host = bundle.lowercased()
    let appBundle = containingAppBundleID.lowercased()
    guard !appBundle.isEmpty else { return false }
    return host == appBundle || host.hasPrefix(appBundle + ".")
  }

  /// Gapla (G57, analysis finding 7): a private-API read that gives nil instead of raising when a
  /// later iOS renames it. value(forKey:) on an unknown key raises NSUnknownKeyException — a crash
  /// on the keyboard's first appearance — so the key is read only when the object answers to it as
  /// a method or holds it as an instance variable (the two places KVC reads from).
  private static func privateValue(of object: NSObject?, key: String) -> Any? {
    guard let object else { return nil }
    if object.responds(to: NSSelectorFromString(key)) {
      return object.value(forKey: key)
    }
    if let objectClass = object_getClass(object),
       class_getInstanceVariable(objectClass, key) != nil || class_getInstanceVariable(objectClass, "_" + key) != nil {
      return object.value(forKey: key)
    }
    return nil
  }

  func detectHostBundleID(from controller: UIInputViewController) -> String? {
    if let bundleId = Self.privateValue(of: controller.parent, key: "_hostBundleID") as? String,
       bundleId != "<null>", !bundleId.isEmpty {
      KeyboardLog.echo("Host detected via KVC: \(bundleId)")
      return bundleId
    }
    KeyboardLog.echo("KVC host detection failed, parent=\(controller.parent != nil ? "present" : "nil")")

    guard let pid = Self.privateValue(of: controller.parent, key: "_hostPID") else {
      KeyboardLog.echo("XPC host detection failed: no _hostPID")
      return nil
    }
    let selector = NSSelectorFromString("defaultService")
    guard let anyClass: AnyObject = NSClassFromString("PKService"),
          let pkService = anyClass as? NSObjectProtocol,
          pkService.responds(to: selector),
          let serverInis = pkService.perform(selector)?.takeUnretainedValue() as? NSObjectProtocol
    else { return nil }
    // G57: every private selector below is checked first; perform(_:) on one an object
    // doesn't answer to raises (unrecognized selector) and would end the extension.
    let personalitiesSelector = NSSelectorFromString("personalities")
    let connectionSelector = NSSelectorFromString("connection")
    let xpcConnectionSelector = NSSelectorFromString("_xpcConnection")
    guard serverInis.responds(to: personalitiesSelector) else { return nil }
    let personalities = serverInis.perform(personalitiesSelector)?.takeUnretainedValue()
    let bundleId = Bundle.main.bundleIdentifier ?? ""
    guard let dict = personalities as? NSDictionary,
          let infos = dict[bundleId] as? NSDictionary,
          let info = infos[pid] as? NSObjectProtocol,
          info.responds(to: connectionSelector),
          let con = info.perform(connectionSelector)?.takeUnretainedValue() as? NSObjectProtocol,
          con.responds(to: xpcConnectionSelector)
    else { return nil }
    let xpcCon = con.perform(xpcConnectionSelector)?.takeUnretainedValue()
    guard let xpcCon = xpcCon else { return nil }
    guard let handle = dlopen("/usr/lib/libc.dylib", RTLD_NOW) else { return nil }
    defer { dlclose(handle) }
    guard let sym = dlsym(handle, "xpc_connection_copy_bundle_id") else { return nil }
    typealias XPCFunc = @convention(c) (AnyObject) -> UnsafePointer<CChar>?
    let cFunc = unsafeBitCast(sym, to: XPCFunc.self)
    guard let response = cFunc(xpcCon) else { return nil }
    return String(cString: response)
  }

  func hostUrlScheme(from controller: UIInputViewController) -> String? {
    guard let bundleId = detectHostBundleID(from: controller) else { return nil }
    return Self.bundleToScheme[bundleId] ?? Self.normalizedBundleToScheme[bundleId.lowercased()]
  }

  func storeHostReturnInfo(from controller: UIInputViewController) {
    guard let defaults = Self.sharedDefaults else { return }
    if let scheme = hostUrlScheme(from: controller) {
      defaults.set(scheme, forKey: "keyboard_return_url")
      KeyboardLog.echo("Stored return URL: \(scheme)")
    } else {
      KeyboardLog.echo("No return URL scheme found for host")
    }
    if let bundle = detectHostBundleID(from: controller) {
      defaults.set(bundle, forKey: "keyboard_return_bundle")
    }
    defaults.synchronize()
  }

  func isBackgroundSessionReady() -> Bool {
    guard let defaults = Self.sharedDefaults else { return false }
    guard defaults.string(forKey: backgroundSessionReadyKey) == "1" else { return false }

    guard let rawHeartbeat = defaults.string(forKey: backgroundSessionHeartbeatKey),
          let heartbeatMs = Double(rawHeartbeat) else {
      KeyboardLog.echo("MARKER provider.backgroundReady.noHeartbeat appAssumedDead")
      return false
    }

    let ageMs = Date().timeIntervalSince1970 * 1000 - heartbeatMs
    if ageMs <= 5_000 {
      return true
    }
    KeyboardLog.echo("MARKER provider.backgroundReady.heartbeatStale ageMs=\(Int(ageMs))")
    return false
  }

  /// True when the containing app (OpenWhispr) is itself in the foreground, so
  /// the keyboard is running inside our own app and a tap should record in place
  /// rather than hand off. The app refreshes this timestamp every couple seconds
  /// while foreground and clears it on background; a stale value (app killed)
  /// fails the freshness check, so another host app never reads a false positive.
  /// Private-API host bundle-id detection is unreliable, so this is the signal.
  func isContainingAppForeground() -> Bool {
    guard let defaults = Self.sharedDefaults else { return false }
    guard let raw = defaults.string(forKey: "containing_app_foreground_at_ms"),
          let atMs = Double(raw) else { return false }
    let ageMs = Date().timeIntervalSince1970 * 1000 - atMs
    return ageMs <= 5_000
  }

  func requestStart() {
    if let defaults = Self.sharedDefaults {
      let jobId = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString)"
      defaults.set("0", forKey: stopRequestedKey)
      defaults.removeObject(forKey: stopRequestedAtMsKey)
      defaults.set("0", forKey: recordingActiveKey)
      defaults.removeObject(forKey: audioLevelKey)
      defaults.removeObject(forKey: pendingTranscriptKey)
      defaults.removeObject(forKey: pendingTranscriptJobIdKey)
      defaults.removeObject(forKey: orphanedRawTranscriptKey)
      defaults.removeObject(forKey: orphanedRawTranscriptJobIdKey)
      defaults.set(jobId, forKey: recordingJobIdKey)
      defaults.set("recording", forKey: transcriptionStatusKey)
      defaults.set(
        String(Int(Date().timeIntervalSince1970 * 1000)),
        forKey: transcriptionStatusUpdatedAtMsKey
      )
      defaults.removeObject(forKey: transcriptionErrorKey)
      // Flush before the Darwin post: the app's start handler records under
      // whatever job id it reads, and a stale snapshot here is how recordings
      // end up keyed to the previous session's id (see resolveRecordingJobId's
      // echo-write for the other half of this handshake).
      defaults.synchronize()
      let state = recordingStateSnapshot()
      KeyboardLog.echo(
        "MARKER provider.requestStart.reset jobId=\(jobId) sharedActive=\(state.active) sharedReady=\(state.ready) sharedWarm=\(state.warmMic) stopReq=\(state.stopRequested)"
      )
    }

    postDarwinNotification(Self.darwinStartNotificationName)
    let state = recordingStateSnapshot()
    KeyboardLog.echo(
      "MARKER provider.requestStart.posted sharedActive=\(state.active) sharedReady=\(state.ready) sharedWarm=\(state.warmMic) stopReq=\(state.stopRequested)"
    )
  }

  func recordingStateSnapshot() -> (active: String, ready: String, stopRequested: String, warmMic: String) {
    guard let defaults = Self.sharedDefaults else {
      return ("?", "?", "?", "?")
    }
    return (
      defaults.string(forKey: recordingActiveKey) ?? "-",
      defaults.string(forKey: backgroundSessionReadyKey) ?? "-",
      defaults.string(forKey: stopRequestedKey) ?? "-",
      defaults.string(forKey: backgroundSessionWarmMicKey) ?? "-"
    )
  }

  func transcriptionStatus() -> String? {
    guard let defaults = Self.sharedDefaults else { return nil }
    return defaults.string(forKey: transcriptionStatusKey)
  }

  /// The error detail riding alongside an error status: `usage_limit`,
  /// `session_expired`, or a free-form message.
  func transcriptionError() -> String? {
    Self.sharedDefaults?.string(forKey: transcriptionErrorKey)
  }

  /// Milliseconds since the shared transcription status last changed, or nil
  /// when no writer has stamped it (e.g. right after the app reset state).
  func transcriptionStatusAgeMs() -> Int? {
    guard let defaults = Self.sharedDefaults,
          let raw = defaults.string(forKey: transcriptionStatusUpdatedAtMsKey),
          let updatedAtMs = Double(raw) else { return nil }
    return Int(Date().timeIntervalSince1970 * 1000 - updatedAtMs)
  }

  func clearTranscriptionStatus() {
    guard let defaults = Self.sharedDefaults else { return }
    defaults.set("idle", forKey: transcriptionStatusKey)
    defaults.removeObject(forKey: transcriptionErrorKey)
  }

  /// Stamped on every Activate tap so the main app can recover the handoff if
  /// the deep link itself never arrives (cold-launch getInitialURL race).
  func markHandoffIntent() {
    guard let defaults = Self.sharedDefaults else { return }
    defaults.set(String(Int(Date().timeIntervalSince1970 * 1000)), forKey: handoffIntentAtMsKey)
    defaults.synchronize()
    KeyboardLog.echo("MARKER provider.markHandoffIntent")
  }

  private func postDarwinNotification(_ name: String) {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    CFNotificationCenterPostNotification(
      center,
      CFNotificationName(name as CFString),
      nil,
      nil,
      true
    )
  }
}

extension KeyboardViewController: UIInputViewAudioFeedback {
  var enableInputClicksWhenVisible: Bool { true }
}
