import SwiftUI
import SwiftBoardKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @AppStorage("appearance") private var appearance = "system"

    @State private var confirmSignOut = false
    @State private var isClearing = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                profileCard
                accountSection
                appearanceSection
                dataSection
                replaySection
                aboutSection
                signOutButton
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 44)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .navigationTitle("我的")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog("退出登录？", isPresented: $confirmSignOut) {
            Button("退出登录", role: .destructive) {
                Task { await model.signOut() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除本机保存的登录状态与缓存，账号密码会从钥匙串中移除。")
        }
    }

    // MARK: - Profile

    private var profileCard: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x741020), Color(hex: 0x9E1B32), Color(hex: 0xB93A4B)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: 190)
                .offset(x: 60, y: -80)

            HStack(spacing: 15) {
                if let profile = model.profile {
                    AvatarView(initials: profile.initials, size: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.displayName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(profile.email.isEmpty ? profile.userName : profile.email)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 6) {
                            Text("学号 \(profile.userName)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.55))
                            if let role = profile.systemRole, !role.isEmpty, role != "无" {
                                Text("·")
                                    .foregroundStyle(.white.opacity(0.35))
                                Text(role)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }
                    Spacer()
                    AcademicMark(size: 40, monochrome: true)
                        .opacity(0.9)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .padding(20)
        }
        .frame(height: 108)
        .shadow(color: Theme.accentDeep.opacity(0.2), radius: 14, y: 8)
    }

    // MARK: - Sections

    private var accountSection: some View {
        SettingsGroup(title: "账户") {
            SettingsValueRow(label: "学号", value: model.profile?.userName ?? "—")
            divider
            SettingsValueRow(label: "邮箱", value: model.profile?.email ?? "—")
            divider
            SettingsValueRow(label: "最近同步", value: model.lastUpdated.map(SBDate.time) ?? "尚未同步")
            divider
            SettingsValueRow(label: "课程", value: "\(model.courses.count) 门")
        }
    }

    private var appearanceSection: some View {
        SettingsGroup(title: "外观") {
            VStack(alignment: .leading, spacing: 10) {
                Text("外观模式")
                    .font(.subheadline)
                Picker("外观", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(14)
        }
    }

    private var dataSection: some View {
        SettingsGroup(title: "数据") {
            Button {
                Task { await model.refreshAll() }
            } label: {
                SettingsActionRow(
                    symbol: "arrow.clockwise",
                    title: "立即刷新",
                    detail: model.isRefreshing ? "正在同步…" : nil,
                    tint: Theme.accent
                )
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)

            divider

            Button {
                isClearing = true
                model.clearCache()
                Task {
                    await model.refreshAll()
                    isClearing = false
                }
            } label: {
                SettingsActionRow(
                    symbol: "trash",
                    title: "清除缓存并刷新",
                    detail: isClearing ? "正在处理…" : (model.hasCachedData ? "有离线缓存" : nil),
                    tint: Theme.muted
                )
            }
            .buttonStyle(.plain)
            .disabled(isClearing)
        }
    }

    private var replaySection: some View {
        SettingsGroup(title: "离线回放") {
            NavigationLink {
                ReplayDownloadsView()
            } label: {
                SettingsActionRow(
                    symbol: "arrow.down.circle",
                    title: "已下载的回放",
                    detail: model.replayDownloads.items.isEmpty
                        ? "暂无下载"
                        : "\(model.replayDownloads.items.count) 个",
                    tint: Theme.accent
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutSection: some View {
        SettingsGroup(title: "关于") {
            SettingsValueRow(label: "版本", value: version)
            divider
            SettingsValueRow(label: "名称", value: "SwiftBoard")
            divider
            Button {
                openURL(URL(string: "https://course.pku.edu.cn")!)
            } label: {
                SettingsActionRow(symbol: "globe", title: "北京大学教学网", detail: "course.pku.edu.cn", tint: Theme.accent)
            }
            .buttonStyle(.plain)
            divider
            Button {
                openURL(URL(string: "https://github.com/sshwy/pku3b")!)
            } label: {
                SettingsActionRow(symbol: "heart", title: "致谢 pku3b", detail: "Blackboard 接口探索", tint: Color(hex: 0xB3263B))
            }
            .buttonStyle(.plain)
            divider
            VStack(alignment: .leading, spacing: 4) {
                Text("非官方客户端")
                    .font(.subheadline)
                Text("SwiftBoard 由学生开发，与北京大学及 Blackboard 官方无关。登录信息仅保存在本机钥匙串中，所有数据直接来自 course.pku.edu.cn。")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
    }

    private var signOutButton: some View {
        Button {
            confirmSignOut = true
        } label: {
            Text("退出登录")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.red.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.14), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        Text("SwiftBoard · 用 SwiftUI 为 iOS、iPadOS 与 macOS 打造")
            .font(.caption2)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var divider: some View {
        Divider().padding(.leading, 14)
    }
}

// MARK: - Building blocks

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .padding(.leading, 5)
            VStack(spacing: 0) {
                content
            }
            .cardSurface(padding: 0, radius: 16)
        }
    }
}

struct SettingsValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct SettingsActionRow: View {
    let symbol: String
    let title: String
    var detail: String?
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 11) {
            IconTile(symbol: symbol, tint: tint, size: 28)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
