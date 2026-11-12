import AppIntents
import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Power button inside the Live Activity. Runs in the app's process (LiveActivityIntent),
/// so it works even when the app is backgrounded. Flips the dictation-mode flag off and
/// posts the shared Darwin notification; the in-process observers end the badge
/// (LiveActivityController) and release the warm mic (AppGroupStorageModule).
@available(iOS 17.0, *)
struct ToggleDictationModeIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Diktovka rejimini o'chirish"
  static var description = IntentDescription("Gapla diktovka rejimini o'chirib qo'yadi.")

  func perform() async throws -> some IntentResult {
    let bundleId = Bundle.main.bundleIdentifier ?? "com.gizmolabs.openwhispr"
    UserDefaults(suiteName: "group.\(bundleId)")?.set("0", forKey: "dictation_mode_enabled")

    let name = "\(bundleId).dictationModeChanged" as CFString
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(name), nil, nil, true)

    return .result()
  }
}
