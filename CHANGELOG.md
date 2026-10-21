# Changelog

本项目使用语义化版本。版本号来自 Git tag，并与 `project.yml` 中的 `MARKETING_VERSION` 保持一致。

## [Unreleased]

## [1.0.1] - 2026-10-21

### 新增

- 课程「教学内容」中的文档现在会显示全部课件/视频附件，支持逐个下载和 Quick Look 预览。
- 作业提交文件在上传前可以点击铅笔重命名，保留原扩展名并自动清理非法字符。
- 登录状态过期时，如果钥匙串中保存了「记住我」凭据，会自动静默重新登录，而不是直接退出到登录页。
- macOS 密码框改用 AppKit `NSSecureTextField`，通过 `allowedInputSourceLocales` 限制为 Roman 输入源，避免中文输入法提交全角标点。
- iOS 密码键盘使用 `.asciiCapable`，并关闭自动大写与自动纠错。

### 变更

- 密码输入统一过滤非 ASCII 字符，防止 IME 或粘贴输入中文、全角符号。
- Release workflow 的版本校验更严格：tag 版本必须与 `project.yml` 的 `MARKETING_VERSION` 一致。
- Release 说明中增加 CHANGELOG 链接。

### 修复

- 修复部分课程文档在挂载多个课件或视频时，只显示正文、不显示附件的问题。
- 修复登录过期后直接回登录页、忽略已保存密码的问题。
- 修复 macOS 中文输入法可以向密码框输入「！」等全角字符的问题。
- 修复已选择作业文件后无法在提交前修改上传文件名的问题。

## [1.0.0] - 2026-10-19

首个公开版本。

### 新增

- 北大统一身份认证登录：RSA 密码加密、手机令牌、图形验证码、钥匙串保存登录凭据与 Cookie。
- 首页概览：本学期课程、即将截止作业、最新通知；首页统计胶囊可点击跳转。
- 课程浏览：按学期分组、课程搜索、内容/回放/通知/成绩/信息五个分页。
- 课程内容：文件夹浏览、文件下载、Quick Look 预览、分享与保存。
- 课程回放：在线 HLS 播放、原生全屏、原生播放器倍速/AirPlay/PiP、AES-128 下载解密、离线播放、导出、iOS 26+ 后台下载。
- 作业：提交文件/留言、提交记录、教师附件下载预览、扫描纸质文稿生成 PDF、提交次数限制检测与拦截、提交前预览。
- 通知：课程通知聚合、按课程筛选、搜索、HTML 正文渲染。
- 成绩：本学期成绩总览、已发布成绩、逐项得分与作业/内容跳转。
- 截止提醒：本地通知，支持截止前 24 小时/1 小时提醒和测试通知。
- 离线回放：登录页可直接进入已下载回放；退出登录会清理下载。
- 多平台界面：iPhone Tab、iPad/Mac 分栏、深色模式、动态字体、Quick Look、分享、键盘快捷键。
- 设置：外观模式、数据刷新、缓存清理、离线回放管理、通知开关、GitHub 仓库入口。
- CI：GitHub Actions 运行 SwiftBoardKit 测试，构建 iOS Simulator 与 macOS App。
- Release：推送 `v*` tag 构建 Universal macOS zip、unsigned IPA 和 SHA256 校验文件。

### 说明

- 发布产物未签名、未公证；iOS IPA 需要自行重签后安装。
- iOS 端导出为 TS（受 AVFoundation 限制），macOS 导出 MP4。
- 暂不支持 Widget、后台推送、新公告实时提醒、多文件提交、小组作业和在线测试。

[Unreleased]: https://github.com/illusionaries/swiftboard/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/illusionaries/swiftboard/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/illusionaries/swiftboard/releases/tag/v1.0.0
