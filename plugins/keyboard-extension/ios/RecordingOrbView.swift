import Accelerate
import QuartzCore
import UIKit

/// Gapla (G47): the recording orb the owner chose — [so'zlari: bilim/gapla-goyalar-royxati.md].
/// 190 particles on a Fibonacci sphere turn slowly; the voice ripples the surface softly (shape)
/// and tints it at once (colour). No background; the seconds sit under the sphere on a dark pad.
///
/// Every value is the shared sample's, unchanged: bilim/gapla-yozish-animatsiyasi-tanlov.md, a
/// port of its `sphere("spin", …)` with bgMode "none" and the "O'rta" speed. Units are points.
///
/// One CALayer per particle (position, size, colour and opacity set each frame) instead of a
/// bitmap redrawn each frame, so the keyboard extension's memory stays flat; one CADisplayLink
/// at 60 fps drives it.
final class RecordingOrbView: UIView {
  enum Stage { case idle, recording, processing, done }

  private(set) var stage: Stage = .idle
  /// Recording or processing and not yet ending: the circle still takes taps.
  var isActive: Bool { (stage == .recording || stage == .processing) && leaveStart == nil }
  var isShowing: Bool { stage != .idle }
  /// Called once, half-way through the final shrink: the keys come back then (the sample keeps
  /// the keys dimmed while its vanish factor is above 0.5).
  var onKeysReturn: (() -> Void)?
  /// One line per orb run: frames, frame rate, worst frame, memory footprint.
  var onStats: ((String) -> Void)?
  /// VoiceOver double-tap (the circle's own action: send).
  var onAccessibilityActivate: (() -> Bool)?
  /// The orb's centre under the view's centre. The sample puts it 16 px below the keyboard's
  /// middle, clearing the toolbar.
  var centerOffsetY: CGFloat = 16
  /// Where the voice comes from while recording (the app's level in the App Group), read at
  /// most every 40 ms — the sample's chunk.
  var levelSource: (() -> CGFloat)?
  /// Test voice (bilim/gapla-yozish-animatsiyasi-tanlov.md, «Sinov ovozi rejimi»): the sample
  /// page's own voice instead of the microphone, so the phone can be put next to the page.
  /// Read at `begin()`.
  var usesTestVoice = false

  // MARK: - The sample's values

  private enum K {
    static let radius = 36.0 // R
    static let tapRadius: CGFloat = 54 // 1.5·R: the circle the sample draws in its other modes
    static let spinRate = 0.26 // rad/s about Y
    static let tilt = 0.45 // rad about X
    /// ls and lf, per 1/60 s whatever the frame rate (60 Hz, 120 Hz ProMotion). The page's code
    /// applies 0.045 and 0.35 once per browser frame; the owner judged it on a 165–180 Hz
    /// screen, where that is 0.12 and 0.70 per 1/60 s — the sample's values since 2026-11-11
    /// («Kadr tezligi»). His words: [so'zlari: bilim/gapla-goyalar-royxati.md].
    static let shapeSmoothing = 0.12 // ls
    static let colourSmoothing = 0.70 // lf (at once)
    static let levelReadInterval = 0.04 // the sample's ~30–50 ms chunk
    static let appearDuration = 0.52
    static let appearCap = 1.06
    static let processRamp = 1.7 // the processing stage's k runs 0 → 1 over 1.7 s
    static let doneDuration = 0.9
    static let leaveDuration = 0.4
    static let infoY = 1.42 * 36.0 // the seconds and the dots: centre + 1.42·R
    static let labelSize: CGFloat = 11.52 // max(10, 0.32·R)
    static let dotSize = 2.52 // max(1.5, 0.07·R)
    static let badgeRadius = 0.62 * 36.0
    static let checkSize = 0.42 * 36.0
  }

  private typealias RGB = (r: Double, g: Double, b: Double)
  private static let cyan: RGB = (62, 240, 255)
  private static let blue: RGB = (76, 125, 255)
  private static let violet: RGB = (139, 92, 246)
  private static let pink: RGB = (236, 72, 200)
  private static let white: RGB = (235, 245, 255)
  private static let padColor = UIColor(red: 7 / 255, green: 10 / 255, blue: 20 / 255, alpha: 0.78)

  private struct Particle {
    let x, y, z, lat, lon, twinkle: Double
  }

  /// The sample's sphere: Fibonacci points and its seeded generator, in the same order.
  private static let particles: [Particle] = {
    var seed = 7.0
    func rnd() -> Double {
      seed = (seed * 9301 + 49297).truncatingRemainder(dividingBy: 233280)
      return seed / 233280
    }
    let count = 190
    let golden = Double.pi * (3 - 5.0.squareRoot())
    return (0..<count).map { (i: Int) -> Particle in
      let y = 1 - Double(i) / Double(count - 1) * 2
      let r = max(0, 1 - y * y).squareRoot()
      let theta = golden * Double(i)
      let x = cos(theta) * r
      let z = sin(theta) * r
      _ = rnd() // the sample draws `r` (used by its other variants) before `tw`
      let twinkle = rnd() * 6.28
      return Particle(x: x, y: y, z: z, lat: asin(y), lon: atan2(z, x), twinkle: twinkle)
    }
  }()

  // MARK: - Layers

  private let particleLayer = CALayer()
  private var dots: [CALayer] = []
  /// The seconds, the waiting dots, the badge and the tick: scaled with the orb around its centre.
  private let infoView = UIView()
  private let timePad = UIView()
  private let timeLabel = UILabel()
  private let dotsPad = UIView()
  private var waitDots: [CALayer] = []
  private let badgeFill = CAShapeLayer()
  private let badgeRing = CAShapeLayer()
  private let checkLayer = CAShapeLayer()

  // MARK: - State

  private var displayLink: CADisplayLink?
  private var startTime: CFTimeInterval = 0
  private var stageStart: CFTimeInterval = 0
  private var leaveStart: CFTimeInterval?
  private var lastFrame: CFTimeInterval?
  private var recordedSeconds: Double = 0
  private var levelTarget = 0.0
  private var lastLevelRead: CFTimeInterval = 0
  /// Every level the orb took this run (one per 40 ms, at most a minute), for the stats line:
  /// the sample's check compares its mean, median, 90th percentile and top.
  private var levelSamples: [Double] = []
  private var ls = 0.0
  private var lf = 0.0
  private var keysReturned = false
  private var completion: (() -> Void)?
  private var shownSeconds = -1

  /// Where `done` starts from: the processing stage's values at the moment the text arrived.
  /// The sample always reaches them (its processing lasts 1.7 s); a faster server must not jump.
  private struct From { var q = 0.35, spin = 1.2, shrink = 0.8, label = 0.0, dots = 1.0 }
  private var from = From()

  private var frames = 0
  private var frameTimeTotal: CFTimeInterval = 0
  private var worstFrame: CFTimeInterval = 0
  private var slowFrames = 0
  private var renderTimeTotal: CFTimeInterval = 0
  private var worstRender: CFTimeInterval = 0
  private var lastTimestamp: CFTimeInterval?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isUserInteractionEnabled = false
    isHidden = true

    particleLayer.shadowColor = UIColor(red: 0, green: 8 / 255, blue: 30 / 255, alpha: 1).cgColor
    particleLayer.shadowOpacity = 0.45
    particleLayer.shadowRadius = 1 // canvas shadowBlur 2 = σ 1
    particleLayer.shadowOffset = .zero
    layer.addSublayer(particleLayer)
    dots = Self.particles.map { _ -> CALayer in
      let dot = CALayer()
      dot.bounds = CGRect(x: 0, y: 0, width: 2, height: 2)
      dot.cornerRadius = 1
      particleLayer.addSublayer(dot)
      return dot
    }

    infoView.isUserInteractionEnabled = false
    infoView.bounds = CGRect(x: -88, y: -88, width: 176, height: 176) // (0, 0) is the centre
    addSubview(infoView)

    timePad.backgroundColor = Self.padColor
    timePad.layer.cornerRadius = K.labelSize * 0.75
    infoView.addSubview(timePad)
    timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: K.labelSize, weight: .semibold)
    timeLabel.textColor = UIColor(red: 0xF4 / 255, green: 0xFB / 255, blue: 0xFF / 255, alpha: 1)
    timeLabel.textAlignment = .center
    timeLabel.layer.shadowOpacity = 0.9
    timeLabel.layer.shadowRadius = K.labelSize * 0.6 / 2
    timeLabel.layer.shadowOffset = .zero
    timePad.addSubview(timeLabel)

    let s = CGFloat(K.dotSize)
    dotsPad.backgroundColor = Self.padColor
    dotsPad.bounds = CGRect(x: 0, y: 0, width: s * 9.2, height: s * 4.4)
    dotsPad.layer.cornerRadius = s * 2.2
    dotsPad.center = CGPoint(x: 0, y: K.infoY)
    dotsPad.alpha = 0
    infoView.addSubview(dotsPad)
    waitDots = (0..<3).map { (i: Int) -> CALayer in
      let dot = CALayer()
      dot.bounds = CGRect(x: 0, y: 0, width: s * 2, height: s * 2)
      dot.cornerRadius = s
      dot.position = CGPoint(x: s * 4.6 + CGFloat(i - 1) * s * 2.6, y: s * 2.2)
      dotsPad.layer.addSublayer(dot)
      return dot
    }

    badgeFill.fillColor = UIColor(red: 7 / 255, green: 10 / 255, blue: 20 / 255, alpha: 0.9).cgColor
    badgeFill.shadowColor = UIColor.black.cgColor
    badgeFill.shadowOpacity = 0.27 // rgba(0,0,0,.3) under a fill of alpha .9
    badgeFill.shadowRadius = CGFloat(K.radius * 0.3 / 2)
    badgeFill.shadowOffset = CGSize(width: 0, height: K.radius * 0.06)
    badgeRing.fillColor = nil
    badgeRing.lineWidth = 1.5
    let c = K.checkSize
    let check = UIBezierPath()
    check.move(to: CGPoint(x: -c * 0.45, y: c * 0.02))
    check.addLine(to: CGPoint(x: -c * 0.1, y: c * 0.36))
    check.addLine(to: CGPoint(x: c * 0.5, y: -c * 0.32))
    checkLayer.path = check.cgPath
    checkLayer.fillColor = nil
    checkLayer.strokeColor = Self.cgColor(Self.white, 1)
    checkLayer.lineWidth = CGFloat(max(2, c * 0.16))
    checkLayer.lineCap = .round
    checkLayer.lineJoin = .round
    checkLayer.shadowColor = Self.cgColor(Self.cyan, 1)
    checkLayer.shadowOpacity = 1
    checkLayer.shadowRadius = CGFloat(c * 0.7 / 2)
    checkLayer.shadowOffset = .zero
    [badgeFill, badgeRing, checkLayer].forEach {
      $0.isHidden = true
      infoView.layer.addSublayer($0)
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    particleLayer.frame = bounds
    CATransaction.commit()
  }

  // MARK: - Control

  /// Appear (0.52 s, a slight overshoot) and record. A second call while recording keeps going.
  func begin() {
    if stage == .recording, leaveStart == nil { return }
    stopTicking()
    let now = CACurrentMediaTime()
    stage = .recording
    startTime = now
    stageStart = now
    leaveStart = nil
    lastFrame = nil
    recordedSeconds = 0
    levelTarget = 0
    lastLevelRead = 0
    levelSamples.removeAll(keepingCapacity: true)
    ls = 0
    lf = 0
    keysReturned = false
    completion = nil
    shownSeconds = -1
    from = From()
    resetStats()
    isHidden = false
    render(at: now)
    startTicking()
  }

  /// The voice, 0…1. Only the recording stage listens; the test voice ignores it.
  func setLevel(_ level: CGFloat) {
    guard stage == .recording, leaveStart == nil, !usesTestVoice else { return }
    levelTarget = Self.clamp(Double(level), 0, 1)
  }

  /// Recording → processing: the sphere settles and spins until the server answers.
  func process() {
    guard stage == .recording, leaveStart == nil else { return }
    let now = CACurrentMediaTime()
    recordedSeconds = now - startTime
    stage = .processing
    stageStart = now
    levelTarget = 0
  }

  /// The text arrived: done (0.9 s — the sphere gathers in, the tick draws on its badge), then
  /// the 0.4 s shrink, then `completion`.
  func finish(completion: @escaping () -> Void) {
    guard isActive else { return }
    let now = CACurrentMediaTime()
    let values = stageValues(at: now)
    from = From(q: values.q, spin: values.spin, shrink: values.shrink, label: values.label, dots: values.dots)
    if stage == .recording { recordedSeconds = now - startTime }
    stage = .done
    stageStart = now
    leaveStart = now + K.doneDuration
    levelTarget = 0
    self.completion = completion
  }

  /// Cancel or failure: shrink away (0.4 s) from wherever it is, then `completion`.
  func dismiss(completion: @escaping () -> Void) {
    guard isActive else { return }
    if stage == .recording { recordedSeconds = CACurrentMediaTime() - startTime }
    leaveStart = CACurrentMediaTime()
    levelTarget = 0
    self.completion = completion
  }

  /// Gone at once, no callbacks (the keyboard is closing).
  func reset() {
    if isShowing { reportStats() }
    stopTicking()
    stage = .idle
    leaveStart = nil
    completion = nil
    isHidden = true
  }

  func circleContains(_ point: CGPoint) -> Bool {
    let c = orbCenter
    return hypot(point.x - c.x, point.y - c.y) <= K.tapRadius
  }

  // MARK: - Accessibility

  override func accessibilityActivate() -> Bool {
    onAccessibilityActivate?() ?? false
  }

  override var accessibilityFrame: CGRect {
    get {
      let c = orbCenter
      let rect = CGRect(x: c.x - K.tapRadius, y: c.y - K.tapRadius, width: K.tapRadius * 2, height: K.tapRadius * 2)
      return UIAccessibility.convertToScreenCoordinates(rect, in: self)
    }
    set { super.accessibilityFrame = newValue }
  }

  // MARK: - Frames

  private var orbCenter: CGPoint {
    CGPoint(x: bounds.midX, y: bounds.midY + centerOffsetY)
  }

  private func startTicking() {
    guard displayLink == nil else { return }
    let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  private func stopTicking() {
    displayLink?.invalidate()
    displayLink = nil
  }

  fileprivate func tick(_ link: CADisplayLink) {
    if let last = lastTimestamp {
      let interval = link.timestamp - last
      frames += 1
      frameTimeTotal += interval
      worstFrame = max(worstFrame, interval)
      if interval > 1.5 / 60 { slowFrames += 1 }
    }
    lastTimestamp = link.timestamp
    let started = CACurrentMediaTime()
    render(at: link.targetTimestamp)
    let spent = CACurrentMediaTime() - started
    renderTimeTotal += spent
    worstRender = max(worstRender, spent)
  }

  /// q (ripple strength), the extra spin, the shrink and the two caption alphas for a moment.
  private func stageValues(at now: CFTimeInterval) -> (q: Double, spin: Double, shrink: Double, fade: Double, label: Double, dots: Double) {
    switch stage {
    case .idle, .recording:
      return (1, 0, 1, 1, 1, 0)
    case .processing:
      let k = min(1, (now - stageStart) / K.processRamp)
      let tIn = Self.ease(k * 3)
      let a = Self.ease(k * 4)
      return (Self.lerp(1, 0.35, tIn), 1.2 * Self.ease(k), Self.lerp(1, 0.8, tIn), 1, 1 - a, a)
    case .done:
      // k keeps running through the shrink, as on the sample (its helpers clamp).
      let k = (now - stageStart) / K.doneDuration
      let out = 1 - Self.ease(k * 5)
      return (
        from.q * (1 - Self.ease(k * 2)),
        from.spin + 0.5 * Self.ease(k),
        from.shrink * (1 - Self.ease(k * 1.5) * 0.9),
        1 - Self.ease(k * 1.6),
        from.label * out,
        from.dots * out
      )
    }
  }

  private func render(at now: CFTimeInterval) {
    guard stage != .idle else { return }
    let dt = lastFrame.map { min(max(now - $0, 0), 0.1) } ?? 1.0 / 60
    lastFrame = now
    if stage == .recording, leaveStart == nil {
      if usesTestVoice {
        levelTarget = Self.testVoice(at: now - startTime)
      } else if let levelSource, now - lastLevelRead >= K.levelReadInterval {
        lastLevelRead = now
        levelTarget = Self.clamp(Double(levelSource()), 0, 1)
        if levelSamples.count < 1500 { levelSamples.append(levelTarget) }
      }
    }
    let steps = dt * 60
    ls += (levelTarget - ls) * (1 - pow(1 - K.shapeSmoothing, steps))
    lf += (levelTarget - lf) * (1 - pow(1 - K.colourSmoothing, steps))

    var vanish = 1.0
    if let leaveStart, now >= leaveStart {
      let k = (now - leaveStart) / K.leaveDuration
      vanish = 1 - Self.ease(k)
      if vanish <= 0.5, !keysReturned {
        keysReturned = true
        onKeysReturn?()
      }
      if k >= 1 {
        end()
        return
      }
    }

    let t = now - startTime // "O'rta": the sample's speed factor is 1
    let scale = min(Self.back((now - startTime) / K.appearDuration), K.appearCap) * vanish
    let R = K.radius * scale
    let values = stageValues(at: now)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }

    guard R > 2 else {
      particleLayer.isHidden = true
      infoView.isHidden = true
      return
    }
    particleLayer.isHidden = false
    infoView.isHidden = false

    let c = orbCenter
    let ry = t * K.spinRate + values.spin
    let cyr = cos(ry), syr = sin(ry), cxr = cos(K.tilt), sxr = sin(K.tilt)
    let rr = R * 0.9 * values.shrink
    // The voice's share of the ripple: the page's 0.22 × 1.3². The owner (2026-11-12, after
    // trying it on the computer): [so'zlari: bilim/gapla-goyalar-royxati.md] → 0.286; after trying 0.286: «Yana kuchaytir» → 0.372.
    let ripple = (0.04 + ls * 0.372) * values.q
    for (index, p) in Self.particles.enumerated() {
      let disp = 1 + ripple * sin(3 * p.lat + t * 0.8) * cos(2 * p.lon - t * 0.5)
      let x = p.x * disp, y = p.y * disp, z = p.z * disp
      let x1 = x * cyr + z * syr
      let z1 = -x * syr + z * cyr
      let y1 = y * cxr - z1 * sxr
      let z2 = y * sxr + z1 * cxr
      let depth = Self.clamp((z2 + 1) / 2, 0, 1)
      let twinkle = 0.85 + 0.15 * sin(t * 1.5 + p.twinkle)
      let colour = Self.hot(Self.mix(Self.blue, Self.cyan, depth), lf * (0.6 + depth * 0.4))
      let alpha = (0.22 + depth * 0.62 + lf * 0.08) * twinkle * values.fade
      let radius = CGFloat(max(0.3, 0.7 + depth * 1.35))
      let dot = dots[index]
      dot.position = CGPoint(x: c.x + CGFloat(x1 * rr), y: c.y + CGFloat(y1 * rr))
      dot.setAffineTransform(CGAffineTransform(scaleX: radius, y: radius))
      dot.backgroundColor = Self.cgColor(colour, alpha)
    }

    infoView.center = c
    infoView.transform = CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale))
    let glow = Self.hot(Self.cyan, lf)

    timePad.isHidden = values.label <= 0.001
    if !timePad.isHidden {
      timePad.alpha = CGFloat(values.label)
      let seconds = Int(stage == .recording && leaveStart == nil ? t : recordedSeconds)
      if seconds != shownSeconds {
        shownSeconds = seconds
        timeLabel.text = String(format: "%d:%02d", seconds / 60, seconds % 60)
        let width = ceil(timeLabel.intrinsicContentSize.width)
        let height = K.labelSize * 1.5
        timePad.frame = CGRect(x: -(width / 2 + K.labelSize * 0.75), y: CGFloat(K.infoY) - height / 2,
                               width: width + K.labelSize * 1.5, height: height)
        timeLabel.frame = timePad.bounds
      }
      timeLabel.layer.shadowColor = Self.cgColor(glow, 1)
    }

    dotsPad.isHidden = values.dots <= 0.001
    if !dotsPad.isHidden {
      dotsPad.alpha = CGFloat(values.dots)
      for (i, dot) in waitDots.enumerated() {
        let a = 0.35 + 0.65 * max(0, sin(t * 4 - Double(i) * 0.9))
        dot.backgroundColor = Self.cgColor(Self.white, a)
      }
    }

    if stage == .done {
      let k = (now - stageStart) / K.doneDuration
      let br = K.badgeRadius * Self.back(k * 3.2)
      let showBadge = br > 0.5
      badgeFill.isHidden = !showBadge
      badgeRing.isHidden = !showBadge
      if showBadge {
        let circle = CGPath(ellipseIn: CGRect(x: -br, y: -br, width: br * 2, height: br * 2), transform: nil)
        badgeFill.path = circle
        badgeFill.shadowPath = circle
        badgeRing.path = circle
        badgeRing.strokeColor = Self.cgColor(glow, 0.8)
      }
      let drawn = Self.ease(k * 3 - 0.25)
      checkLayer.isHidden = drawn <= 0
      checkLayer.strokeEnd = CGFloat(drawn)
    } else {
      badgeFill.isHidden = true
      badgeRing.isHidden = true
      checkLayer.isHidden = true
    }
  }

  private func end() {
    reportStats()
    stopTicking()
    stage = .idle
    leaveStart = nil
    isHidden = true
    let done = completion
    completion = nil
    done?()
  }

  // MARK: - Measurement (G47 asked to check the extension's memory and frame rate)

  private func resetStats() {
    frames = 0
    frameTimeTotal = 0
    worstFrame = 0
    slowFrames = 0
    renderTimeTotal = 0
    worstRender = 0
    lastTimestamp = nil
  }

  private func reportStats() {
    guard frames > 0, frameTimeTotal > 0 else { return }
    let fps = Double(frames) / frameTimeTotal
    let line = String(
      format: "orb frames=%d fps=%.1f worstFrameMs=%.1f slowFrames=%d renderAvgMs=%.2f renderWorstMs=%.2f footprintMB=%.1f",
      frames, fps, worstFrame * 1000, slowFrames, renderTimeTotal / Double(frames + 1) * 1000,
      worstRender * 1000, Self.footprintMB()
    )
    onStats?(line + " " + levelSummary())
  }

  /// The microphone's levels this run against the sample's check (bilim/…, «Ovoz darajasi
  /// qanday hisoblanadi»: over 10 s of speech mean ~0.23, under 0.1 about half the time, 90th
  /// percentile ~0.7, top 1; silence ≤ 0.05).
  private func levelSummary() -> String {
    if usesTestVoice { return "level=testVoice" }
    guard !levelSamples.isEmpty else { return "level=none" }
    let sorted = levelSamples.sorted()
    let n = sorted.count
    let mean = sorted.reduce(0, +) / Double(n)
    let quiet = Double(sorted.filter { (v: Double) -> Bool in v < 0.1 }.count) / Double(n)
    return String(
      format: "level n=%d mean=%.2f median=%.2f p90=%.2f max=%.2f under0.1=%.0f%%",
      n, mean, sorted[n / 2], sorted[min(n - 1, n * 9 / 10)], sorted[n - 1], quiet * 100
    )
  }

  /// The sample page's test voice, `t` in seconds from the start of recording.
  private static func testVoice(at t: Double) -> Double {
    let syllable = pow(max(0, sin(t * 8.7)), 0.7) * (0.55 + 0.45 * sin(t * 2.1 + 1.3))
    let pause = t.truncatingRemainder(dividingBy: 1.9) > 1.5 ? 0.08 : 1.0
    return clamp(syllable * pause + 0.07 * sin(t * 27) + 0.05, 0.03, 1)
  }

  static func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
  }

  // MARK: - The keys behind the orb

  /// The keys as the orb dims them: a 1x picture blurred by about 1.5 pt (a 7-pixel tent ≈ σ
  /// 1.6), shown at 16 % in their place. A static picture, because UIKit has no live blur of
  /// a chosen radius; 1x keeps it near half a megabyte.
  static func blurredSnapshot(of view: UIView) -> UIImage? {
    let size = view.bounds.size
    guard size.width >= 1, size.height >= 1 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    format.preferredRange = .standard
    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
      if !view.drawHierarchy(in: view.bounds, afterScreenUpdates: false) {
        view.layer.render(in: context.cgContext)
      }
    }
    guard let cgImage = image.cgImage,
          let vFormat = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
              rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
          ),
          var source = try? vImage_Buffer(cgImage: cgImage, format: vFormat)
    else { return image }
    defer { source.free() }
    guard var blurred = try? vImage_Buffer(width: Int(source.width), height: Int(source.height), bitsPerPixel: 32)
    else { return image }
    defer { blurred.free() }
    let error = vImageTentConvolve_ARGB8888(&source, &blurred, nil, 0, 0, 7, 7, nil, vImage_Flags(kvImageEdgeExtend))
    guard error == kvImageNoError, let output = try? blurred.createCGImage(format: vFormat) else { return image }
    return UIImage(cgImage: output, scale: 1, orientation: .up)
  }

  // MARK: - The sample's helpers

  private static func clamp(_ x: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, x)) }
  private static func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }

  private static func ease(_ x: Double) -> Double {
    let x = clamp(x, 0, 1)
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
  }

  private static func back(_ x: Double) -> Double {
    let x = clamp(x, 0, 1)
    let c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
  }

  private static func mix(_ a: RGB, _ b: RGB, _ k: Double) -> RGB {
    let k = clamp(k, 0, 1)
    return (
      (a.r + (b.r - a.r) * k).rounded(),
      (a.g + (b.g - a.g) * k).rounded(),
      (a.b + (b.b - a.b) * k).rounded()
    )
  }

  /// Quiet — cyan and blue; loud — violet, then pink.
  private static func hot(_ c: RGB, _ lf: Double) -> RGB {
    mix(c, lf > 0.55 ? pink : violet, lf * 0.95)
  }

  private static func cgColor(_ c: RGB, _ alpha: Double) -> CGColor {
    CGColor(srgbRed: CGFloat(c.r / 255), green: CGFloat(c.g / 255), blue: CGFloat(c.b / 255),
            alpha: CGFloat(clamp(alpha, 0, 1)))
  }
}

/// CADisplayLink keeps its target alive; this proxy holds the orb weakly.
private final class DisplayLinkProxy: NSObject {
  private weak var owner: RecordingOrbView?

  init(_ owner: RecordingOrbView) {
    self.owner = owner
  }

  @objc func tick(_ link: CADisplayLink) {
    guard let owner else {
      link.invalidate()
      return
    }
    owner.tick(link)
  }
}
