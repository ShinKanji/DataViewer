import SwiftUI

struct OptionalAccessibilityIdentifierModifier: ViewModifier {
    let id: String?

    func body(content: Content) -> some View {
        if let id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}

extension View {
    func optionalAccessibilityIdentifier(_ id: String?) -> some View {
        modifier(OptionalAccessibilityIdentifierModifier(id: id))
    }
}

struct CandidateDragSourceModifier: ViewModifier {
    let channel: ChannelDescriptor
    @Bindable var viewModel: DataViewModel

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .draggable(viewModel.candidateDragPayload(for: channel))
            .accessibilityLabel(viewModel.friendlyName(for: channel))
    }
}
