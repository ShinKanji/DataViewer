import SwiftUI

extension View {
    func minimumTouchTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
    }

    func numericKeyboardDoneToolbar(
        isActive: Bool,
        accessibilityIdentifier: String = "numericKeyboardDoneButton",
        onDone: @escaping () -> Void
    ) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                numericKeyboardDoneButton(
                    accessibilityIdentifier: accessibilityIdentifier,
                    action: onDone
                )
                .disabled(!isActive)
            }
        }
    }
}

@ViewBuilder
func numericKeyboardDoneButton(
    accessibilityIdentifier: String,
    action: @escaping () -> Void
) -> some View {
    Button(String(localized: "完成", comment: "Done editing numeric field button"), action: action)
        .glassControl(.inline, size: .compact)
        .accessibilityIdentifier(accessibilityIdentifier)
}

struct PhoneCompactSheetModifier: ViewModifier {
    @Environment(\.workspaceLayout) private var workspaceLayout

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #else
        content
        #endif
    }
}
