import UIKit
import Photos

struct ImageDeliveryInfo: Sendable {
    let isDegraded: Bool
    let isInCloud: Bool
    let hasError: Bool
}

@MainActor
final class ImageCacheManager {
    static let shared = ImageCacheManager()

    private let cachingManager: PHCachingImageManager

    private init() {
        let manager = PHCachingImageManager()
        manager.allowsCachingHighQualityImages = true
        self.cachingManager = manager
    }

    // MARK: - Расчёт размера с потолком 2048 px

    /// Рассчитывает точный targetSize с учётом displayScale и безопасным потолком 2048px по длинной стороне
    static func targetSize(for containerSize: CGSize, displayScale: CGFloat) -> CGSize {
        let rawWidth = max(containerSize.width * displayScale, 1)
        let rawHeight = max(containerSize.height * displayScale, 1)
        let longestSide = max(rawWidth, rawHeight)

        // КРАСНАЯ ЛИНИЯ: не запрашивать PHImageManagerMaximumSize во избежание OOM на 48 МП ProRAW
        if longestSide > 2048 {
            let scale = 2048.0 / longestSide
            return CGSize(width: (rawWidth * scale).rounded(), height: (rawHeight * scale).rounded())
        }
        return CGSize(width: rawWidth.rounded(), height: rawHeight.rounded())
    }

    // MARK: - Оппортунистический запрос изображения (БЕЗ CheckedContinuation!)

    /// Запрос изображения через callback-замыкание.
    /// КРАСНАЯ ЛИНИЯ: Строго запрещено оборачивать deliveryMode = .opportunistic в withCheckedContinuation!
    @discardableResult
    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill,
        progressHandler: ((Double) -> Void)? = nil,
        resultHandler: @escaping @MainActor (UIImage?, ImageDeliveryInfo) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        if let progressHandler = progressHandler {
            options.progressHandler = { progress, _, _, _ in
                DispatchQueue.main.async {
                    progressHandler(progress)
                }
            }
        }

        return cachingManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { [weak self] image, info in
            guard self != nil else { return }

            // Игнорируем отменённые запросы
            let isCancelled = (info?[PHImageCancelledKey] as? NSNumber)?.boolValue ?? false
            guard !isCancelled else { return }

            let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
            let isInCloud = (info?[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue ?? false
            let hasError = (info?[PHImageErrorKey] != nil)

            let deliveryInfo = ImageDeliveryInfo(
                isDegraded: isDegraded,
                isInCloud: isInCloud,
                hasError: hasError
            )

            if Thread.isMainThread {
                resultHandler(image, deliveryInfo)
            } else {
                DispatchQueue.main.async {
                    resultHandler(image, deliveryInfo)
                }
            }
        }
    }

    // MARK: - Отмена запроса

    func cancelRequest(id: PHImageRequestID) {
        cachingManager.cancelImageRequest(id)
    }

    // MARK: - Prefetching (startCaching / stopCaching)

    /// Запуск упреждающего кэширования для следующих карточек
    func startCaching(
        for assets: [PHAsset],
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill
    ) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        cachingManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        )
    }

    /// Остановка упреждающего кэширования для пройденных карточек
    func stopCaching(
        for assets: [PHAsset],
        targetSize: CGSize,
        contentMode: PHImageContentMode = .aspectFill
    ) {
        guard !assets.isEmpty else { return }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        cachingManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        )
    }

    /// Полный сброс кэша
    func stopCachingForAllAssets() {
        cachingManager.stopCachingImagesForAllAssets()
    }
}
