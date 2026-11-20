import SwiftUI
import Photos

struct RootView: View {
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(AppSettings.self) private var settings
    @Environment(DecisionStore.self) private var decisionStore

    var body: some View {
        Group {
            switch photoService.currentStatus {
            case .authorized, .limited:
                DashboardView()
            case .notDetermined, .denied, .restricted:
                PermissionView()
            @unknown default:
                PermissionView()
            }
        }
        .task {
            photoService.refreshStatus()
            decisionStore.hydrate()
        }
    }
}
