import SwiftUI
import SwiftBoardKit

struct ReplayDownloadsView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: ReplayDownload?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if model.replayDownloads.items.isEmpty {
                    EmptyStateView(
                        symbol: "arrow.down.circle",
                        title: "还没有离线回放",
                        message: "在课程回放的播放器里点「下载」，就会出现在这里。"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.replayDownloads.items.enumerated()), id: \.element.id) { index, item in
                            row(item)
                            if index < model.replayDownloads.items.count - 1 {
                                Divider().padding(.leading, 66)
                            }
                        }
                    }
                    .cardSurface(padding: 0, radius: 18)

                    Text("共 \(model.replayDownloads.items.count) 个，\(totalSizeText)。仅保存在本机，退出登录会清除。")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .navigationTitle("离线回放")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $selected) { item in
            VideoPlayerSheet(download: item)
                .environment(model)
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["SWIFTBOARD_OFFLINE"] == "1",
               selected == nil,
               let first = model.replayDownloads.items.first {
                selected = first
            }
            #endif
        }
    }

    private func row(_ item: ReplayDownload) -> some View {
        HStack(spacing: 4) {
            Button {
                selected = item
            } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: "play.fill", tint: Theme.accent, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(item.courseTitle)
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                        Text("\(item.teacher) · \(durationText(item.duration)) · \(sizeText(item.totalBytes))")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("删除下载", role: .destructive) {
                    if selected?.id == item.id { selected = nil }
                    model.replayDownloads.delete(item)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 34, height: 40)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
    }

    private var totalSizeText: String {
        let total = model.replayDownloads.items.reduce(Int64(0)) { $0 + $1.totalBytes }
        return sizeText(total)
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, total % 60)
        }
        return String(format: "%d:%02d", minutes, total % 60)
    }
}
