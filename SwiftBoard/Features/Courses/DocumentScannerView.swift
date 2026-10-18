#if os(iOS)
import SwiftUI
import UIKit
import VisionKit

struct DocumentScannerView: UIViewControllerRepresentable {
    let onFinish: (VNDocumentCameraScan) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: DocumentScannerView

        init(_ parent: DocumentScannerView) {
            self.parent = parent
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            parent.onFinish(scan)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            parent.onError(error)
        }
    }
}

enum ScannedDocumentPDF {
    static func make(from scan: VNDocumentCameraScan) throws -> URL {
        guard scan.pageCount > 0 else {
            throw ScanError.noPages
        }

        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 at 72 dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            for pageIndex in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: pageIndex)
                context.beginPage()

                let content = pageBounds.insetBy(dx: 28, dy: 32)
                let scale = min(content.width / image.size.width, content.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let rect = CGRect(
                    x: content.midX - size.width / 2,
                    y: content.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                image.draw(in: rect)
            }
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftBoardScans", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("scan.pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    enum ScanError: Error, LocalizedError {
        case noPages

        var errorDescription: String? {
            switch self {
            case .noPages: "没有扫描到任何页面"
            }
        }
    }
}

struct ScanNameSheet: View {
    @Binding var name: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("给扫描的 PDF 起一个文件名")
                    .font(.headline)
                Text("提交前可以修改；扩展名会自动补全为 .pdf。")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)

                TextField("扫描文稿", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        if !trimmedName.isEmpty { save() }
                    }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("命名扫描文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(250))
                focused = true
            }
        }
        .presentationDetents([.height(250)])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave()
        dismiss()
    }
}
#endif
