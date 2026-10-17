import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.phase {
            case .booting:
                SplashView()
                    .transition(.opacity)
            case .login:
                LoginView()
                    .transition(.opacity)
            case .ready:
                MainShell()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: model.phase)
        .background(Theme.canvas)
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.heroGradient
                .ignoresSafeArea()

            GeometryReader { proxy in
                Canvas { context, size in
                    for index in 0..<5 {
                        let inset = CGFloat(index) * 46
                        let rect = CGRect(
                            x: -size.width * 0.25 + inset,
                            y: size.height * 0.55 + inset,
                            width: size.width * 1.5 - inset * 2,
                            height: size.width * 1.5 - inset * 2
                        )
                        context.stroke(
                            Path(ellipseIn: rect),
                            with: .color(.white.opacity(0.06)),
                            lineWidth: 1
                        )
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .ignoresSafeArea()

            VStack(spacing: 16) {
                AcademicMark(size: 86, monochrome: true)
                Text("SwiftBoard")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("北京大学教学网")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                ProgressView()
                    .tint(.white)
                    .padding(.top, 10)
            }
        }
    }
}
