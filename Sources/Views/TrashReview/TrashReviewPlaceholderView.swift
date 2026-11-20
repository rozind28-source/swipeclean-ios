import SwiftUI

struct TrashReviewPlaceholderView: View {
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 11/255, green: 12/255, blue: 16/255)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255))

                    Text("Корзина")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)

                    Text("Экран проверки корзины, in-place спасения фото без прыжков сетки и системного пакетного удаления будет реализован в Фазе 4.")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        onDismiss()
                    } label: {
                        Text("Закрыть")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(Color(red: 22/255, green: 24/255, blue: 31/255))
                            .clipShape(Capsule())
                    }
                    .padding(.top, 16)
                }
                .padding(24)
            }
            .navigationTitle("Корзина")
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
