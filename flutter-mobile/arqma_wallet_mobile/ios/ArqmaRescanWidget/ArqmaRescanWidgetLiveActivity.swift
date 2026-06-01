import ActivityKit
import SwiftUI
import WidgetKit

struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState

  public struct ContentState: Codable, Hashable {}

  var id = UUID()
}

extension LiveActivitiesAppAttributes {
  func prefixedKey(_ key: String) -> String {
    "\(id)_\(key)"
  }
}

private let appGroupId = "group.com.arqma.arqmaWalletMobile"

struct ArqmaRescanWidgetLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      RescanLiveActivityView(context: context)
        .activityBackgroundTint(Color.black.opacity(0.85))
        .activitySystemActionForegroundColor(Color(red: 0.85, green: 0.72, blue: 0.35))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text("ARQ")
            .font(.caption.bold())
            .foregroundStyle(Color(red: 0.85, green: 0.72, blue: 0.35))
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(rescanPct(context))
            .font(.caption.bold())
            .monospacedDigit()
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(rescanSubtitle(context))
            .font(.caption2)
            .lineLimit(2)
        }
      } compactLeading: {
        Image(systemName: "arrow.triangle.2.circlepath")
          .foregroundStyle(Color(red: 0.85, green: 0.72, blue: 0.35))
      } compactTrailing: {
        Text(rescanPct(context))
          .font(.caption2.bold())
          .monospacedDigit()
      } minimal: {
        Text(rescanPctShort(context))
          .font(.caption2.bold())
          .monospacedDigit()
      }
    }
  }
}

private struct RescanLiveActivityView: View {
  let context: ActivityViewContext<LiveActivitiesAppAttributes>

  var body: some View {
    let shared = UserDefaults(suiteName: appGroupId)
    return VStack(alignment: .leading, spacing: 8) {
      Text(shared?.string(forKey: context.attributes.prefixedKey("title")) ?? "Arqma Wallet")
        .font(.headline)
        .foregroundStyle(.white)
      Text(shared?.string(forKey: context.attributes.prefixedKey("subtitle")) ?? "Blockchain rescan")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      ProgressView(value: rescanProgress(shared, context))
        .tint(Color(red: 0.85, green: 0.72, blue: 0.35))
      Text(rescanSubtitle(context))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
  }
}

private func rescanProgress(
  _ shared: UserDefaults?,
  _ context: ActivityViewContext<LiveActivitiesAppAttributes>
) -> Double {
  let pct = shared?.integer(forKey: context.attributes.prefixedKey("pct")) ?? 0
  return Double(min(max(pct, 0), 100)) / 100.0
}

private func rescanPct(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) -> String {
  let shared = UserDefaults(suiteName: appGroupId)
  let pct = shared?.integer(forKey: context.attributes.prefixedKey("pct")) ?? 0
  return "\(min(max(pct, 0), 100))%"
}

private func rescanPctShort(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) -> String {
  let shared = UserDefaults(suiteName: appGroupId)
  let pct = shared?.integer(forKey: context.attributes.prefixedKey("pct")) ?? 0
  return "\(min(max(pct, 0), 100))"
}

private func rescanSubtitle(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) -> String {
  let shared = UserDefaults(suiteName: appGroupId)
  let current = shared?.integer(forKey: context.attributes.prefixedKey("current")) ?? 0
  let target = shared?.integer(forKey: context.attributes.prefixedKey("target")) ?? 0
  if target > 0 {
    return "Block \(current) / \(target)"
  }
  return "Scanning…"
}
