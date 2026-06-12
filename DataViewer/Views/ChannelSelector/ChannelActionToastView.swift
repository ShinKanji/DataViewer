import SwiftUI

struct ChannelActionToastView: View {
    let toast: ChannelActionToast
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: Constants.controlSpacing) {
            Text(toast.message)
                .font(.subheadline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(String(localized: "撤销", comment: "Undo channel mutation button"), action: onUndo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .glassControl(.inline, touchTarget: true)
                .accessibilityIdentifier("channelActionUndoButton")
        }
        .padding(.horizontal, Constants.toolbarHorizontalInset)
        .padding(.vertical, Constants.toolbarVerticalInset)
        .liquidGlassFloatingPanel(cornerRadius: Constants.cornerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("channelActionToast")
        .accessibilityHint(String(localized: "双击撤销上一次操作", comment: "Undo toast accessibility hint"))
        .accessibilityAction(named: String(localized: "撤销", comment: "Undo accessibility action")) {
            onUndo()
        }
    }
}
