import SwiftUI
import Photos
import AVFoundation

/// Карточка свайпа SwipeCardView.
/// Отображает фото, видео (LoopingVideoView) или Live Photo.
/// Поддерживает Pinch-to-Zoom (MagnifyGesture) + двойной тап (1× ↔ 2.5×),
/// панорамирование увеличенного изображения, метаданные с секундами внизу,
/// бейджи, капсулу загрузки из iCloud и штампы «УДАЛИТЬ» / «ОСТАВИТЬ».
struct SwipeCardView: View {
    let asset: PHAsset
    let metadata: MediaMetadata?
    let sizeBytes: Int64
    let isTop: Bool
    let stackIndex: Int // 0 - верхняя, 1 - средняя, 2 - нижняя
    let onSwipe: (SwipeDirection) -> Void

    @Environment(\.displayScale) private var displayScale
    @Bindable var viewModel: SwipeDeckViewModel

    // Локальное состояние загрузки изображения
    @State private var image: UIImage? = nil
    @State private var requestID: PHImageRequestID? = nil
    @State private var iCloudProgress: Double? = nil
    @State private var isInCloud: Bool = false
    @State private var hasError: Bool = false

    // Локальное состояние жеста перетаскивания (для верхней карточки)
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    // Zoom-жесты
    @GestureState private var magnifyScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = geometry.size.width
            let cardHeight = geometry.size.height

            ZStack {
                // Фоновая подложка карточки
                Color(red: 22/255, green: 24/255, blue: 31/255)

                // 1. Медиа-контент (Фото или Видео)
                mediaContent(size: geometry.size)

                // 2. Оверлей загрузки из iCloud или ошибки сети
                iCloudStatusOverlay

                // 3. Оверлеи штампов «УДАЛИТЬ» / «ОСТАВИТЬ» (только на верхней карточке)
                if isTop {
                    decisionStampOverlays
                }

                // 4. Нижний блок метаданных с секундами поверх градиента
                VStack {
                    Spacer()
                    bottomMetadataBar
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(borderStrokeColor, lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
            // Физика стопки карточек
            .scaleEffect(stackScale)
            .offset(y: stackOffsetY)
            // Смещение и наклон верхней карточки при свайпе
            .offset(isTop ? currentCardOffset : .zero)
            .rotationEffect(isTop ? currentCardRotation : .zero)
            .allowsHitTesting(isTop && !viewModel.isTransitioning)
            // Жесты зума, двойного тапа и свайпа
            .gesture(isTop ? cardGestures(cardWidth: cardWidth) : nil)
            .onAppear {
                loadImage(containerSize: geometry.size)
            }
            .onDisappear {
                cancelImageRequest()
            }
            .onChange(of: asset.localIdentifier) { _, _ in
                cancelImageRequest()
                loadImage(containerSize: geometry.size)
            }
        }
    }

    // MARK: - Медиа-контент

    @ViewBuilder
    private func mediaContent(size: CGSize) -> some View {
        Group {
            if isTop && asset.mediaType == .video {
                LoopingVideoView(player: viewModel.videoController.player)
            } else if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(isTop ? (viewModel.zoomScale * magnifyScale) : 1.0)
        .offset(isTop ? viewModel.zoomOffset : .zero)
        .clipped()
    }

    // MARK: - Статус iCloud

    @ViewBuilder
    private var iCloudStatusOverlay: some View {
        if isInCloud && hasError {
            VStack(spacing: 6) {
                Image(systemName: "icloud.slash.fill")
                    .font(.title2)
                    .foregroundColor(.yellow)
                Text("В iCloud (нет сети)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.75))
            .clipShape(Capsule())
        } else if isInCloud, let progress = iCloudProgress, progress < 1.0 {
            HStack(spacing: 10) {
                ProgressView(value: progress)
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(0.8)

                Text("Загрузка из iCloud \(Int(progress * 100))%")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.75))
            .clipShape(Capsule())
        }
    }

    // MARK: - Штампы решений («УДАЛИТЬ» / «ОСТАВИТЬ»)

    private var currentCardOffset: CGSize {
        isDragging ? dragOffset : viewModel.cardOffset
    }

    private var currentCardRotation: Angle {
        let x = currentCardOffset.width
        let degrees = Double(x / 20).clamped(to: -14...14)
        return Angle(degrees: degrees)
    }

    private var deleteProgress: Double {
        let x = currentCardOffset.width
        guard x < 0 else { return 0 }
        return min(1.0, max(0.0, Double(-x) / 100.0))
    }

    private var keepProgress: Double {
        let x = currentCardOffset.width
        guard x > 0 else { return 0 }
        return min(1.0, max(0.0, Double(x) / 100.0))
    }

    private var borderStrokeColor: Color {
        if deleteProgress > 0 {
            return Color(red: 239/255, green: 68/255, blue: 68/255).opacity(deleteProgress)
        } else if keepProgress > 0 {
            return Color(red: 34/255, green: 197/255, blue: 94/255).opacity(keepProgress)
        }
        return Color.white.opacity(0.08)
    }

    @ViewBuilder
    private var decisionStampOverlays: some View {
        ZStack {
            // Штамп «УДАЛИТЬ» (красный, слева вверху)
            if deleteProgress > 0 {
                VStack {
                    HStack {
                        Spacer()
                        Text("УДАЛИТЬ")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(red: 239/255, green: 68/255, blue: 68/255), lineWidth: 4)
                            )
                            .rotationEffect(.degrees(12))
                            .opacity(deleteProgress)
                            .padding(24)
                    }
                    Spacer()
                }
            }

            // Штамп «ОСТАВИТЬ» (зелёный, справа вверху)
            if keepProgress > 0 {
                VStack {
                    HStack {
                        Text("ОСТАВИТЬ")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 34/255, green: 197/255, blue: 94/255))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color(red: 34/255, green: 197/255, blue: 94/255), lineWidth: 4)
                            )
                            .rotationEffect(.degrees(-12))
                            .opacity(keepProgress)
                            .padding(24)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Нижний блок метаданных

    private var bottomMetadataBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Бейджи (ВИДЕО, LIVE, СКРИНШОТ) и контролы видео
            HStack(spacing: 8) {
                if let kind = metadata?.kind {
                    switch kind {
                    case .video:
                        badgeView(
                            text: "ВИДЕО \(formatDuration(metadata?.duration ?? asset.duration))",
                            icon: "video.fill",
                            color: Color.blue
                        )
                    case .livePhoto:
                        badgeView(
                            text: "LIVE",
                            icon: "livephoto",
                            color: Color.purple
                        )
                    case .screenshot:
                        badgeView(
                            text: "СКРИНШОТ",
                            icon: "camera.viewfinder",
                            color: Color.orange
                        )
                    case .photo:
                        EmptyView()
                    }
                }

                Spacer()

                // Кнопки управления видео (если актив является видео)
                if asset.mediaType == .video && isTop {
                    HStack(spacing: 12) {
                        Button {
                            viewModel.videoController.toggleMute()
                        } label: {
                            Image(systemName: viewModel.videoController.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }

                        Button {
                            viewModel.videoController.togglePlayPause()
                        } label: {
                            Image(systemName: viewModel.videoController.isPlaying ? "pause.fill" : "play.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                }
            }

            // Дата и время С СЕКУНДАМИ + Разрешение + Вес
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundColor(.gray)

                    Text(formattedDateWithSeconds(metadata?.creationDate ?? asset.creationDate))
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                }

                HStack(spacing: 12) {
                    // Разрешение
                    let width = metadata?.pixelWidth ?? asset.pixelWidth
                    let height = metadata?.pixelHeight ?? asset.pixelHeight
                    Text("\(width) × \(height)")
                        .font(.caption2)
                        .foregroundColor(.gray)

                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.5))

                    // Размер файла
                    Text(ByteFormatter.format(sizeBytes > 0 ? sizeBytes : viewModel.currentAssetSize))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.45),
                    Color.black.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func badgeView(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.85))
        .foregroundColor(.white)
        .clipShape(Capsule())
    }

    // MARK: - Физика стопки

    private var stackScale: CGFloat {
        switch stackIndex {
        case 0: return 1.0
        case 1: return 0.95
        default: return 0.90
        }
    }

    private var stackOffsetY: CGFloat {
        switch stackIndex {
        case 0: return 0
        case 1: return 12
        default: return 24
        }
    }

    // MARK: - Жесты (Pinch-to-Zoom, Двойной тап, Свайп)

    private func cardGestures(cardWidth: CGFloat) -> some Gesture {
        let doubleTap = TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if viewModel.zoomScale > 1.01 {
                        viewModel.zoomScale = 1.0
                        viewModel.zoomOffset = .zero
                    } else {
                        viewModel.zoomScale = 2.5
                        viewModel.zoomOffset = .zero
                    }
                }
            }

        let magnify = MagnifyGesture()
            .updating($magnifyScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                let newScale = (viewModel.zoomScale * value.magnification).clamped(to: 1.0...4.0)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    if newScale <= 1.01 {
                        viewModel.zoomScale = 1.0
                        viewModel.zoomOffset = .zero
                    } else {
                        viewModel.zoomScale = newScale
                    }
                }
            }

        let panOrSwipe = DragGesture()
            .onChanged { value in
                if viewModel.zoomScale > 1.01 {
                    // Панорамирование при зуме
                    viewModel.zoomOffset = CGSize(
                        width: viewModel.zoomOffset.width + value.translation.width * 0.4,
                        height: viewModel.zoomOffset.height + value.translation.height * 0.4
                    )
                } else {
                    // Обычный свайп карточки
                    isDragging = true
                    dragOffset = value.translation
                }
            }
            .onEnded { value in
                if viewModel.zoomScale > 1.01 {
                    // Ограничение панорамирования в границах
                    let maxOffset = (viewModel.zoomScale - 1.0) * (cardWidth / 2)
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        viewModel.zoomOffset = CGSize(
                            width: viewModel.zoomOffset.width.clamped(to: -maxOffset...maxOffset),
                            height: viewModel.zoomOffset.height.clamped(to: -maxOffset...maxOffset)
                        )
                    }
                } else {
                    isDragging = false
                    let translationX = value.translation.width
                    let velocityX = value.predictedEndTranslation.width

                    // Порог > 110pt или флинг > 220pt
                    if translationX < -110 || velocityX < -220 {
                        viewModel.cardOffset = dragOffset
                        dragOffset = .zero
                        onSwipe(.left)
                    } else if translationX > 110 || velocityX > 220 {
                        viewModel.cardOffset = dragOffset
                        dragOffset = .zero
                        onSwipe(.right)
                    } else {
                        // Возврат в центр
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            dragOffset = .zero
                            viewModel.cardOffset = .zero
                        }
                    }
                }
            }

        return doubleTap
            .simultaneously(with: magnify)
            .simultaneously(with: panOrSwipe)
    }

    // MARK: - Загрузка изображения

    private func loadImage(containerSize: CGSize) {
        let targetSize = ImageCacheManager.targetSize(for: containerSize, displayScale: displayScale)

        requestID = ImageCacheManager.shared.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            progressHandler: { progress in
                self.iCloudProgress = progress
            },
            resultHandler: { fetchedImage, deliveryInfo in
                self.image = fetchedImage
                self.isInCloud = deliveryInfo.isInCloud
                self.hasError = deliveryInfo.hasError
                if !deliveryInfo.isDegraded {
                    self.iCloudProgress = nil
                }
            }
        )
    }

    private func cancelImageRequest() {
        if let id = requestID {
            ImageCacheManager.shared.cancelRequest(id: id)
            requestID = nil
        }
    }

    // MARK: - Форматирование даты и времени с секундами

    private static let dateFormatterWithSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM yyyy, HH:mm:ss"
        return formatter
    }()

    private func formattedDateWithSeconds(_ date: Date?) -> String {
        guard let date = date else { return "Дата неизвестна" }
        return Self.dateFormatterWithSeconds.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Вспомогательное расширение Clamped

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
