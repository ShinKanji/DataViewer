import SwiftUI

struct ChannelRowView: View {
    let channel: ChannelDescriptor
    var viewModel: DataViewModel

    var body: some View {
        Text(viewModel.friendlyName(for: channel))
            .font(.subheadline)
            .lineLimit(1)
    }
}
