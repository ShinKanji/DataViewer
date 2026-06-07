import SwiftUI

extension View {
    func channelListDensity() -> some View {
        listSectionSpacing(Constants.listSectionSpacing)
            .environment(\.defaultMinListRowHeight, Constants.minRowHeight)
    }

    func channelListRowInsets() -> some View {
        listRowInsets(
            EdgeInsets(
                top: Constants.rowVerticalInset,
                leading: Constants.rowHorizontalInset,
                bottom: Constants.rowVerticalInset,
                trailing: Constants.rowHorizontalInset
            )
        )
    }
}

struct ChannelListStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.plain)
    }
}
