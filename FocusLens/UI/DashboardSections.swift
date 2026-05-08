import SwiftUI
import AppKit

// MARK: - DeltaCaption

enum DeltaUnit {
    case seconds, points
}

struct DeltaCaption: View {
    let delta: Double
    let unit: DeltaUnit
    let hasComparison: Bool
    var comparisonLabel: String = "vs yesterday"

    private var label: String {
        comparisonLabel.replacingOccurrences(of: "vs ", with: "")
    }
    private var isPositive: Bool { delta >= 0 }
    private var arrow: String { isPositive ? "↑" : "↓" }
    private var color: Color { isPositive ? TierColors.color(for: 1) : TierColors.color(for: -1) }

    private var formattedDelta: String {
        switch unit {
        case .seconds: return DurationFormatter.string(from: abs(delta))
        case .points:  return "\(Int(abs(delta)))pts"
        }
    }

    var body: some View {
        if !hasComparison {
            Text("No data for \(label)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else if delta == 0 {
            Text("Same as \(label)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("\(arrow) \(formattedDelta) vs \(label)")
                .font(.caption2)
                .foregroundStyle(color)
        }
    }
}

// MARK: - HeroTimeView

struct HeroTimeView: View {
    let totalSeconds: Double
    let previousSeconds: Double
    let hasComparison: Bool
    var comparisonLabel: String = "vs yesterday"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Time logged")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(DurationFormatter.string(from: totalSeconds))
                .font(.system(size: 34, weight: .bold, design: .rounded))
            DeltaCaption(
                delta: totalSeconds - previousSeconds,
                unit: .seconds,
                hasComparison: hasComparison,
                comparisonLabel: comparisonLabel
            )
        }
    }
}

// MARK: - CategoryPercentRow

struct CategoryPercentRow: View {
    let name: String
    let colorHex: String
    let seconds: Double
    let totalSeconds: Double

    private var percent: Int {
        guard totalSeconds > 0 else { return 0 }
        return Int((seconds / totalSeconds * 100).rounded())
    }

    private var fraction: Double {
        guard totalSeconds > 0 else { return 0 }
        return seconds / totalSeconds
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(percent)%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
                .monospacedDigit()

            Text(name)
                .font(.callout)
                .lineLimit(1)
                .frame(minWidth: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: colorHex) ?? .gray)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 5)

            Text(DurationFormatter.string(from: seconds))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
        .frame(height: 20)
    }
}

// MARK: - WindowTitlePillRow

struct WindowTitlePillRow: View {
    let title: String
    let appName: String
    let seconds: Double
    let tier: Int

    private var displayTitle: String {
        formatWindowTitle(title, appName: appName)
    }

    private var tierColor: Color { TierColors.color(for: tier) }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tierColor)
                .frame(width: 3)
                .padding(.trailing, 6)

            Text(displayTitle)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Text(DurationFormatter.string(from: seconds))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .layoutPriority(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tierColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func formatWindowTitle(_ title: String, appName: String) -> String {
        var result = title
        // Strip trailing " - <appName>" browser suffix (case-insensitive)
        let suffix = " - \(appName)"
        if result.lowercased().hasSuffix(suffix.lowercased()) {
            result = String(result.dropLast(suffix.count))
        }
        return result.isEmpty ? appName : result
    }
}

// MARK: - AppIconCache

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for bundleId: String) -> NSImage? {
        if let hit = cache[bundleId] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleId] = img
        return img
    }
}

// MARK: - AppIcon

struct AppIcon: View {
    let bundleId: String

    private var icon: NSImage? { AppIconCache.shared.icon(for: bundleId) }

    var body: some View {
        Group {
            if let img = icon {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - ExpandableAppRow

struct ExpandableAppRow: View {
    let appName: String
    let appBundleId: String
    let seconds: Double
    let totalSeconds: Double
    let tierTint: Color?
    let windowTitles: [(windowTitle: String, totalSeconds: Double, tier: Int)]

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let tint = tierTint {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: 3, height: 16)
                } else {
                    Spacer().frame(width: 3)
                }

                AppIcon(bundleId: appBundleId)
                    .frame(width: 16, height: 16)

                Text(appName)
                    .font(.callout)
                    .lineLimit(1)

                Spacer()

                Text(DurationFormatter.string(from: seconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if !windowTitles.isEmpty {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                }
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !windowTitles.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(windowTitles.prefix(5), id: \.windowTitle) { entry in
                        WindowTitlePillRow(
                            title: entry.windowTitle,
                            appName: appName,
                            seconds: entry.totalSeconds,
                            tier: entry.tier
                        )
                    }
                }
                .padding(.leading, 25)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
