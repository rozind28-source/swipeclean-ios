import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(DecisionStore.self) private var decisionStore

    @State private var showResetConfirmation: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 11/255, green: 12/255, blue: 16/255)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Секция оформления
                        settingsSection(title: "Внешний вид") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Тема оформления")
                                    .font(.subheadline)
                                    .foregroundColor(.white)

                                Picker("Тема", selection: Bindable(settings).theme) {
                                    ForEach(AppTheme.allCases) { theme in
                                        Text(theme.title).tag(theme)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        // Секция взаимодействия
                        settingsSection(title: "Настройки разбора") {
                            VStack(spacing: 16) {
                                Toggle(isOn: Bindable(settings).hapticsEnabled) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Тактильный отклик")
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                        Text("Вибрация при свайпах и действиях")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .tint(Color(red: 99/255, green: 102/255, blue: 241/255))

                                Divider()
                                    .background(Color.white.opacity(0.1))

                                Toggle(isOn: Bindable(settings).hideCompletedGroups) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Скрывать разобранные группы")
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                        Text("Прятать группы, где все фото проверены")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .tint(Color(red: 99/255, green: 102/255, blue: 241/255))
                            }
                        }

                        // Секция данных
                        settingsSection(title: "Управление данными") {
                            Button(role: .destructive) {
                                showResetConfirmation = true
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Сбросить весь прогресс просмотра")
                                    Spacer()
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255))
                            }
                        }

                        // Секция «О приложении»
                        settingsSection(title: "О приложении") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Версия")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text("1.0.0")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.white)
                                }

                                Divider()
                                    .background(Color.white.opacity(0.1))

                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "lock.shield.fill")
                                        .foregroundColor(Color(red: 34/255, green: 197/255, blue: 94/255))
                                        .font(.title3)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("100% оффлайн и конфиденциально")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.white)
                                        Text("SwipeClean не использует сторонние серверы или аналитику. Все операции выполняются строго локально на вашем iPhone.")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                }
            }
            .confirmationDialog(
                "Сбросить весь прогресс?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Сбросить оставленные решения", role: .destructive) {
                    decisionStore.resetKeptDecisions()
                    HapticsService.shared.notification(.success)
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Все отметки «Оставить» будут очищены. Файлы в корзине затронуты не будут.")
            }
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundColor(.gray)
                .padding(.horizontal, 4)

            VStack(alignment: .leading) {
                content()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 22/255, green: 24/255, blue: 31/255))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
            )
        }
    }
}
