import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ChannelDragPayload: Codable, Hashable, Sendable, Transferable {
    let channelIDs: [UUID]

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .dataViewerChannelDrag)
    }
}

extension UTType {
    static let dataViewerChannelDrag = UTType(exportedAs: "com.dataviewer.channel-drag")
}

enum ChannelCandidateDropStyle {
    case fullFrameContentShape
    case overlayAboveContent
}

extension View {
    func channelCandidateDropDestination(
        viewModel: DataViewModel,
        style: ChannelCandidateDropStyle = .fullFrameContentShape
    ) -> some View {
        modifier(ChannelCandidateDropDestinationModifier(viewModel: viewModel, style: style))
    }
}

private struct ChannelCandidateDropDestinationModifier: ViewModifier {
    @Bindable var viewModel: DataViewModel
    let style: ChannelCandidateDropStyle
    @State private var isDropTargeted = false

    func body(content: Content) -> some View {
        switch style {
        case .fullFrameContentShape:
            content
                .contentShape(Rectangle())
                .dropDestination(for: ChannelDragPayload.self, action: handleDrop, isTargeted: handleTargeted)
                .overlay { dropTargetHighlight }
        case .overlayAboveContent:
            // List 会拦截拖放，需在内容上方加透明接收层。
            content
                .overlay {
                    ChannelDropTargetLayer(
                        viewModel: viewModel,
                        isDropTargeted: $isDropTargeted,
                        allowsHitTestingWhenNotTargeted: true
                    )
                }
                .overlay { dropTargetHighlight }
        }
    }

    private func handleDrop(items: [ChannelDragPayload], _: CGPoint) -> Bool {
        let ids = items.flatMap(\.channelIDs)
        return viewModel.addCandidatesFromDrag(ids)
    }

    private func handleTargeted(_ targeted: Bool) {
        isDropTargeted = targeted
        if targeted {
            PlotChannelsDropFeedback.dropTargetChanged(to: true)
        }
    }

    @ViewBuilder
    private var dropTargetHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 2)
                .padding(4)
                .allowsHitTesting(false)
        }
    }
}

private struct ChannelDropTargetLayer: View {
    @Bindable var viewModel: DataViewModel
    @Binding var isDropTargeted: Bool
    var allowsHitTestingWhenNotTargeted: Bool

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(true)
            .dropDestination(for: ChannelDragPayload.self) { items, _ in
                let ids = items.flatMap(\.channelIDs)
                return viewModel.addCandidatesFromDrag(ids)
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
    }
}
