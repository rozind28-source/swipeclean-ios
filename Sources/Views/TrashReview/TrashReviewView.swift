import SwiftUI
import Photos

struct TrashReviewView: View {
    let group: MediaGroup?
    let photoService: PhotoLibraryService
    let decisionStore: DecisionStore
    var onDismiss: () -> Void

    @State private var viewModel: TrashReviewViewModel

    // КРАСНАЯ ЛИНИЯ: сетка 3 колонки (LazyVGrid) с spacing 2pt
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    init(
        group: MediaGroup? = nil,
        groupID: String? = nil,
        photoService: PhotoLibraryService,
        decisionStore: DecisionStore,
        onDismiss: @escaping () -> Void
    ) {
        self.group = group
        self.photoService = photoService
        self.decisionStore = decisionStore
        self.onDismiss = onDismiss
        _viewModel = State(
            initialValue: TrashReviewViewModel(
                group: group,
                groupID: groupID,
                photoService: photoService,
                decisionStore: decisionStore
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 11/255, green: 12/255, blue: 16/255)
                    .ignoresSafeArea()

                if viewModel.showSessionComplete {
                    SessionCompleteView(
                        deletedCount: viewModel.deletedCountInSession,
                        freedBytes: viewModel.freedBytesInSession,
                        onFinish: onDismiss
                    )
                } else if viewModel.assetIDs.isEmpty {
                    emptyStateView
                } else {
                    reviewContentView
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar(viewModel.showSessionComplete ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.totalCount > 0 {
                        Button {
                            if viewModel.areAllRescued {
                                viewModel.selectAllForDeletion()
                            } else {
                                viewModel.rescueAll()
                            }
                        } label: {
                            Text(viewModel.areAllRescued ? "Выбрать все" : "Спасти все")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                        }
                    }
                }
            }
            .alert("Ошибка удаления", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Не удалось завершить операцию удаления.")
            }
            .onDisappear {
                viewModel.cancelTasks()
            }
        }
    }

    private var navigationTitle: String {
        if let group = group {
            return group.title
        }
        return "Корзина"
    }

    // MARK: - Пустая корзина

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "trash.slash.fill")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.6))

            VStack(spacing: 8) {
                Text("Корзина пуста")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)

                Text("Нет файлов, ожидающих удаления.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }

            Button {
                onDismiss()
            } label: {
                Text("Закрыть")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color(red: 22/255, green: 24/255, blue: 31/255))
                    .clipShape(Capsule())
            }
            .padding(.top, 12)

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Содержимое корзины с сеткой без прыжков

    private var reviewContentView: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 8) {
                    // Подсказка пользователю
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .foregroundColor(Color(red: 34/255, green: 197/255, blue: 94/255))
                        Text("Нажмите на фото, чтобы спасти его от удаления")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    // КРАСНАЯ ЛИНИЯ: LazyVGrid 3 колонки (spacing 2pt) БЕЗ прыжков.
                    // Тап по ячейке переключает её в rescuedIDs на месте (opacity 0.45 + зелёная галочка «Оставить»).
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(viewModel.assetIDs, id: \.self) { assetID in
                            if let asset = viewModel.assetsById[assetID] {
                                TrashAssetCell(
                                    asset: asset,
                                    metadata: viewModel.metadataById[assetID],
                                    isRescued: viewModel.rescuedIDs.contains(assetID),
                                    sizeBytes: viewModel.assetSizes[assetID],
                                    onTap: {
                                        viewModel.toggleRescue(id: assetID)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    // Отступ под закреплённую панель
                    .padding(.bottom, 120)
                }
            }

            // Закреплённая нижняя панель
            pinnedBottomBar
        }
    }

    // MARK: - Закреплённая нижняя панель

    private var pinnedBottomBar: some View {
        VStack(spacing: 12) {
            // Строка со сводкой: «К удалению: N из Total • X МБ»
            HStack(spacing: 6) {
                if viewModel.itemsToDeleteCount > 0 {
                    Text("К удалению:")
                        .foregroundColor(.gray)
                    Text("\(viewModel.itemsToDeleteCount) из \(viewModel.totalCount)")
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                    Text("•")
                        .foregroundColor(.gray)
                    Text(ByteFormatter.format(viewModel.bytesToDelete))
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(red: 34/255, green: 197/255, blue: 94/255))
                    Text("Все файлы спасены")
                        .foregroundColor(Color(red: 34/255, green: 197/255, blue: 94/255))
                        .fontWeight(.semibold)
                }
            }
            .font(.subheadline)

            // Кнопка действия: удаление или сохранение спасённых
            if viewModel.itemsToDeleteCount > 0 {
                Button {
                    Task {
                        await viewModel.executeBatchDelete(onDismiss: onDismiss)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isDeleting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "trash.fill")
                            Text("Удалить выбранные (\(viewModel.itemsToDeleteCount))")
                        }
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 239/255, green: 68/255, blue: 68/255))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(viewModel.isDeleting)
            } else {
                Button {
                    viewModel.saveRescuedAndDismiss(onDismiss: onDismiss)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Сохранить спасённые и закрыть")
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 34/255, green: 197/255, blue: 94/255))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(
            Color(red: 22/255, green: 24/255, blue: 31/255)
                .shadow(color: .black.opacity(0.35), radius: 10, y: -4)
        )
    }
}

// MARK: - Ячейка сетки корзины (LazyVGrid)

struct TrashAssetCell: View {
    let asset: PHAsset
    let metadata: MediaMetadata?
    let isRescued: Bool
    let sizeBytes: Int64?
    let onTap: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnailImage: UIImage? = nil
    @State private var requestID: PHImageRequestID? = nil

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ZStack(alignment: .bottomTrailing) {
                        // Фоновая подложка
                        Color(red: 22/255, green: 24/255, blue: 31/255)

                        // Изображение из ImageCacheManager
                        if let image = thumbnailImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .opacity(isRescued ? 0.45 : 1.0)
                        } else {
                            ProgressView()
                                .tint(.gray.opacity(0.6))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        // Бейдж видео
                        if asset.mediaType == .video {
                            HStack(spacing: 3) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8))
                                Text(formatDuration(asset.duration))
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.65))
                            .clipShape(Capsule())
                            .padding(4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        }

                        // Бейдж размера
                        if let size = sizeBytes, size > 0 {
                            Text(ByteFormatter.format(size))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .padding(4)
                        }

                        // In-place отметка «Оставить» (плитка остаётся на месте, сетка не прыгает!)
                        if isRescued {
                            Color.black.opacity(0.25)

                            VStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(Color(red: 34/255, green: 197/255, blue: 94/255))

                                Text("Оставить")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 34/255, green: 197/255, blue: 94/255).opacity(0.9))
                                    .clipShape(Capsule())
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap()
                    }
                    .onAppear {
                        loadThumbnail(size: geo.size)
                    }
                    .onDisappear {
                        cancelThumbnailRequest()
                    }
                }
            }
            .clipped()
    }

    private func loadThumbnail(size: CGSize) {
        cancelThumbnailRequest()
        let target = ImageCacheManager.targetSize(for: size, displayScale: displayScale)
        requestID = ImageCacheManager.shared.requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFill
        ) { image, _ in
            self.thumbnailImage = image
        }
    }

    private func cancelThumbnailRequest() {
        if let id = requestID {
            ImageCacheManager.shared.cancelRequest(id: id)
            requestID = nil
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
