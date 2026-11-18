import SwiftUI
#if os(iOS)
import UIKit
#endif

struct IMESafeTextField: View {
    let placeholder: String
    @Binding var text: String
    let alignment: TextAlignment
    let isFocused: Binding<Bool>?
    let onSubmit: (() -> Void)?

    init(
        _ placeholder: String,
        text: Binding<String>,
        alignment: TextAlignment = .trailing,
        isFocused: Binding<Bool>? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        _text = text
        self.alignment = alignment
        self.isFocused = isFocused
        self.onSubmit = onSubmit
    }

    var body: some View {
        #if os(iOS)
        IMESafeUITextField(
            placeholder: placeholder,
            text: $text,
            alignment: alignment,
            isFocused: isFocused,
            onSubmit: onSubmit
        )
        .frame(minHeight: 24)
        #else
        TextField(text: $text, prompt: Text(placeholder)) {
            Text(placeholder)
        }
            .labelsHidden()
            .multilineTextAlignment(alignment)
        #endif
    }
}

struct IMESafeTextEditor: View {
    @Binding var text: String
    let isFocused: Binding<Bool>?

    init(text: Binding<String>, isFocused: Binding<Bool>? = nil) {
        _text = text
        self.isFocused = isFocused
    }

    var body: some View {
        #if os(iOS)
        IMESafeUITextView(text: $text, isFocused: isFocused)
        #else
        TextEditor(text: $text)
        #endif
    }
}

#if os(iOS)
private struct IMESafeUITextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let alignment: TextAlignment
    let isFocused: Binding<Bool>?
    let onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField(frame: .zero)
        field.placeholder = placeholder
        field.text = text
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.textAlignment = alignment == .leading ? .left : .right
        field.adjustsFontForContentSizeCategory = true
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        field.placeholder = placeholder
        field.textAlignment = alignment == .leading ? .left : .right
        context.coordinator.text = $text
        context.coordinator.isFocused = isFocused
        context.coordinator.onSubmit = onSubmit

        if let isFocused {
            if isFocused.wrappedValue, !field.isFirstResponder {
                DispatchQueue.main.async { field.becomeFirstResponder() }
            } else if !isFocused.wrappedValue, field.isFirstResponder {
                field.resignFirstResponder()
            }
        }

        // Never replace text while an IME is composing marked text. Doing so
        // commits or splits the first pinyin syllable before the user selects it.
        if field.markedTextRange == nil, field.text != text {
            field.text = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>?
        var onSubmit: (() -> Void)?

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>?,
            onSubmit: (() -> Void)?
        ) {
            self.text = text
            self.isFocused = isFocused
            self.onSubmit = onSubmit
        }

        @objc func textDidChange(_ field: UITextField) {
            guard field.markedTextRange == nil else { return }
            text.wrappedValue = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isFocused?.wrappedValue = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isFocused?.wrappedValue = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            guard textField.markedTextRange == nil else { return false }
            onSubmit?()
            return false
        }
    }
}

private struct IMESafeUITextView: UIViewRepresentable {
    @Binding var text: String
    let isFocused: Binding<Bool>?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(frame: .zero)
        textView.text = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = isFocused

        if let isFocused {
            if isFocused.wrappedValue, !textView.isFirstResponder {
                DispatchQueue.main.async { textView.becomeFirstResponder() }
            } else if !isFocused.wrappedValue, textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }

        guard textView.markedTextRange == nil, textView.text != text else { return }
        textView.text = text
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>?

        init(text: Binding<String>, isFocused: Binding<Bool>?) {
            self.text = text
            self.isFocused = isFocused
        }

        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            text.wrappedValue = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFocused?.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFocused?.wrappedValue = false
        }
    }
}
#endif
