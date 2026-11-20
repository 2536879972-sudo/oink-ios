import SwiftUI

/// 启动动画：拥抱视频 + 文字淡入
struct SplashView: View {
    @State private var videoScale: CGFloat = 1.0
    @State private var textOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 视频（没有视频则降级为静态图/纯色）
            if let url = Bundle.main.url(forResource: "hug", withExtension: "mp4") {
                LoopingVideo(url: url)
                    .scaledToFill()
                    .ignoresSafeArea()
                    .scaleEffect(videoScale)
            } else if let img = UIImage(named: "LaunchImage") {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .scaleEffect(videoScale)
            }

            // 暗角
            RadialGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.85)]),
                center: .center,
                startRadius: 80,
                endRadius: 420
            )
            .ignoresSafeArea()

            // 水印遮挡（右下角）
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 120, height: 36)
                        .blur(radius: 14)
                        .padding(.trailing, 6)
                        .padding(.bottom, 6)
                }
            }
            .ignoresSafeArea()

            // 文字
            VStack {
                Spacer()
                VStack(spacing: 8) {
                    Text("哀世界")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 12)
                    Text("Chat with AI")
                        .font(.system(size: 12, weight: .medium))
                        .tracking(2.4)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .opacity(textOpacity)
                .padding(.bottom, 60)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 2.0)) {
                videoScale = 1.08
            }
            withAnimation(.easeOut(duration: 0.7).delay(1.0)) {
                textOpacity = 1
            }
        }
    }
}

// MARK: - 循环视频播放器

import AVKit

struct LoopingVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.play(url: url)
        return v
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}

    final class PlayerContainerView: UIView {
        private var playerLayer: AVPlayerLayer?
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        func play(url: URL) {
            let item = AVPlayerItem(url: url)
            let p = AVQueuePlayer()
            p.isMuted = true
            looper = AVPlayerLooper(player: p, templateItem: item)
            player = p

            let layer = AVPlayerLayer(player: p)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            self.layer.addSublayer(layer)
            playerLayer = layer

            p.play()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer?.frame = bounds
        }
    }
}
