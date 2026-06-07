import SwiftUI

struct SignalBrowserView: View {
    @Bindable var viewModel: DataViewModel
    @Binding var isCandidateSelectionMode: Bool

    var body: some View {
        VStack(spacing: Constants.channelBlockSpacing) {
            SignalCandidateListView(
                viewModel: viewModel,
                isSelectionMode: $isCandidateSelectionMode
            )
            .frame(maxHeight: .infinity)

            SignalSelectedListView(viewModel: viewModel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity)
    }
}
