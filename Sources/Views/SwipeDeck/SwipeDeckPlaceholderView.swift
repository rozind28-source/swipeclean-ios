import SwiftUI

struct SwipeDeckPlaceholderView: View {
    let group: MediaGroup
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 11/255, green: 12/255, blue: 16/255)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 64))
                        .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))

                    Text(group.title)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)

                    Text("Файлов в группе: \(group.assetIDs.count)")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    Text("Экран свайп-деки с поддержкой жестов, Pinch-to-Zoom, видеоплеера и Undo будет реализован в Фазе 3.")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        onDismiss()
                    } label: {
                        Text("Вернуться на главный экран")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(Color(red: 99/255, green: 102/255, blue: 241/255))
                            .clipShape(Capsule())
                    }
                    .padding(.top, 16)
                }
                .padding(24)
            }
            .navigationTitle(group.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }
}
