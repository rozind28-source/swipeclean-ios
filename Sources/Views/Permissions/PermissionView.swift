import SwiftUI
import Photos
import UIKit

struct PermissionView: View {
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(\.openURL) private var openURL
    @State private var isRequesting = false

    var body: some View {
        ZStack {
            // Тёмный фон #0B0C10
            Color(red: 11/255, green: 12/255, blue: 16/255)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Логотип и заголовок
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 99/255, green: 102/255, blue: 241/255).opacity(0.15))
                            .frame(width: 100, height: 100)

                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(Color(red: 99/255, green: 102/255, blue: 241/255))
                    }

                    Text("SwipeClean")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Быстрая и безопасная очистка галереи свайпами")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // 3 ключевых тезиса приватности и безопасности
                VStack(spacing: 20) {
                    featureRow(
                        icon: "lock.shield.fill",
                        iconColor: Color(red: 99/255, green: 102/255, blue: 241/255),
                        title: "100% приватно и оффлайн",
                        description: "Все медиафайлы анализируются строго на вашем устройстве. Без серверов, облаков и аналитики."
                    )

                    featureRow(
                        icon: "arrow.counterclockwise.circle.fill",
                        iconColor: Color(red: 34/255, green: 197/255, blue: 94/255),
                        title: "30 дней на восстановление",
                        description: "Файлы перемещаются в системную папку «Недавно удалённые». Вы всегда можете восстановить их."
                    )

                    featureRow(
                        icon: "hand.draw.fill",
                        iconColor: Color(red: 239/255, green: 68/255, blue: 68/255),
                        title: "Двухэтапное удаление",
                        description: "Свайп влево только отправляет в корзину приложения. Физическое удаление запускается по вашей команде."
                    )
                }
                .padding(24)
                .background(Color(red: 22/255, green: 24/255, blue: 31/255))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 20)

                Spacer()

                // Кнопка запроса прав или перехода в Настройки
                VStack(spacing: 12) {
                    if photoService.currentStatus == .denied || photoService.currentStatus == .restricted {
                        Text("Доступ к фото был отклонён. Чтобы SwipeClean мог разбирать галерею, включите доступ в Настройках.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        Button {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                openURL(settingsURL)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "gear")
                                Text("Открыть «Настройки»")
                            }
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color(red: 99/255, green: 102/255, blue: 241/255))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .padding(.horizontal, 20)
                    } else {
                        Button {
                            Task {
                                isRequesting = true
                                await photoService.requestAuthorization()
                                isRequesting = false
                            }
                        } label: {
                            HStack {
                                if isRequesting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Разрешить доступ к фото")
                                }
                            }
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color(red: 99/255, green: 102/255, blue: 241/255))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(isRequesting)
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func featureRow(icon: String, iconColor: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
