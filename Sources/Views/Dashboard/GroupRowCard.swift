import SwiftUI
import Photos

struct GroupRowCard: View {
    let group: MediaGroup
    let progress: GroupProgress
    let coverAsset: PHAsset?
    let onReset: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var coverImage: UIImage? = nil
    @State private var requestID: PHImageRequestID? = nil

    var body: some View {
        HStack(spacing: 14) {
            // Обложка 56x56 pt
            ZStack {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(red: 30/255, green: 32/255, blue: 40/255))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: iconName(for: group))
                                .font(.system(size: 22))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            // Текстовая информация и прогресс
            VStack(alignment: .leading, spacing: 6) {
                Text(group.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let subtitle = group.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.5))

                    Text("\(progress.reviewedCount) из \(progress.totalCount)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(progress.isCompleted ? Color(red: 34/255, green: 197/255, blue: 94/255) : .gray)
                }

                // Прогресс-бар
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 4)

                        Capsule()
                            .fill(
                                progress.isCompleted
                                    ? Color(red: 34/255, green: 197/255, blue: 94/255)
                                    : Color(red: 99/255, green: 102/255, blue: 241/255)
                            )
                            .frame(
                                width: max(0, min(geo.size.width * CGFloat(progress.completionRatio), geo.size.width)),
                                height: 4
                            )
                    }
                }
                .frame(height: 4)
            }

            Spacer(minLength: 4)

            // Трейлинг статус: бейдж корзины группы / галочка 100% / шеврон
            HStack(spacing: 8) {
                if progress.stagedCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 10))
                        Text("\(progress.stagedCount)")
                            .font(.caption2.weight(.bold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.2))
                    .foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255))
                    .clipShape(Capsule())
                }

                if progress.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(Color(red: 34/255, green: 197/255, blue: 94/255))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
        }
        .padding(14)
        .background(Color(red: 22/255, green: 24/255, blue: 31/255))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                onReset()
            } label: {
                Label("Сбросить прогресс этой группы", systemImage: "arrow.counterclockwise")
            }
        }
        .task(id: coverAsset?.localIdentifier) {
            loadCoverImage()
        }
        .onDisappear {
            if let requestID {
                ImageCacheManager.shared.cancelRequest(id: requestID)
                self.requestID = nil
            }
        }
    }

    private func loadCoverImage() {
        guard let coverAsset else { return }
        let targetSize = ImageCacheManager.targetSize(
            for: CGSize(width: 56, height: 56),
            displayScale: displayScale
        )
        self.requestID = ImageCacheManager.shared.requestImage(
            for: coverAsset,
            targetSize: targetSize,
            contentMode: .aspectFill
        ) { image, _ in
            self.coverImage = image
        }
    }

    private func iconName(for group: MediaGroup) -> String {
        switch group.mode {
        case .months:
            return "calendar"
        case .albums:
            return "rectangle.stack"
        case .smart:
            if group.id.contains("video") {
                return "video.fill"
            } else if group.id.contains("screenshot") {
                return "camera.viewfinder"
            } else if group.id.contains("day") {
                return "sparkles"
            } else {
                return "dice.fill"
            }
        }
    }
}
