import Foundation
import AVFoundation
import Photos
import SwiftUI
import Observation

/// Контроллер одиночного AVPlayer для всей сессии SwipeDeck.
/// КРАСНАЯ ЛИНИЯ: Строго один AVPlayer на весь SwipeDeckView.
/// Защита от видео-призраков через activeAssetID и activeRequestID.
/// Умная AVAudioSession: ambient по умолчанию, playback при explicit unmute,
/// возврат в ambient при mute / disappear / scenePhase inactive.
@Observable
@MainActor
final class VideoPlayerController {
    static let shared = VideoPlayerController()

    let player: AVPlayer
    private(set) var activeAssetID: String?
    private(set) var activeRequestID: PHImageRequestID?
    private(set) var isPlaying: Bool = false
    private(set) var isMuted: Bool = true

    nonisolated(unsafe) private var endObserverToken: NSObjectProtocol?

    init() {
        let avPlayer = AVPlayer()
        avPlayer.actionAtItemEnd = .none
        avPlayer.isMuted = true
        self.player = avPlayer

        setupLoopingObserver()
        configureAudioSession(muted: true)
    }

    deinit {
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Загрузка видео с защитой от гонок и видео-призраков

    /// Загружает видео для актива, отменяя предыдущий запрос и очищая текущий плеер
    func loadVideo(for asset: PHAsset) {
        // 1. Отмена предыдущего запроса PhotoKit
        if let reqID = activeRequestID {
            PHImageManager.default().cancelImageRequest(reqID)
            activeRequestID = nil
        }

        // 2. Остановка и очистка плеера
        player.pause()
        isPlaying = false
        player.replaceCurrentItem(with: nil)

        let targetAssetID = asset.localIdentifier
        self.activeAssetID = targetAssetID

        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        let reqID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }

                // КРАСНАЯ ЛИНИЯ: Защита от видео-призрака
                guard self.activeAssetID == targetAssetID else {
                    return
                }

                guard let playerItem = item else {
                    return
                }

                self.player.replaceCurrentItem(with: playerItem)
                self.player.isMuted = self.isMuted
                self.player.play()
                self.isPlaying = true
            }
        }
        self.activeRequestID = reqID
    }

    // MARK: - Управление воспроизведением

    func play() {
        guard player.currentItem != nil else { return }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    // MARK: - Умная AVAudioSession

    func toggleMute() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player.isMuted = muted
        configureAudioSession(muted: muted)
    }

    private func configureAudioSession(muted: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if muted {
                // ambient не прерывает фоновую музыку пользователя
                try session.setCategory(.ambient, options: .mixWithOthers)
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            } else {
                // playback играет даже при аппаратном беззвучном переключателе
                try session.setCategory(.playback, options: .mixWithOthers)
                try session.setActive(true)
            }
        } catch {
            // Мягкая обработка без fatalError / crash
        }
    }

    // MARK: - Обработка жизненного цикла приложения

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if isPlaying && player.currentItem != nil {
                player.play()
            }
        case .inactive, .background:
            pause()
            configureAudioSession(muted: true)
        @unknown default:
            break
        }
    }

    // MARK: - Очистка

    func reset() {
        if let reqID = activeRequestID {
            PHImageManager.default().cancelImageRequest(reqID)
            activeRequestID = nil
        }
        activeAssetID = nil
        pause()
        player.replaceCurrentItem(with: nil)
        setMuted(true)
    }

    // MARK: - Зацикливание видео

    private func setupLoopingObserver() {
        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let item = notification.object as? AVPlayerItem,
                  item == self.player.currentItem else {
                return
            }
            self.player.seek(to: .zero)
            self.player.play()
            self.isPlaying = true
        }
    }
}
