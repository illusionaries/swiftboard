import SwiftUI
import SwiftBoardKit

struct ReplayExportSheet: View {
    let download: ReplayDownload

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var state: ExportState = .working

    private enum ExportState {
        case working
        case ready(URL)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                switch state {
                case .working:
                    ProgressView()
                        .controlSize(.large)
                    Text("正在导出视频…")
                        .font(.headline)
                    Text("两小时的回放可能需要几分钟，请保持 App 在前台。")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                case .ready(let url):
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(Theme.accent)
                    Text("导出完成")
                        .font(.headline)
                    Text(fileDescription(url))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    if url.pathExtension.lowercased() == "ts" {
                        Text("iOS 端导出为 TS 文件，可用 VLC 等播放器打开；macOS 端可直接导出 MP4。")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    ShareLink(item: url, preview: SharePreview(download.title)) {
                        Label("分享 / 保存到文件", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    Button("完成") { dismiss() }
                        .buttonStyle(.bordered)
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.accent)
                    Text("导出失败")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await export() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    Button("关闭") { dismiss() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
            .navigationTitle("导出视频")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task { await export() }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }

    private func export() async {
        state = .working
        do {
            let url = try await model.replayDownloads.exportVideo(download)
            state = .ready(url)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func fileDescription(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        return "\(url.lastPathComponent) · \(formatted)"
    }
}
