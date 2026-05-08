import SwiftUI

// MARK: - DeltaCaption

enum DeltaUnit {
    case seconds, points
}

struct DeltaCaption: View {
    let delta: Double
    let unit: DeltaUnit
    let hasComparison: Bool

    private var isPositive: Bool { delta >= 0 }
    private var arrow: String { isPositive ? "↑" : "↓" }
    private var color: Color { isPositive ? TierColors.color(for: 1) : TierColors.color(for: -1) }

    private var formattedDelta: String {
        switch unit {
        case .seconds:
            return DurationFormatter.string(from: abs(delta))
        case .points:
            return "\(Int(abs(delta)))pts"
        }
    }

    var body: some View {
        if !hasComparison {
            Text("No data for previous day")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else if delta == 0 {
            Text("Same as yesterday")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("\(arrow) \(formattedDelta) vs yesterday")
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
                hasComparison: hasComparison
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

// MARK: - AppListRow

struct AppListRow: View {
    let appName: String
    let seconds: Double
    let totalSeconds: Double
    let tierTint: Color?

    init(appName: String, seconds: Double, totalSeconds: Double, tierTint: Color? = nil) {
        self.appName = appName
        self.seconds = seconds
        self.totalSeconds = totalSeconds
        self.tierTint = tierTint
    }

    private var percent: Int {
        guard totalSeconds > 0 else { return 0 }
        return Int((seconds / totalSeconds * 100).rounded())
    }

    var body: some View {
        HStack(spacing: 6) {
            if let tint = tierTint {
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 3, height: 14)
            }
            Text(appName)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Text(DurationFormatter.string(from: seconds))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
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
