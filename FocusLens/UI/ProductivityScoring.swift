import Foundation

struct ProductivityScoreResult {
    let categoryBreakdown: [(category: Category, totalSeconds: Double)]
    let score: Int
    let tierBreakdown: [(tier: Int, seconds: Double)]
}

func computeProductivityScore(
    rawBreakdown: [(categoryId: Int64?, totalSeconds: Double)],
    hourlyTierBreakdown: [(hour: Int, tier: Int, seconds: Double)],
    categories: [Category]
) -> ProductivityScoreResult {
    guard !categories.isEmpty else {
        return ProductivityScoreResult(categoryBreakdown: [], score: 50, tierBreakdown: [])
    }

    let categoryMap = Dictionary(uniqueKeysWithValues: categories.compactMap { c -> (Int64, Category)? in
        guard let id = c.id else { return nil }
        return (id, c)
    })

    var breakdown: [(category: Category, totalSeconds: Double)] = []
    var weightedSum: Double = 0
    var categorizedTotal: Double = 0

    for entry in rawBreakdown {
        guard let categoryId = entry.categoryId,
              let category = categoryMap[categoryId] else { continue }
        breakdown.append((category: category, totalSeconds: entry.totalSeconds))
        weightedSum += Double(category.productivityScore) * entry.totalSeconds
        categorizedTotal += entry.totalSeconds
    }

    let sortedBreakdown = breakdown.sorted { $0.totalSeconds > $1.totalSeconds }

    var tierTotals: [Int: Double] = [:]
    for entry in hourlyTierBreakdown {
        tierTotals[entry.tier, default: 0] += entry.seconds
    }
    let tierBreakdown = tierTotals.map { (tier: $0.key, seconds: $0.value) }
        .sorted { $0.tier > $1.tier }

    let score: Int
    if categorizedTotal > 0 {
        let avg = weightedSum / categorizedTotal
        score = max(0, min(100, Int(((avg + 2.0) / 4.0) * 100)))
    } else {
        score = 50
    }

    return ProductivityScoreResult(categoryBreakdown: sortedBreakdown, score: score, tierBreakdown: tierBreakdown)
}

// Variant for range aggregates where hourly breakdown isn't available — derives tier breakdown
// from category-level data instead.
func computeProductivityScoreForRange(
    rawBreakdown: [(categoryId: Int64?, totalSeconds: Double)],
    categories: [Category]
) -> ProductivityScoreResult {
    guard !categories.isEmpty else {
        return ProductivityScoreResult(categoryBreakdown: [], score: 50, tierBreakdown: [])
    }

    let categoryMap = Dictionary(uniqueKeysWithValues: categories.compactMap { c -> (Int64, Category)? in
        guard let id = c.id else { return nil }
        return (id, c)
    })

    var breakdown: [(category: Category, totalSeconds: Double)] = []
    var weightedSum: Double = 0
    var categorizedTotal: Double = 0
    var tierTotals: [Int: Double] = [:]

    for entry in rawBreakdown {
        guard let categoryId = entry.categoryId,
              let category = categoryMap[categoryId] else { continue }
        breakdown.append((category: category, totalSeconds: entry.totalSeconds))
        weightedSum += Double(category.productivityScore) * entry.totalSeconds
        categorizedTotal += entry.totalSeconds
        tierTotals[category.productivityScore, default: 0] += entry.totalSeconds
    }

    let sortedBreakdown = breakdown.sorted { $0.totalSeconds > $1.totalSeconds }
    let tierBreakdown = tierTotals.map { (tier: $0.key, seconds: $0.value) }
        .sorted { $0.tier > $1.tier }

    let score: Int
    if categorizedTotal > 0 {
        let avg = weightedSum / categorizedTotal
        score = max(0, min(100, Int(((avg + 2.0) / 4.0) * 100)))
    } else {
        score = 50
    }

    return ProductivityScoreResult(categoryBreakdown: sortedBreakdown, score: score, tierBreakdown: tierBreakdown)
}
