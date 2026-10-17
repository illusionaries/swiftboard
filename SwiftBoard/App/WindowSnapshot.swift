#if DEBUG && os(macOS)
import AppKit

/// Debug helper: renders the app's window into a PNG without requiring screen
/// recording permissions. Used by the development snapshot workflow.
enum WindowSnapshot {
    @MainActor
    static func capture(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.contentView != nil }) else {
            log("no window to capture")
            return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        guard let view = window.contentView else { return }
        let bounds = view.bounds
        guard bounds.width > 10, bounds.height > 10 else {
            log("window has no size")
            return
        }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            log("cannot create bitmap representation")
            return
        }
        view.layoutSubtreeIfNeeded()
        view.cacheDisplay(in: bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            log("wrote snapshot to \(path) (\(Int(bounds.width))x\(Int(bounds.height)))")
        }

        // A PDF capture keeps vector/AppKit-drawn subviews (e.g. the sidebar)
        // that cacheDisplay sometimes skips because they live in layers.
        let pdfURL = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("pdf")
        let pdf = view.dataWithPDF(inside: bounds)
        try? pdf.write(to: pdfURL)
        log("wrote pdf to \(pdfURL.path)")
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data(("[snapshot] " + message + "\n").utf8))
    }
}
#endif
