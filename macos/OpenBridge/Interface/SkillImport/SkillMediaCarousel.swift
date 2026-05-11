import AVKit
import SwiftUI

/// Native AVPlayerView wrapper that bypasses SwiftUI's VideoPlayer
/// to avoid _AVKit_SwiftUI metadata crashes and control constraint conflicts
private struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context _: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context _: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

/// A media carousel that displays video (priority) or image fallback
struct SkillMediaCarousel: View {
    let videoURL: String?
    let heroURL: String?

    @State private var player: AVPlayer?
    @State private var isVideoLoaded = false
    @State private var videoLoadFailed = false

    var body: some View {
        Group {
            if let videoURLString = videoURL,
               let url = URL(string: videoURLString),
               !videoLoadFailed
            {
                videoPlayerView(url: url)
            } else if let heroURLString = heroURL,
                      let url = URL(string: heroURLString)
            {
                heroImageView(url: url)
            } else {
                placeholderView
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.5))
        }
    }

    // MARK: - Video Player

    private func videoPlayerView(url: URL) -> some View {
        Group {
            if let player {
                NativeVideoPlayer(player: player)
            } else {
                Color.clear
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .onAppear {
            setupPlayer(url: url)
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .overlay {
            if !isVideoLoaded {
                loadingOverlay
            }
        }
    }

    private func setupPlayer(url: URL) {
        // Download video to temp file first to avoid presigned URL issues with AVPlayer
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let httpResponse = response as? HTTPURLResponse
                let statusCode = httpResponse?.statusCode ?? -1

                guard statusCode == 200, data.count > 1000 else {
                    await MainActor.run {
                        videoLoadFailed = true
                    }
                    return
                }

                // Write to temp file
                let tempDir = FileManager.default.temporaryDirectory
                let destURL = tempDir.appendingPathComponent(UUID().uuidString + ".mp4")
                try data.write(to: destURL)

                await MainActor.run {
                    createPlayer(from: destURL)
                }
            } catch {
                await MainActor.run {
                    videoLoadFailed = true
                }
            }
        }
    }

    private func createPlayer(from localURL: URL) {
        let asset = AVURLAsset(url: localURL)
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.isMuted = true

        // Listen for loop playback
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            newPlayer.seek(to: .zero)
            newPlayer.play()
        }

        // Check asset playability before playing
        Task {
            do {
                let isPlayable = try await asset.load(.isPlayable)

                await MainActor.run {
                    if isPlayable {
                        isVideoLoaded = true
                        newPlayer.play()
                    } else {
                        videoLoadFailed = true
                    }
                }
            } catch {
                await MainActor.run {
                    videoLoadFailed = true
                }
            }
        }

        player = newPlayer
    }

    // MARK: - Hero Image

    private func heroImageView(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                loadingOverlay
            case let .success(image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                placeholderView
            @unknown default:
                placeholderView
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }

    // MARK: - Helpers

    private var loadingOverlay: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                ProgressView()
            }
    }

    private var placeholderView: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }
}

#Preview {
    VStack(spacing: 20) {
        SkillMediaCarousel(
            videoURL: nil,
            heroURL: "https://via.placeholder.com/800x450"
        )
        .frame(height: 200)

        SkillMediaCarousel(
            videoURL: nil,
            heroURL: nil
        )
        .frame(height: 200)
    }
    .padding()
}
