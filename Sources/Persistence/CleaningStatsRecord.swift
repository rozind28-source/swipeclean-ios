import Foundation
import SwiftData

struct StatsSnapshot: Equatable, Sendable {
    let totalReviewedCount: Int
    let totalDeletedCount: Int
    let totalBytesFreed: Int64
    static let empty = StatsSnapshot(totalReviewedCount: 0, totalDeletedCount: 0, totalBytesFreed: 0)
}

@Model
final class CleaningStatsRecord {
    @Attribute(.unique)
    var id: String
    var totalReviewedCount: Int
    var totalDeletedCount: Int
    var totalBytesFreed: Int64
    var lastUpdated: Date

    init(
        id: String = "global_stats",
        totalReviewedCount: Int = 0,
        totalDeletedCount: Int = 0,
        totalBytesFreed: Int64 = 0,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.totalReviewedCount = totalReviewedCount
        self.totalDeletedCount = totalDeletedCount
        self.totalBytesFreed = totalBytesFreed
        self.lastUpdated = lastUpdated
    }

    var snapshot: StatsSnapshot {
        StatsSnapshot(
            totalReviewedCount: totalReviewedCount,
            totalDeletedCount: totalDeletedCount,
            totalBytesFreed: totalBytesFreed
        )
    }
}
