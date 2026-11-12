import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

private let recordingRed = Color(red: 1.0, green: 0.27, blue: 0.23)
// Gapla mandarini (G54): qora (60%) faoliyat fonida chegara chizig'i — kompyuter va ilova bilan bir xil.
private let brandAccent = Color(red: 1.0, green: 0x94 / 255, blue: 0x47 / 255)
// Ilova belgisi foni — iliq grafit #1C1917.
private let gaplaGraphite = Color(red: 0x1C / 255, green: 0x19 / 255, blue: 0x17 / 255)
// Timer text reserves the width of the widest value in its range, and a meeting
// activity never outlives ActivityKit's cap, so it never needs "23:59:59".
private let meetingTimerSpan = RecordingActivityContentState.maxActivityDuration

// MARK: - Brand mark

/// Gapla belgisining bo'laklari ilova belgisining 1024 birlikli to'rida, belgiga qirqilgan (x 195–831,
/// y 301–722) — src/components/ui/OpenWhisprMark.tsx bilan bir xil: I-kursor va 4 ta ovoz chizig'i.
private enum GaplaMarkGeometry {
  static let origin = CGPoint(x: 195, y: 301)
  static let size = CGSize(width: 636, height: 421)
  static let cursor: [CGRect] = [
    CGRect(x: 195, y: 301, width: 165, height: 55),
    CGRect(x: 250, y: 301, width: 55, height: 421),
    CGRect(x: 195, y: 667, width: 165, height: 55),
  ]
  static let bars: [CGRect] = [
    CGRect(x: 431, y: 449, width: 55, height: 126),
    CGRect(x: 546, y: 390, width: 55, height: 244),
    CGRect(x: 661, y: 390, width: 55, height: 244),
    CGRect(x: 776, y: 449, width: 55, height: 126),
  ]
}

/// Berilgan to'rtburchaklarni belgining o'lchamiga moslab, markazga qo'yib chizadi.
private struct GaplaMarkPart: Shape {
  let rects: [CGRect]

  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width / GaplaMarkGeometry.size.width, rect.height / GaplaMarkGeometry.size.height)
    let dx = rect.minX + (rect.width - GaplaMarkGeometry.size.width * scale) / 2
    let dy = rect.minY + (rect.height - GaplaMarkGeometry.size.height * scale) / 2
    var path = Path()
    for r in rects {
      path.addRect(
        CGRect(
          x: dx + (r.minX - GaplaMarkGeometry.origin.x) * scale,
          y: dy + (r.minY - GaplaMarkGeometry.origin.y) * scale,
          width: r.width * scale,
          height: r.height * scale
        )
      )
    }
    return path
  }
}

/// Gapla belgisi: mandarin kursor va oq chiziqlar — ilova belgisidagidek.
struct BrandMark: View {
  var cursorColor: Color = brandAccent
  var color: Color = .white

  var body: some View {
    ZStack {
      GaplaMarkPart(rects: GaplaMarkGeometry.cursor).fill(cursorColor)
      GaplaMarkPart(rects: GaplaMarkGeometry.bars).fill(color)
    }
  }
}

/// Ilova belgisi kabi plitka: iliq grafit fon ustida Gapla belgisi.
struct BrandBadge: View {
  var size: CGFloat

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        .fill(gaplaGraphite)
      BrandMark()
        .frame(width: size * 0.62, height: size * 0.62)
    }
    .frame(width: size, height: size)
  }
}

struct ElapsedText: View {
  let startedAt: Date
  var color: Color = .white
  var span: TimeInterval = 60 * 60 * 24

  var body: some View {
    Text(timerInterval: startedAt...startedAt.addingTimeInterval(span), countsDown: false)
      .monospacedDigit()
      .font(.system(size: 15, weight: .semibold))
      .foregroundColor(color)
  }
}

struct RecordingDot: View {
  var size: CGFloat = 7

  var body: some View {
    Circle().fill(recordingRed).frame(width: size, height: size)
  }
}

// MARK: - Power button (turn dictation mode off)

struct PowerButton: View {
  var size: CGFloat = 30

  var body: some View {
    if #available(iOS 17.0, *) {
      Button(intent: ToggleDictationModeIntent()) {
        glyph
      }
      .buttonStyle(.plain)
    } else {
      glyph
    }
  }

  private var glyph: some View {
    Image(systemName: "power")
      .font(.system(size: size * 0.62, weight: .semibold))
      .foregroundColor(.white)
      .frame(width: size, height: size)
      .background(Circle().fill(Color.white.opacity(0.16)))
  }
}

// MARK: - End button (stop the meeting recording)

/// Same translucent material as PowerButton. Omitted before iOS 17, where
/// `Button(intent:)` doesn't exist; tapping the card still opens the app.
struct EndButton: View {
  var body: some View {
    if #available(iOS 17.0, *) {
      Button(intent: EndMeetingIntent()) {
        Text("Tugatish")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white)
          .padding(.horizontal, 18)
          .padding(.vertical, 8)
          .background(Capsule().fill(Color.white.opacity(0.16)))
      }
      .buttonStyle(.plain)
    }
  }
}

// MARK: - Lock screen / banner

struct RecordingLockScreenView: View {
  let state: RecordingActivityAttributes.ContentState

  var body: some View {
    HStack(spacing: 12) {
      BrandBadge(size: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text("Gapla")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white)
        if state.phase == .recording {
          HStack(spacing: 5) {
            RecordingDot()
            Text("Yozilmoqda")
              .font(.system(size: 13))
              .foregroundColor(.white.opacity(0.6))
          }
        } else {
          Text("Diktovka rejimi yoqilgan")
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.6))
        }
      }
      Spacer()
      if state.phase == .recording {
        ElapsedText(startedAt: state.startedAt, color: .white.opacity(0.85))
      }
      PowerButton(size: 34)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

struct MeetingLockScreenView: View {
  let state: RecordingActivityAttributes.ContentState

  var body: some View {
    HStack(spacing: 12) {
      BrandBadge(size: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text(state.displayTitle)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.white)
          .lineLimit(1)
        MeetingSubtitle(state: state, size: 13)
      }
      Spacer(minLength: 8)
      if state.phase == .recording {
        EndButton()
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

struct MeetingSubtitle: View {
  let state: RecordingActivityAttributes.ContentState
  var size: CGFloat

  var body: some View {
    if state.phase == .processing {
      Text("Yozib olindi: \(state.recordedDurationLabel)")
        .font(.system(size: size))
        .foregroundColor(.white.opacity(0.6))
    } else {
      HStack(spacing: 5) {
        RecordingDot(size: size * 0.54)
        (Text("Yozilmoqda · ")
          + Text(
            timerInterval: state.startedAt...state.startedAt.addingTimeInterval(meetingTimerSpan),
            countsDown: false))
          .monospacedDigit()
          .font(.system(size: size))
          .foregroundColor(.white.opacity(0.6))
      }
    }
  }
}

// MARK: - Widget

@main
struct OpenWhisprActivityBundle: WidgetBundle {
  var body: some Widget {
    RecordingLiveActivity()
  }
}

struct RecordingLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
      Group {
        if context.state.mode == .meeting {
          MeetingLockScreenView(state: context.state)
        } else {
          RecordingLockScreenView(state: context.state)
        }
      }
      .activityBackgroundTint(Color.black.opacity(0.6))
      .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      if context.state.mode == .meeting {
        return meetingIsland(context.state)
      }
      return dictationIsland(context.state)
    }
  }

  private func dictationIsland(_ state: RecordingActivityAttributes.ContentState) -> DynamicIsland {
    DynamicIsland {
      DynamicIslandExpandedRegion(.leading) {
        HStack(spacing: 10) {
          BrandBadge(size: 34)
          VStack(alignment: .leading, spacing: 1) {
            Text("Gapla")
              .font(.system(size: 14, weight: .semibold))
              .foregroundColor(.white)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            Text(state.phase == .recording ? "Yozilmoqda" : "Yoqilgan")
              .font(.system(size: 12))
              .foregroundColor(.white.opacity(0.6))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
        }
      }
      DynamicIslandExpandedRegion(.trailing) {
        HStack(spacing: 8) {
          if state.phase == .recording {
            ElapsedText(startedAt: state.startedAt, color: .white.opacity(0.7))
          }
          PowerButton(size: 30)
        }
      }
    } compactLeading: {
      BrandBadge(size: 22)
    } compactTrailing: {
      if state.phase == .recording {
        ElapsedText(startedAt: state.startedAt)
          .frame(maxWidth: 44)
      }
    } minimal: {
      BrandBadge(size: 22)
    }
    .keylineTint(brandAccent)
  }

  private func meetingIsland(_ state: RecordingActivityAttributes.ContentState) -> DynamicIsland {
    DynamicIsland {
      DynamicIslandExpandedRegion(.leading) {
        HStack(spacing: 10) {
          BrandBadge(size: 34)
          VStack(alignment: .leading, spacing: 1) {
            Text(state.displayTitle)
              .font(.system(size: 14, weight: .semibold))
              .foregroundColor(.white)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            MeetingSubtitle(state: state, size: 12)
          }
        }
      }
      DynamicIslandExpandedRegion(.trailing) {
        if state.phase == .recording {
          EndButton()
        }
      }
    } compactLeading: {
      BrandBadge(size: 22)
    } compactTrailing: {
      if state.phase == .recording {
        // Meetings run past an hour, and "1:02:03" is wider than the 44 pt slot.
        ElapsedText(startedAt: state.startedAt, color: recordingRed, span: meetingTimerSpan)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .frame(maxWidth: 44)
      } else {
        Image(systemName: "waveform")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.white.opacity(0.6))
      }
    } minimal: {
      BrandBadge(size: 22)
    }
    .keylineTint(brandAccent)
  }
}
