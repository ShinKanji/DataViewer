import SwiftUI

extension View {
    func minimumTouchTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
    }
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
