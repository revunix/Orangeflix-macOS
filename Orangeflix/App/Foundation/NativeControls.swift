import AppKit
import SwiftUI

/// The search field of a sidebar, drawn by AppKit. It brings the magnifier,
/// the corner radius and the clear button of every other Mac app with it —
/// a hand built field never looks like the standard one.
struct NativeSearchField: NSViewRepresentable {
    /// The text the user types.
    @Binding var text: String
    /// The text shown while the field is empty.
    var placeholder: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        field.controlSize = .regular
        return field
    }

    func updateNSView(_ view: NSSearchField, context: Context) {
        view.placeholderString = placeholder
        if view.stringValue != text { view.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    /// Hands the text of the field back to the view.
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

/// The way back and forth as one glass capsule with a divider between the
/// two arrows, grouped the way the buttons of a toolbar are.
struct GlassBackForward: View {
    /// Whether the way back leads to a visited area.
    var canGoBack: Bool
    /// Whether the way forth leads to a visited area.
    var canGoForward: Bool
    /// Called with `-1` for the way back and `1` for the way forth.
    var onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", label: "Zurück", enabled: canGoBack, direction: -1)
            Rectangle()
                .fill(.primary.opacity(0.18))
                .frame(width: 1, height: 14)
            arrow("chevron.right", label: "Weiter", enabled: canGoForward, direction: 1)
        }
        .glassPlate(in: Capsule(), interactive: true)
    }

    private func arrow(_ symbol: String, label: String, enabled: Bool, direction: Int) -> some View {
        Button {
            onStep(direction)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary.opacity(enabled ? 1 : 0.3))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}
