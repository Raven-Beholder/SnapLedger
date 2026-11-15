import SwiftUI
#if os(iOS)
import UIKit
#endif

struct IMESafeTextField: View {
    let placeholder: String
    @Binding var text: String
    let alignment: TextAlignment

    init(
        _ placeholder: String,
        text: Binding<String>,
        alignment: TextAlignment = .trailing
    ) {
        self.placeholder = placeholder
        _text = text
        self.alignment = alignment
    }

    var body: some View {
        #if os(iOS)
        IMESafeUITextField(
            placeholder: placeholder,
            text: $text,
            alignment: alignment
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

#if os(iOS)
private struct IMESafeUITextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let alignment: TextAlignment

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField(frame: .zero)
        field.placeholder = placeholder
        field.text = text
        field.textAlignment = alignment == .leading ? .left : .right
        field.adjustsFontForContentSizeCategory = true
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

        // Never replace text while an IME is composing marked text. Doing so
        // commits or splits the first pinyin syllable before the user selects it.
        guard field.markedTextRange == nil, field.text != text else { return }
        field.text = text
    }

    @MainActor
    final class Coordinator: NSObject {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func textDidChange(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }
    }
}
#endif
