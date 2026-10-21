#if os(macOS)
import SwiftUI
import AppKit

/// AppKit-backed password field for macOS.
///
/// SwiftUI's SecureField does not expose the field editor, so an active
/// Chinese/Japanese input method can commit full-width punctuation into the
/// password. Browsers that disable IME for password fields do so at the
/// AppKit text input layer; this wrapper restricts the field editor to Roman
/// input sources and also filters non-ASCII text as a fallback.
struct MacPasswordField: NSViewRepresentable {
    @Binding var text: String
    let isSecure: Bool
    let placeholder: String
    let onSubmit: () -> Void
    let onFocusChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = isSecure
            ? NSSecureTextField(frame: .zero)
            : NSTextField(frame: .zero)
        field.delegate = context.coordinator
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        field.textColor = .labelColor
        field.placeholderString = placeholder
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byClipping
        field.isAutomaticTextCompletionEnabled = false
        if let cell = field.cell as? NSTextFieldCell {
            cell.isScrollable = true
            cell.wraps = false
        }
        field.setAccessibilityLabel(placeholder)
        field.stringValue = text
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.currentEditor() == nil, nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacPasswordField

        init(_ parent: MacPasswordField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
            restrictInputSources(notification)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        func controlTextDidChange(_ notification: Notification) {
            restrictInputSources(notification)
            guard let field = notification.object as? NSTextField else { return }
            let filtered = String(field.stringValue.filter { $0.isASCII })
            if filtered != field.stringValue {
                field.stringValue = filtered
            }
            if parent.text != filtered {
                parent.text = filtered
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }

        private func restrictInputSources(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let editor = field.currentEditor() as? NSTextView else { return }
            editor.allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]
        }
    }
}
#endif
