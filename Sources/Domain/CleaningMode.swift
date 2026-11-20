import Foundation

enum CleaningMode: String, CaseIterable, Identifiable, Sendable {
    case months     // "Месяцы"
    case albums     // "Альбомы"
    case smart      // "Подборки"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .months:
            return "Месяцы"
        case .albums:
            return "Альбомы"
        case .smart:
            return "Подборки"
        }
    }
}
