import Foundation
import Observation

@Observable
final class TodayAggregate {
    var topApps: [(name: String, seconds: Double)] = []
    var totalActiveSeconds: Double = 0
}
