import Foundation
import Photos
import Observation

@Observable
@MainActor
final class PhotoLibraryService: NSObject {
    private(set) var currentStatus: PHAuthorizationStatus

    override init() {
        self.currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        super.init()
    }

    /// Обновляет текущий статус доступа к медиатеке
    func refreshStatus() {
        self.currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Запрос прав доступа по явному нажатию кнопки пользователем.
    /// Строго запрещено вызывать автоматически в .onAppear!
    @discardableResult
    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        self.currentStatus = status
        return status
    }
}
