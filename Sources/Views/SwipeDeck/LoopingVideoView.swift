import SwiftUI
import AVFoundation
import UIKit

/// UIViewRepresentable для отображения AVPlayer через AVPlayerLayer.
/// Обеспечивает videoGravity .resizeAspectFill и отсутствие force unwrap.
struct LoopingVideoView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.setPlayer(player)
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.setPlayer(player)
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer? {
        layer as? AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        playerLayer?.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        playerLayer?.videoGravity = .resizeAspectFill
    }

    func setPlayer(_ player: AVPlayer) {
        if playerLayer?.player !== player {
            playerLayer?.player = player
        }
        playerLayer?.videoGravity = .resizeAspectFill
    }
}
