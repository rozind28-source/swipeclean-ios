import Foundation
import Photos

/// Потокобезопасный актор для ленивого расчёта и кэширования размера медиафайлов в RAM.
/// КРАСНАЯ ЛИНИЯ: Никаких массовых вызовов PHAssetResource на 50 000 файлах!
/// Используется лениво: для текущей карточки свайпа, следующих 5 карточек и для файлов в корзине.
actor MediaSizeCalculator {
    static let shared = MediaSizeCalculator()

    // O(1) RAM-кэш вычисленных размеров [localIdentifier: bytes]
    private var cache: [String: Int64] = [:]

    // Селектор для безопасной проверки наличия приватного свойства fileSize в PHAssetResource
    private static let fileSizeSelector = NSSelectorFromString("fileSize")

    private init() {}

    // MARK: - Безопасное извлечение размера ресурса

    /// КРАСНАЯ ЛИНИЯ: обращение к fileSize строго через responds(to:) и приведение к NSNumber
    private static func safeResourceSize(_ resource: PHAssetResource) -> Int64 {
        guard resource.responds(to: fileSizeSelector),
              let number = resource.value(forKey: "fileSize") as? NSNumber else { return 0 }
        return number.int64Value
    }

    // MARK: - Ленивый расчёт размера для ассета

    /// Возвращает размер файла в байтах.
    /// Если значение уже закэшировано в RAM — возвращает его мгновенно за O(1).
    func size(for asset: PHAsset) -> Int64 {
        let identifier = asset.localIdentifier
        if let cached = cache[identifier] {
            return cached
        }

        let resources = PHAssetResource.assetResources(for: asset)
        var totalBytes: Int64 = 0
        for resource in resources {
            totalBytes += Self.safeResourceSize(resource)
        }

        cache[identifier] = totalBytes
        return totalBytes
    }

    /// Быстрое чтение размера из RAM без обращения к PhotoKit
    func cachedSize(for localIdentifier: String) -> Int64? {
        cache[localIdentifier]
    }

    /// Принудительная запись значения в кэш
    func setCachedSize(_ size: Int64, for localIdentifier: String) {
        cache[localIdentifier] = size
    }

    /// Удаление отдельного элемента из кэша
    func removeSize(for localIdentifier: String) {
        cache.removeValue(forKey: localIdentifier)
    }

    /// Очистка всего кэша
    func clearCache() {
        cache.removeAll()
    }
}
