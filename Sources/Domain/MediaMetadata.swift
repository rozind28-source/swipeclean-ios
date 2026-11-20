import Foundation

enum MediaKind: String, Sendable {
    case photo, livePhoto, screenshot, video
}

struct MediaMetadata: Identifiable, Hashable, Sendable {
    let localIdentifier: String
    let creationDate: Date?
    let kind: MediaKind
    let duration: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
    var isFavorite: Bool

    var id: String { localIdentifier }
    var isVideo: Bool { kind == .video }

    /// Мгновенная эвристика «тяжести» видео в RAM без обращения к PHAssetResource
    var estimatedWeightScore: Double {
        duration * Double(max(pixelWidth, 1) * max(pixelHeight, 1))
    }
}
