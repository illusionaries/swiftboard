import SwiftUI
import SwiftBoardKit

struct CourseVideosSection: View {
    let course: Course

    @Environment(AppModel.self) private var model
    @State private var videos: [CourseVideo]?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedVideo: CourseVideo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "课程回放",
                subtitle: videos.map { "\($0.count) 节课" },
                actionTitle: "刷新",
                showsChevron: false,
                action: { Task { await load(force: true) } }
            )

            if isLoading && videos == nil {
                LoadingRows(count: 3)
            } else if let errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await load(force: true) }
                }
            } else if let videos, videos.isEmpty {
                EmptyStateView(
                    symbol: "play.rectangle",
                    title: "暂无课程回放",
                    message: "老师还没有上传这门课的回放。"
                )
            } else if let videos {
                VStack(spacing: 0) {
                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                        Button {
                            selectedVideo = video
                        } label: {
                            videoRow(video)
                        }
                        .buttonStyle(.plain)

                        if index < videos.count - 1 {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
                .cardSurface(padding: 0, radius: 18)

                Text("回放由北大在线课堂提供，仅对已选课同学开放，请勿传播。")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: course.id) { await load() }
        .sheet(item: $selectedVideo) { video in
            VideoPlayerSheet(video: video, course: course)
                .environment(model)
        }
    }

    private func videoRow(_ video: CourseVideo) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: "play.fill", tint: Theme.accent, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    if !video.time.isEmpty {
                        Text(video.time)
                    }
                    if !video.time.isEmpty && !video.teacher.isEmpty {
                        Text("·")
                    }
                    if !video.teacher.isEmpty {
                        Text(video.teacher)
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if model.replayDownloads.item(for: video.id) != nil {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("已下载")
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func load(force: Bool = false) async {
        if !force, videos != nil { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let items = try await model.client.blackboard.videos.list(courseID: course.id)
            videos = items
            #if DEBUG
            if ProcessInfo.processInfo.environment["SWIFTBOARD_VIDEO"] == "1",
               selectedVideo == nil,
               let first = items.first {
                selectedVideo = first
            }
            #endif
        } catch {
            if let api = error as? APIError, case .notAuthenticated = api {
                model.expireSession()
            }
            errorMessage = error.localizedDescription
        }
    }
}
