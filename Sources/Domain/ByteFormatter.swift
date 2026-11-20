import Foundation

enum ByteFormatter {
    private static let countFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    static func format(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 Б" }
        return countFormatter.string(fromByteCount: bytes)
    }
}
