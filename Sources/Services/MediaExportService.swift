import Foundation
import Photos
import UniformTypeIdentifiers

enum MediaExportError: LocalizedError {
    case assetNotFound
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .assetNotFound:
            return "Файл не найден в медиатеке"
        case .exportFailed(let reason):
            return "Ошибка экспорта: \(reason)"
        case .cancelled:
            return "Экспорт был отменён"
        }
    }
}

/// Сервис экспорта оригиналов фото и видео во временную директорию (tmp/)
/// для передачи в ActivityShareSheet.
/// КРАСНАЯ ЛИНИЯ: Не передавать PHAsset в ShareLink — использовать MediaExportService + ActivityShareSheet.
final class MediaExportService: Sendable {
    static let shared = MediaExportService()

    private init() {}

    // MARK: - Экспорт оригинала (Фото или Видео)

    func exportOriginal(for asset: PHAsset) async throws -> URL {
        if asset.mediaType == .video {
            return try await exportVideo(for: asset)
        } else {
            return try await exportPhoto(for: asset)
        }
    }

    // MARK: - Экспорт Фото

    private func exportPhoto(for asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var hasResumed = false

            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, info in
                lock.lock()
                defer { lock.unlock() }

                guard !hasResumed else { return }

                if let isCancelled = (info?[PHImageCancelledKey] as? NSNumber)?.boolValue, isCancelled {
                    hasResumed = true
                    continuation.resume(throwing: MediaExportError.cancelled)
                    return
                }

                if let error = info?[PHImageErrorKey] as? Error {
                    hasResumed = true
                    continuation.resume(throwing: MediaExportError.exportFailed(error.localizedDescription))
                    return
                }

                guard let data = data else {
                    hasResumed = true
                    continuation.resume(throwing: MediaExportError.exportFailed("Не удалось получить данные фото"))
                    return
                }

                let ext: String
                if let uti = uti, let utType = UTType(uti), let preferredExt = utType.preferredFilenameExtension {
                    ext = preferredExt
                } else {
                    ext = "jpg"
                }

                let filename = "export_\(UUID().uuidString).\(ext)"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

                do {
                    try data.write(to: tempURL, options: .atomic)
                    hasResumed = true
                    continuation.resume(returning: tempURL)
                } catch {
                    hasResumed = true
                    continuation.resume(throwing: MediaExportError.exportFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Экспорт Видео

    private func exportVideo(for asset: PHAsset) async throws -> URL {
        let resources = PHAssetResource.assetResources(for: asset)
        let videoResource = resources.first(where: { $0.type == .video || $0.type == .pairedVideo }) ?? resources.first

        if let resource = videoResource {
            let ext = (resource.originalFilename as NSString).pathExtension
            let finalExt = ext.isEmpty ? "mov" : ext
            let filename = "export_\(UUID().uuidString).\(finalExt)"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            return try await withCheckedThrowingContinuation { continuation in
                let lock = NSLock()
                var hasResumed = false

                PHAssetResourceManager.default().writeData(for: resource, toFile: tempURL, options: options) { error in
                    lock.lock()
                    defer { lock.unlock() }

                    guard !hasResumed else { return }
                    hasResumed = true

                    if let error = error {
                        try? FileManager.default.removeItem(at: tempURL)
                        continuation.resume(throwing: MediaExportError.exportFailed(error.localizedDescription))
                    } else {
                        continuation.resume(returning: tempURL)
                    }
                }
            }
        } else {
            // Резервный экспорт через AVAssetExportSession
            return try await withCheckedThrowingContinuation { continuation in
                let lock = NSLock()
                var hasResumed = false

                let videoOptions = PHVideoRequestOptions()
                videoOptions.isNetworkAccessAllowed = true
                videoOptions.deliveryMode = .highQualityFormat

                PHImageManager.default().requestExportSession(
                    forVideo: asset,
                    options: videoOptions,
                    exportPreset: AVAssetExportPresetPassthrough
                ) { session, info in
                    lock.lock()
                    defer { lock.unlock() }

                    guard !hasResumed else { return }

                    guard let session = session else {
                        hasResumed = true
                        continuation.resume(throwing: MediaExportError.exportFailed("Не удалось создать сессию экспорта видео"))
                        return
                    }

                    let filename = "export_\(UUID().uuidString).mov"
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                    session.outputURL = tempURL
                    session.outputFileType = .mov

                    session.exportAsynchronously {
                        lock.lock()
                        defer { lock.unlock() }

                        if session.status == .completed {
                            hasResumed = true
                            continuation.resume(returning: tempURL)
                        } else {
                            hasResumed = true
                            let msg = session.error?.localizedDescription ?? "Неизвестная ошибка экспорта"
                            continuation.resume(throwing: MediaExportError.exportFailed(msg))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Очистка временного файла

    static func cleanupExportedFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
