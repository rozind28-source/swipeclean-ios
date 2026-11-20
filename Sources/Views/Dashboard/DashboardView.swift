import SwiftUI
import Photos

struct DashboardView: View {
    @Environment(PhotoLibraryService.self) private var photoService
    @Environment(DecisionStore.self) private var decisionStore
    @Environment(AppSettings.self) private var settings

    @State private var viewModel = DashboardViewModel()

    var body: some View {
        @Bindable var vm = viewModel

        NavigationStack {
            ZStack {
                Color(red: 11/255, green: 12/255, blue: 16/255)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        // Баннер ограниченного доступа (Limited Access)
                        if vm.isLimitedAccess {
                            limitedAccessBanner
                        }

                        // Hero-карточка статистики
                        heroStatsCard

                        // Глобальный красный баннер корзины (если stagedCount > 0)
                        if vm.stagedCount > 0 {
                            stagedTrashBanner
                        }

                        // Segmented control переключения режимов
                        Picker("Режим", selection: $vm.selectedMode) {
                            ForEach(CleaningMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 4)

                        // Список групп или состояние загрузки/пустоты
                        if vm.isIndexing {
                            indexingIndicator
                        } else if vm.filteredGroups.isEmpty {
                            emptyGroupsState
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(vm.filteredGroups) { group in
                                    GroupRowCard(
                                        group: group,
                                        progress: vm.progress(for: group),
                                        coverAsset: vm.coverAsset(for: group),
                                        onReset: {
                                            vm.resetGroupProgress(group)
                                        }
                                    )
                                    .onTapGesture {
                                        HapticsService.shared.impact(.light)
                                        vm.selectedGroup = group
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("SwipeClean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    filterMenu
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundColor(.white)
                    }
                }
            }
            // КРАСНАЯ ЛИНИЯ: открытие экрана группы строго через .fullScreenCover
            .fullScreenCover(item: $vm.selectedGroup) { group in
                SwipeDeckPlaceholderView(group: group) {
                    vm.selectedGroup = nil
                }
            }
            .fullScreenCover(isPresented: $vm.showTrashReview) {
                TrashReviewPlaceholderView {
                    vm.showTrashReview = false
                }
            }
            .sheet(isPresented: $vm.showSettings) {
                SettingsView()
            }
            .task {
                vm.configure(
                    photoService: photoService,
                    decisionStore: decisionStore,
                    settings: settings
                )
                vm.onAppear()
            }
        }
    }

    // MARK: - Подкомпоненты

    /// Баннер ограниченного доступа (.limited)
    private var limitedAccessBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(red: 234/255, green: 179/255, blue: 8/255))
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ограниченный доступ к фото")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("SwipeClean видит только часть медиатеки.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.openLimitedAccessPicker()
                } label: {
                    Text("Выбрать ещё")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(red: 99/255, green: 102/255, blue: 241/255))
                        .clipShape(Capsule())
                }

                Button {
                    viewModel.openSystemSettings()
                } label: {
                    Text("Настройки")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(Color(red: 35/255, green: 30/255, blue: 18/255))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 234/255, green: 179/255, blue: 8/255).opacity(0.3), lineWidth: 1)
        )
    }

    /// Hero-карточка статистики («Освобождено», «Проверено», «Удалено»)
    private var heroStatsCard: some View {
        VStack(spacing: 16) {
            Text("Освобождено памяти")
                .font(.subheadline)
                .foregroundColor(.gray)

            Text(ByteFormatter.format(viewModel.stats.totalBytesFreed))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            HStack(spacing: 36) {
                VStack(spacing: 4) {
                    Text("\(viewModel.stats.totalReviewedCount)")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                    Text("Проверено")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                VStack(spacing: 4) {
                    Text("\(viewModel.stagedCount)")
                        .font(.title3.weight(.bold))
                        .foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255))
                    Text("В корзине")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                VStack(spacing: 4) {
                    Text("\(viewModel.stats.totalDeletedCount)")
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
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    /// Глобальный красный баннер корзины
    private var stagedTrashBanner: some View {
        Button {
            viewModel.showTrashReview = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill")
                    .font(.title3)
                    .foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255))

                VStack(alignment: .leading, spacing: 2) {
                    Text("В корзине \(viewModel.stagedCount) файлов (\(ByteFormatter.format(viewModel.stagedTotalBytes)))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("Нажмите, чтобы проверить и удалить")
                        .font(.caption)
                        .foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.9))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(16)
            .background(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Индикатор индексирования
    private var indexingIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color(red: 99/255, green: 102/255, blue: 241/255))
            Text("Индексирование медиатеки...")
                .font(.footnote)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    /// Пустое состояние
    private var emptyGroupsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundColor(.gray.opacity(0.5))

            Text("Нет доступных фото")
                .font(.headline)
                .foregroundColor(.white)

            if settings.hideCompletedGroups {
                Text("Все группы в этом разделе разобраны и скрыты фильтром.")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Button("Показать разобранные группы") {
                    settings.hideCompletedGroups = false
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                .padding(.top, 4)
            } else {
                Text("В этом разделе нет фотографий или видео.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color(red: 22/255, green: 24/255, blue: 31/255))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Меню фильтрации в тулбаре
    private var filterMenu: some View {
        Menu {
            Toggle(
                "Скрывать разобранные",
                isOn: Bindable(settings).hideCompletedGroups
            )

            if viewModel.selectedMode == .smart {
                Button {
                    viewModel.reshuffleRandom50()
                } label: {
                    Label("Пересобрать «Случайные 50»", systemImage: "dice")
                }
            }
        } label: {
            Image(systemName: settings.hideCompletedGroups ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .foregroundColor(.white)
        }
    }
}
