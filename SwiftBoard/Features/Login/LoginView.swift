import SwiftUI
import SwiftBoardKit

struct LoginView: View {
    @Environment(AppModel.self) private var model

    @State private var username = ""
    @State private var password = ""
    @State private var otp = ""
    @State private var remember = true
    @State private var showPassword = false
    @State private var needsOTP = false
    @State private var needsCaptcha = false
    @State private var randCode = ""
    @State private var captchaNonce = UUID()
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var showHelp = false
    @State private var showOfflineReplays = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case username
        case password
        case otp
        case captcha
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 900 {
                HStack(spacing: 0) {
                    hero
                        .frame(width: max(430, proxy.size.width * 0.47))
                    formPanel
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        compactHero
                            .frame(height: 290)
                        formCard
                            .padding(.horizontal, 20)
                            .offset(y: -44)
                        Text("非官方客户端 · 数据来自 course.pku.edu.cn")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 6)
                            .padding(.bottom, 30)
                    }
                }
                .background(Theme.canvas)
                .ignoresSafeArea(edges: .top)
            }
        }
        .background(Theme.canvas)
        .sheet(isPresented: $showOfflineReplays) {
            NavigationStack {
                ReplayDownloadsView(showsCloseButton: true)
                    .environment(model)
            }
        }
        .task {
            if username.isEmpty {
                #if DEBUG
                if ProcessInfo.processInfo.environment["SWIFTBOARD_DEMO"] == "1" {
                    username = "0000000000"
                } else {
                    username = UserDefaults.standard.string(forKey: "lastUsername") ?? ""
                }
                #else
                username = UserDefaults.standard.string(forKey: "lastUsername") ?? ""
                #endif
            }
            errorMessage = model.sessionMessage
            #if DEBUG
            if ProcessInfo.processInfo.environment["SWIFTBOARD_FORCE_CAPTCHA"] == "1" {
                needsCaptcha = true
            }
            if ProcessInfo.processInfo.environment["SWIFTBOARD_LOGIN_OFFLINE"] == "1",
               showOfflineReplays == false,
               !model.replayDownloads.items.isEmpty {
                showOfflineReplays = true
            }
            #endif
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            Theme.heroGradient
            rings
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    AcademicMark(size: 42, monochrome: true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("SwiftBoard")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text("北京大学教学网")
                            .font(.caption)
                            .opacity(0.66)
                    }
                }
                .foregroundStyle(.white)

                Spacer(minLength: 30)

                Text("把课堂\n装进口袋")
                    .font(.system(size: 46, weight: .bold))
                    .lineSpacing(4)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)

                Text("课程资料、课程通知、作业截止与成绩，\n一个清爽的客户端就够了。")
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.top, 16)

                VStack(alignment: .leading, spacing: 13) {
                    feature("books.vertical", "课程内容与文件集中浏览")
                    feature("megaphone", "通知与作业截止一目了然")
                    feature("chart.bar.xaxis", "成绩动态及时同步")
                }
                .padding(.top, 34)

                Spacer(minLength: 30)

                Text("非官方客户端 · 数据来自 course.pku.edu.cn")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(48)
        }
        .ignoresSafeArea()
    }

    private var compactHero: some View {
        ZStack {
            Theme.heroGradient
            rings.opacity(0.8)
            VStack(spacing: 10) {
                AcademicMark(size: 58, monochrome: true)
                Text("SwiftBoard")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("北京大学教学网")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .clipped()
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.86))
        }
    }

    private var rings: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let radius = min(size.width, size.height) * 0.9
                for index in 0..<6 {
                    let inset = CGFloat(index) * 52
                    let rect = CGRect(
                        x: size.width * 0.55 - radius + inset,
                        y: size.height * 0.42 - radius + inset,
                        width: radius * 2 - inset * 2,
                        height: radius * 2 - inset * 2
                    )
                    context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.055)), lineWidth: 1)
                }
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height * 0.78))
                line.addLine(to: CGPoint(x: size.width, y: size.height * 0.55))
                context.stroke(line, with: .color(.white.opacity(0.05)), lineWidth: 1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Form

    private var formPanel: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack {
                    Spacer(minLength: 40)
                    formContent
                        .cardSurface(padding: 28, radius: 24)
                        .frame(maxWidth: 420)
                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
                .padding(.horizontal, 36)
            }
            .background(Theme.canvas)
        }
    }

    private var formCard: some View {
        formContent
            .cardSurface(padding: 24, radius: 24)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("登录教学网")
                    .font(.system(size: 28, weight: .bold))
                Text("使用学号与北大统一身份认证密码")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            VStack(spacing: 12) {
                inputField(
                    icon: "person.text.rectangle",
                    placeholder: "学号",
                    text: $username,
                    field: .username,
                    secure: false
                )
                passwordField
                if needsCaptcha {
                    captchaField
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if needsOTP {
                    inputField(
                        icon: "number.square",
                        placeholder: "手机令牌验证码",
                        text: $otp,
                        field: .otp,
                        secure: false
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                        .padding(.top, 2)
                    Text(errorMessage)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.red.opacity(0.85))
                .transition(.opacity)
            }

            HStack(spacing: 10) {
                Toggle(isOn: $remember) {
                    Text("记住我")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .fixedSize()

                Spacer()

                Button {
                    showHelp = true
                } label: {
                    Text("登录遇到问题？")
                        .font(.footnote)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                    helpContent
                        .padding(18)
                        .frame(width: 300)
                }
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                        Text("正在登录…")
                    } else {
                        Text("登录")
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            canSubmit
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Theme.accentBright, Theme.accentDeep],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                : AnyShapeStyle(Theme.field)
                        )
                }
                .foregroundStyle(canSubmit ? Color.white : Theme.muted)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .animation(.easeInOut(duration: 0.15), value: canSubmit)

            Text("密码仅保存在本机钥匙串中，不会上传到任何第三方服务器。")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !model.replayDownloads.items.isEmpty {
                Button {
                    showOfflineReplays = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("离线回放")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("无需登录，观看已下载的课程")
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 8)
                        Text("\(model.replayDownloads.items.count) 节")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 52)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private var captchaField: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 18)
            TextField("验证码", text: $randCode)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focus, equals: .captcha)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            Button {
                captchaNonce = UUID()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.white)
                    AsyncImage(url: captchaURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        default:
                            ProgressView().controlSize(.mini)
                        }
                    }
                    .padding(2)
                }
                .frame(width: 84, height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("刷新验证码")
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focus == .captcha ? Theme.accent.opacity(0.55) : Theme.stroke, lineWidth: focus == .captcha ? 1.4 : 0.8)
        }
    }

    private var captchaURL: URL? {
        var components = URLComponents(string: "https://iaaa.pku.edu.cn/iaaa/servlet/DrawServlet")
        components?.queryItems = [URLQueryItem(name: "Rand", value: captchaNonce.uuidString)]
        return components?.url
    }

    private var passwordField: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 18)
            Group {
                if showPassword {
                    TextField("密码", text: $password)
                } else {
                    SecureField("密码", text: $password)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .focused($focus, equals: .password)
            .submitLabel(.go)
            .onSubmit(submit)
            #if os(iOS)
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            #endif
            .onChange(of: password) { _, value in
                // IAAA passwords are ASCII. macOS IME can otherwise commit
                // full-width punctuation such as "！" into the field.
                let sanitized = String(value.filter { $0.isASCII })
                if sanitized != value {
                    password = sanitized
                }
            }

            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showPassword ? "隐藏密码" : "显示密码")
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focus == .password ? Theme.accent.opacity(0.55) : Theme.stroke, lineWidth: focus == .password ? 1.4 : 0.8)
        }
    }

    private func inputField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        secure: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 18)
            if secure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focus, equals: field)
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focus, equals: field)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(field == .otp ? .numberPad : .default)
                    #endif
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focus == field ? Theme.accent.opacity(0.55) : Theme.stroke, lineWidth: focus == field ? 1.4 : 0.8)
        }
        .onSubmit {
            if field == .username { focus = .password }
            if field == .otp { submit() }
        }
        .submitLabel(field == .username ? .next : .go)
        #if os(iOS)
        .textContentType(field == .username ? .username : .oneTimeCode)
        #endif
    }

    private var helpContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关于登录")
                .font(.headline)
            Text("• 账号为学号（10 位数字），密码为北大统一身份认证密码。")
            Text("• 如果开启了手机令牌，登录时会出现验证码输入框。")
            Text("• 如果提示需要图形验证码，输入右侧图片中的 4 个字符。")
            Text("• 如果提示“登录尝试过于频繁”，请等待半小时后再试。")
            Text("• 也可以前往 course.pku.edu.cn 使用网页端登录。")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var canSubmit: Bool {
        !isSubmitting
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && (!needsOTP || !otp.isEmpty)
            && (!needsCaptcha || randCode.count >= 4)
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        isSubmitting = true
        errorMessage = nil
        model.sessionMessage = nil

        Task {
            do {
                try await model.signIn(
                    username: username,
                    password: password,
                    otp: otp,
                    remember: remember,
                    randCode: randCode
                )
            } catch let api as APIError {
                if case .login(let message, let code) = api {
                    errorMessage = message
                    if code == "E05" || code == "E04" {
                        needsOTP = code == "E05"
                        if needsOTP { focus = .otp }
                    } else if code == "E03" {
                        needsCaptcha = true
                        randCode = ""
                        captchaNonce = UUID()
                        focus = .captcha
                    }
                } else {
                    errorMessage = api.localizedDescription
                }
                isSubmitting = false
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
