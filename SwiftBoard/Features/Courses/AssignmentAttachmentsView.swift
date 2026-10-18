import SwiftUI
import SwiftBoardKit

struct AssignmentAttachmentsView: View {
    let attachments: [AssignmentAttachment]
    let course: Course

    @Environment(AppModel.self) private var model
    @Environment(DownloadCenter.self) private var downloads

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("作业附件", systemImage: "paperclip")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(attachments.count) 个")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }

            ForEach(attachments) { attachment in
                row(attachment)
            }

            Text("附件会下载到本机，并使用系统预览打开。")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
        .cardSurface(padding: 16, radius: 16)
    }

    @ViewBuilder
    private func row(_ attachment: AssignmentAttachment) -> some View {
        let state = downloads.state(for: attachment)
        let localURL = downloads.existingFile(for: attachment, course: course)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "doc")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18)
                Text(attachment.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)

                if let state, state.isDownloading {
                    ProgressView()
                        .controlSize(.mini)
                    Button {
                        downloads.cancel(attachment)
                    } label: {
                        Text("取消")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                } else if let localURL {
                    Button {
                        downloads.preview(attachment, course: course, api: model.client.blackboard)
                    } label: {
                        Label("预览", systemImage: "eye")
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)

                    ShareLink(item: localURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .foregroundStyle(Theme.muted)
                } else {
                    Button {
                        downloads.preview(attachment, course: course, api: model.client.blackboard)
                    } label: {
                        Label("下载并预览", systemImage: "arrow.down.circle")
                            .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
            }

            if let state, state.isDownloading {
                ProgressView(value: state.progress)
                    .tint(Theme.accent)
                    .controlSize(.mini)
            } else if let state, let error = state.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.85))
            } else if localURL != nil {
                Text("已下载")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
