import SwiftUI
import SwiftBoardKit
import UserNotifications

@main
struct SwiftBoardApp: App {
    @State private var model = AppModel()
    @State private var router = AppRouter()
    @State private var downloads = DownloadCenter()
    @AppStorage("appearance") private var appearance = "system"

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    @SceneBuilder
    var body: some Scene {
        mainWindow
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(model)
                .environment(router)
                .environment(downloads)
                .preferredColorScheme(preferredScheme)
                .frame(width: 580, height: 640)
        }
        #endif
    }

    private var mainWindow: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(router)
                .environment(downloads)
                .tint(Theme.accent)
                .preferredColorScheme(preferredScheme)
                .task {
                    #if DEBUG
                    let environment = ProcessInfo.processInfo.environment
                    if environment["SWIFTBOARD_RESET"] == "1" {
                        await model.signOut()
                    }
                    await model.bootstrap()
                    if environment["SWIFTBOARD_NOTIFICATION_TEST"] == "1" {
                        _ = await model.deadlineNotifications.setEnabled(true, deadlines: model.deadlines)
                        await model.deadlineNotifications.sendTestNotification()
                    }
                    if environment["SWIFTBOARD_FORCE_LOGIN"] == "1" {
                        model.expireSession()
                    }
                    if let route = environment["SWIFTBOARD_ROUTE"] {
                        let parts = route.split(separator: ":").map(String.init)
                        if parts.first == "content", parts.count >= 3 {
                            await router.openDebugContent(courseID: parts[1], contentID: parts[2], model: model)
                        } else {
                            router.apply(debugRoute: route, model: model)
                        }
                    }
                    if let preview = environment["SWIFTBOARD_PREVIEW"] {
                        let parts = preview.split(separator: ":").map(String.init)
                        if parts.count >= 2,
                           let item = await model.debugFindContent(courseID: parts[0], contentID: parts[1]),
                           let course = model.course(id: parts[0]) {
                            downloads.preview(item, course: course, api: model.client.blackboard)
                        }
                    }
                    #else
                    await model.bootstrap()
                    #endif

                    #if DEBUG && os(macOS)
                    if let snapshot = ProcessInfo.processInfo.environment["SWIFTBOARD_SNAPSHOT"] {
                        try? await Task.sleep(for: .seconds(3))
                        WindowSnapshot.capture(to: snapshot)
                    }
                    #endif
                }
                .onOpenURL { router.handle($0, model: model) }
        }
        .defaultSize(width: 1220, height: 820)
        #if os(macOS)
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新") {
                    Task { await model.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("首页") { router.section = .home }
                    .keyboardShortcut("1", modifiers: .command)
                Button("我的课程") { router.section = .courses }
                    .keyboardShortcut("2", modifiers: .command)
                Button("通知") { router.section = .announcements }
                    .keyboardShortcut("3", modifiers: .command)
                Button("成绩") { router.section = .grades }
                    .keyboardShortcut("4", modifiers: .command)
            }
        }
        #endif
    }

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
