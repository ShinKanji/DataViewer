import SwiftUI

struct DataViewerSplitView: View {
    @Bindable var viewModel: DataViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredColumn: NavigationSplitViewColumn = .detail

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredColumn
        ) {
            ChannelSelectorView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(
                    min: Constants.sidebarMinWidth,
                    ideal: Constants.sidebarIdealWidth,
                    max: Constants.sidebarMaxWidth
                )
        } detail: {
            SplitDetailWorkspaceView(viewModel: viewModel)
        }
    }
}

#Preview {
    DataViewerSplitView(viewModel: DataViewModel())
        .workspaceLayout(.split)
}
