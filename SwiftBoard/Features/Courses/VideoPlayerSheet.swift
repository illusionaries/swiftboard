import SwiftUI
import AVKit
import AVFoundation
import Combine
import SwiftBoardKit
#if os(iOS)
import AVFAudio
#endif
#if os(macOS)
import AppKit
#endif

struct VideoPlayerSheet: View {
    let video: CourseVideo

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = VideoPlayerController()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                playerArea
                infoArea
                Spacer(minLength: 0)
            }
            .background(Theme.canvas)
            .navigationTitle("回放")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task {
            await controller.load(video: video, service: model.client.blackboard.videos)
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                controller.pause()
            }
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 640)
        #endif
    }

    private var playerArea: some View {
        ZStack {
            Color.black
            switch controller.state {
            case .loading:
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("正在准备回放…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 30, weight: .light))
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重试") {
                        Task {
                            await controller.load(video: video, service: model.client.blackboard.videos)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .foregroundStyle(.white)
                .padding(24)
                .frame(maxWidth: 420)
            case .ready:
                if let player = controller.player {
                    #if os(macOS)
                    MacVideoPlayer(player: player)
                    #else
                    VideoPlayer(player: player)
                    #endif
                }
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 14) {
                if !video.teacher.isEmpty {
                    Label(video.teacher, systemImage: "person")
                }
                if !video.time.isEmpty {
                    Label(video.time, systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .lineLimit(1)

            Text("回放由北大在线课堂提供，仅对已选课同学开放，请勿传播。")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
@Observable
final class VideoPlayerController {
    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var player: AVPlayer?
    private var item: AVPlayerItem?
    private var videoServer: LocalVideoServer?
    private var statusCancellable: AnyCancellable?
    private var shouldAutoplay = true

    func load(video: CourseVideo, service: CourseVideoService) async {
        stop()
        shouldAutoplay = true
        state = .loading

        do {
            let prepared = try await service.prepare(video: video)
            let server = LocalVideoServer(keys: prepared.keys)
            let port = try await server.start()
            self.videoServer = server
            var playlist = prepared.playlist
            if !prepared.keys.isEmpty {
                playlist = playlist.replacingOccurrences(
                    of: "swiftboard-key://key/",
                    with: "http://127.0.0.1:\(port)/key/"
                )
            }
            server.setPlaylist(playlist)
            guard let url = URL(string: "http://127.0.0.1:\(port)/playlist.m3u8") else {
                throw VideoError.invalidPlaylist
            }
            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.automaticallyWaitsToMinimizeStalling = true

            self.item = item
            self.player = player

            #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif

            statusCancellable = item.publisher(for: \.status)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    guard let self else { return }
                    switch status {
                    case .readyToPlay:
                        self.state = .ready
                        if self.shouldAutoplay {
                            self.player?.play()
                        }
                    case .failed:
                        self.state = .failed(item.error?.localizedDescription ?? "回放加载失败")
                    default:
                        break
                    }
                }
            if shouldAutoplay {
                player.play()
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func pause() {
        shouldAutoplay = false
        player?.pause()
    }

    func stop() {
        player?.pause()
        statusCancellable?.cancel()
        statusCancellable = nil
        player = nil
        item = nil
        videoServer?.stop()
        videoServer = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}


#if os(macOS)
private struct MacVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
#endif
