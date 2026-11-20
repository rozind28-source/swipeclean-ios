import SwiftUI
import Photos

struct DashboardView: View {
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(DecisionStore.self) private var decisionStore
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 11/255, green: 12/255, blue: 16/255)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Баннер статуса Фазы 1 для smoke-теста CI
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(Color(red: 34/255, green: 197/255, blue: 94/255))
                                    .font(.title2)

                                Text("Каркас Фазы 1 готов для CI")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                Spacer()
                            }

                            Text("Доменные контракты, хранилище SwiftData, движок свайпов SwipeSessionEngine и сервис прав успешно инициализированы.")
                                .font(.subheadline)
                                .foregroundColor(.gray)

                            Divider()
                                .background(Color.white.opacity(0.1))

                            HStack {
                                Text("Статус прав доступа:")
                                    .font(.caption)
                                    .foregroundColor(.gray)

                                Text(permissionStatusText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                            }
                        }
                        .padding(20)
                        .background(Color(red: 22/255, green: 24/255, blue: 31/255))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                        // Hero-карточка статистики
                        VStack(spacing: 16) {
                            Text("Освобождено памяти")
                                .font(.subheadline)
                                .foregroundColor(.gray)

                            Text(ByteFormatter.format(decisionStore.stats.totalBytesFreed))
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            HStack(spacing: 40) {
                                VStack(spacing: 4) {
                                    Text("\(decisionStore.stats.totalReviewedCount)")
                                        .font(.title3.weight(.bold))
                                        .foregroundColor(.white)
                                    Text("Проверено")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }

                                VStack(spacing: 4) {
                                    Text("\(decisionStore.stagedCount)")
                                        .font(.title3.weight(.bold))
                                        .foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255))
                                    Text("В корзине")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }

                                VStack(spacing: 4) {
                                    Text("\(decisionStore.stats.totalDeletedCount)")
                                        .font(.title3.weight(.bold))
                                        .foregroundColor(Color(red: 34/255, green: 197/255, blue: 94/255))
                                    Text("Удалено")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(Color(red: 22/255, green: 24/255, blue: 31/255))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                        // Информационный блок о Фазе 2
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Следующий этап: Фаза 2")
                                .font(.headline)
                                .foregroundColor(.white)

                            Text("Будет реализовано фоновое PhotoKit-индексирование 50 000+ файлов, группировка по месяцам, альбомам и смарт-подборкам, и полноценный UI дашборда.")
                                .font(.footnote)
                                .foregroundColor(.secondary)

                            Button {
                                HapticsService.shared.impact(.light)
                            } label: {
                                HStack {
                                    Image(systemName: "hand.tap.fill")
                                    Text("Тест тактильного отклика (Haptics)")
                                }
                                .font(.footnote.weight(.medium))
                                .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(Color(red: 22/255, green: 24/255, blue: 31/255))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .padding(20)
                }
            }
            .navigationTitle("SwipeClean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var permissionStatusText: String {
        switch photoService.currentStatus {
        case .authorized:
            return "Полный доступ (.authorized)"
        case .limited:
            return "Ограниченный доступ (.limited)"
        case .notDetermined:
            return "Не определено (.notDetermined)"
        case .denied:
            return "Запрещено (.denied)"
        case .restricted:
            return "Ограничено системой (.restricted)"
        @unknown default:
            return "Неизвестно"
        }
    }
}
