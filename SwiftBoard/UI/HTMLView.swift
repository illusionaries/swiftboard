import SwiftUI
import WebKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Renders Blackboard's HTML bodies with a stylesheet that matches the app's
/// typography, in both light and dark appearances.
struct HTMLView: View {
    let html: String
    var baseURL: URL? = URL(string: "https://course.pku.edu.cn")

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PlatformWebView(html: document, baseURL: baseURL, isDark: colorScheme == .dark)
            .background(Color.clear)
    }

    private var document: String {
        let dark = colorScheme == .dark
        return """
        <!DOCTYPE html>
        <html class="\(dark ? "dark" : "light")">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        body {
            margin: 0;
            padding: 16px 20px 28px;
            font-family: -apple-system, "PingFang SC", "Helvetica Neue", sans-serif;
            font-size: 16px;
            line-height: 1.72;
            word-wrap: break-word;
            -webkit-text-size-adjust: 100%;
            background: transparent;
            color: #1c1c1e;
        }
        html.dark body { color: #e8e8ea; }
        h1, h2, h3, h4 { line-height: 1.35; margin: 1.2em 0 0.5em; font-weight: 650; }
        h1 { font-size: 1.45em; } h2 { font-size: 1.3em; } h3 { font-size: 1.15em; }
        p { margin: 0.72em 0; }
        ul, ol { padding-left: 1.35em; margin: 0.72em 0; }
        li { margin: 0.24em 0; }
        a { color: #A6192E; text-decoration: none; }
        html.dark a { color: #F08A98; }
        img, video, svg { max-width: 100%; height: auto; border-radius: 10px; }
        table { width: 100%; border-collapse: collapse; margin: 1em 0; font-size: 0.94em; display: block; overflow-x: auto; }
        th, td { border: 1px solid rgba(127,127,127,0.32); padding: 8px 10px; text-align: left; }
        th { background: rgba(127,127,127,0.08); }
        blockquote { margin: 1em 0; padding: 4px 14px; border-left: 3px solid #A6192E; color: inherit; opacity: 0.82; }
        pre { overflow-x: auto; background: rgba(127,127,127,0.10); padding: 12px 14px; border-radius: 10px; }
        code { font-family: "SF Mono", Menlo, monospace; font-size: 0.9em; background: rgba(127,127,127,0.12); padding: 1px 5px; border-radius: 4px; }
        hr { border: none; border-top: 1px solid rgba(127,127,127,0.26); margin: 1.5em 0; }
        ::selection { background: rgba(166,25,46,0.22); }
        .vtbegenerated { display: block; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }
}

#if os(iOS)
private struct PlatformWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    let isDark: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.dataDetectorTypes = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInset = .zero
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(html: html, isDark: isDark, baseURL: baseURL, in: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var lastHTML: String?
        private var lastDark: Bool?

        func load(html: String, isDark: Bool, baseURL: URL?, in webView: WKWebView) {
            guard html != lastHTML || isDark != lastDark else { return }
            lastHTML = html
            lastDark = isDark
            let store = WKWebsiteDataStore.default().httpCookieStore
            Task { @MainActor in
                let cookies = (HTTPCookieStorage.shared.cookies ?? []).filter { $0.domain.hasSuffix("pku.edu.cn") }
                for cookie in cookies {
                    await store.setCookie(cookie)
                }
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
#elseif os(macOS)
private struct PlatformWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let isDark: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(html: html, isDark: isDark, baseURL: baseURL, in: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var lastHTML: String?
        private var lastDark: Bool?

        func load(html: String, isDark: Bool, baseURL: URL?, in webView: WKWebView) {
            guard html != lastHTML || isDark != lastDark else { return }
            lastHTML = html
            lastDark = isDark
            let store = WKWebsiteDataStore.default().httpCookieStore
            Task { @MainActor in
                let cookies = (HTTPCookieStorage.shared.cookies ?? []).filter { $0.domain.hasSuffix("pku.edu.cn") }
                for cookie in cookies {
                    await store.setCookie(cookie)
                }
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
#endif
