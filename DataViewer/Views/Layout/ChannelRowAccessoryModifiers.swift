import SwiftUI

struct PlatformHelpModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content.accessibilityHint(text)
    }
}

extension View {
    func channelNameAccessory(_ fullName: String) -> some View {
        modifier(PlatformHelpModifier(text: fullName))
    }
}
