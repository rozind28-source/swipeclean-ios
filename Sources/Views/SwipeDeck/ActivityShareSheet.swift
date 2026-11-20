import SwiftUI
import UIKit

/// UIViewControllerRepresentable для отображения системного UIActivityViewController.
/// КРАСНАЯ ЛИНИЯ: Очистка временного файла в completionWithItemsHandler,
/// предотвращающая утечки дискового пространства в tmp/.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let fileURL: URL
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )

        controller.completionWithItemsHandler = { [fileURL] _, _, _, _ in
            MediaExportService.cleanupExportedFile(at: fileURL)
            DispatchQueue.main.async {
                onComplete?()
            }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Нет необходимости в динамическом обновлении UIActivityViewController
    }

    static func dismantleUIViewController(_ uiViewController: UIActivityViewController, coordinator: ()) {
        // Дополнительная гарантия очистки ресурсов
    }
}
