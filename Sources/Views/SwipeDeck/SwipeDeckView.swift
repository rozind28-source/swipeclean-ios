import SwiftUI
import Photos

/// Главный экран свайп-деки SwipeDeckView.
/// КРАСНАЯ ЛИНИЯ: Открывается строго через .fullScreenCover.
/// Содержит верхнюю панель управления, стопку из максимум 3 карточек,
/// 5 нижних кнопок действий и экран завершения группы с приглашением в корзину.
struct SwipeDeckView: View {
    let group: MediaGroup
    let onDismiss: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var viewModel: SwipeDeckViewModel

    init(
        group: MediaGroup,
        photoService: PhotoLibraryService,
        decisionStore: DecisionStore,
        onDismiss: @escaping () -> Void
    ) {
        self.group = group
        self.onDismiss = onDismiss
        _viewModel = State(
            initialValue: SwipeDeckViewModel(
                group: group,
                photoService: photoService,
                decisionStore: decisionStore
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Тёмный фон по спецификации (#0B0C10)
                Color(red: 11/255, green: 12/255, blue: 16/255)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    // 1. Верхняя панель управления
                    topNavigationBar

                    // 2. Колода карточек или экран завершения
                    if viewModel.isGroupFinished {
                        groupCompletionView
                    } else {
                        cardDeckContainer(size: geometry.size)
                    }

                    // 3. Нижняя панель действий (5 кнопок)
                    if !viewModel.isGroupFinished {
                        bottomActionButtons
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onAppear {
                let deckWidth = max(geometry.size.width - 32, 1)
                let deckHeight = max(geometry.size.height - 200, 1)
                viewModel.onAppear(
                    containerSize: CGSize(width: deckWidth, height: deckHeight),
                    displayScale: displayScale
                )
            }
            .onDisappear {
                viewModel.onDisappear()
            }
            .onChange(of: scenePhase) { _, newPhase in
                viewModel.videoController.handleScenePhaseChange(newPhase)
            }
            .sheet(isPresented: $viewModel.showShareSheet) {
                if let fileURL = viewModel.shareFileURL {
                    ActivityShareSheet(fileURL: fileURL) {
                        viewModel.shareFileURL = nil
                        viewModel.showShareSheet = false
                    }
                }
            }
            .fullScreenCover(isPresented: $viewModel.showTrashReview) {
                TrashReviewView(
                    group: group,
                    photoService: photoService,
                    decisionStore: decisionStore
                ) {
                    viewModel.showTrashReview = false
                    if viewModel.isGroupFinished && viewModel.stagedCountInGroup == 0 {
                        onDismiss()
                    }
                }
            }
        }
    }

    // MARK: - Верхняя панель (✕, остаток, корзина группы)

    private var topNavigationBar: some View {
        HStack(spacing: 12) {
            // Кнопка закрытия ✕
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }

            // Название группы и счётчик остатка («14 из 85»)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("\(viewModel.remainingCount) из \(viewModel.totalGroupCount)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            // Пилюля корзины текущей группы («🗑 7 • 34 МБ»)
            if viewModel.stagedCountInGroup > 0 {
                Button {
                    viewModel.showTrashReview = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash.fill")
                            .font(.caption2)
                        Text("\(viewModel.stagedCountInGroup) • \(ByteFormatter.format(viewModel.stagedBytesInGroup))")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.9))
                    .clipShape(Capsule())
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.caption2)
                    Text("0")
                        .font(.caption2.weight(.medium))
                }
                .foregroundColor(.gray)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Контейнер колоды карточек (ZStack до 3 карточек)

    private func cardDeckContainer(size: CGSize) -> some View {
        let visibleIDs = viewModel.visibleAssetIDs
        let visibleAssets = visibleIDs.compactMap { viewModel.asset(for: $0) }

        return ZStack {
            // КРАСНАЯ ЛИНИЯ: ForEach строго с id: \.localIdentifier
            // Отображаем в обратном порядке (reversed), чтобы верхняя карточка была последним дочерним элементом ZStack
            ForEach(Array(visibleAssets.reversed()), id: \.localIdentifier) { asset in
                let index = visibleIDs.firstIndex(of: asset.localIdentifier) ?? 0
                let isTop = (index == 0)

                SwipeCardView(
                    asset: asset,
                    metadata: viewModel.metadata(for: asset.localIdentifier),
                    sizeBytes: (isTop ? viewModel.currentAssetSize : 0),
                    isTop: isTop,
                    stackIndex: index,
                    onSwipe: { direction in
                        viewModel.swipe(direction: direction, assetID: asset.localIdentifier)
                    },
                    viewModel: viewModel
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 5 Нижних кнопок действий

    private var bottomActionButtons: some View {
        HStack(spacing: 16) {
            // 1. Undo
            Button {
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(viewModel.canUndo ? .white : .gray.opacity(0.4))
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .disabled(!viewModel.canUndo)

            Spacer()

            // 2. Красная кнопка «Удалить» (Свайп влево)
            Button {
                if let currentID = viewModel.currentAssetID {
                    viewModel.swipe(direction: .left, assetID: currentID)
                }
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Color(red: 239/255, green: 68/255, blue: 68/255))
                    .clipShape(Circle())
                    .shadow(color: Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.4), radius: 8, x: 0, y: 4)
            }

            Spacer()

            // 3. Поделиться (Share с индикатором загрузки оригинала)
            Button {
                viewModel.exportAndShare()
            } label: {
                Group {
                    if viewModel.isExportingForShare {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 48, height: 48)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
            }
            .disabled(viewModel.isExportingForShare)

            Spacer()

            // 4. Зелёная кнопка «Оставить» (Свайп вправо)
            Button {
                if let currentID = viewModel.currentAssetID {
                    viewModel.swipe(direction: .right, assetID: currentID)
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Color(red: 34/255, green: 197/255, blue: 94/255))
                    .clipShape(Circle())
                    .shadow(color: Color(red: 34/255, green: 197/255, blue: 94/255).opacity(0.4), radius: 8, x: 0, y: 4)
            }

            Spacer()

            // 5. Избранное
            Button {
                viewModel.toggleFavorite()
            } label: {
                Image(systemName: viewModel.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(viewModel.isFavorite ? Color(red: 234/255, green: 179/255, blue: 8/255) : .white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Экран завершения группы

    private var groupCompletionView: some View {
        VStack(spacing: 24) {
            Spacer()

            if viewModel.stagedCountInGroup > 0 {
                ZStack {
                    Circle()
                        .fill(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.15))
                        .frame(width: 96, height: 96)
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255))
                }

                VStack(spacing: 8) {
                    Text("Группа разобрана!")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)

                    Text("В корзине этой группы: \(viewModel.stagedCountInGroup) файлов (\(ByteFormatter.format(viewModel.stagedBytesInGroup)))")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(spacing: 12) {
                    Button {
                        viewModel.showTrashReview = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash.fill")
                            Text("Перейти в корзину")
                        }
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 239/255, green: 68/255, blue: 68/255))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Button {
                        onDismiss()
                    } label: {
                        Text("Вернуться на главную")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.gray)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 24)
            } else {
                ZStack {
                    Circle()
                        .fill(Color(red: 34/255, green: 197/255, blue: 94/255).opacity(0.15))
                        .frame(width: 96, height: 96)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(Color(red: 34/255, green: 197/255, blue: 94/255))
                }

                VStack(spacing: 8) {
                    Text("Все файлы сохранены!")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)

                    Text("Вы разобрали все файлы в группе «\(group.title)». В корзину ничего не отправлено.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button {
                    onDismiss()
                } label: {
                    Text("Вернуться на главную")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 99/255, green: 102/255, blue: 241/255))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 24)
            }

            Spacer()
        }
    }
}
