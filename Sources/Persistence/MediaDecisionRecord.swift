import Foundation
import SwiftData

@Model
final class MediaDecisionRecord {
    @Attribute(.unique)
    var assetIdentifier: String
    var statusRaw: String
    var timestamp: Date

    var status: DecisionStatus {
        get {
            DecisionStatus(rawValue: statusRaw) ?? .kept
        }
        set {
            statusRaw = newValue.rawValue
        }
    }

    init(assetIdentifier: String, status: DecisionStatus, timestamp: Date = Date()) {
        self.assetIdentifier = assetIdentifier
        self.statusRaw = status.rawValue
        self.timestamp = timestamp
    }
}
