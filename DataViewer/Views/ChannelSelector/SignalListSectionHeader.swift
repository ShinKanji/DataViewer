import SwiftUI

struct SignalListSectionHeader: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.title3.weight(.bold))
            .padding(.horizontal, Constants.rowHorizontalInset)
            .padding(.top, Constants.channelBlockTitleTopPadding)
    }
}
