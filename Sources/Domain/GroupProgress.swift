import Foundation

struct GroupProgress: Equatable, Sendable {
    let totalCount: Int
    let keptCount: Int
    let stagedCount: Int
    let stagedBytes: Int64

    var reviewedCount: Int { keptCount + stagedCount }
    var remainingCount: Int { max(0, totalCount - reviewedCount) }
    var completionRatio: Double {
        guard totalCount > 0 else { return 1.0 }
        return Double(reviewedCount) / Double(totalCount)
    }
    var isCompleted: Bool { totalCount > 0 && remainingCount == 0 }
}
