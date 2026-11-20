import Foundation

struct MediaGroup: Identifiable, Hashable, Sendable {
    let id: String              // Напр. "month-2026-11", "album-<id>", "smart-videos"
    let title: String
    let subtitle: String?
    let mode: CleaningMode
    let assetIDs: [String]      // Только deletable localIdentifier
    let coverAssetID: String?
}
