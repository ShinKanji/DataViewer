import SwiftUI

private enum SplitDetailTab: Int, CaseIterable, Hashable {
    case plot
    case statistics
    case compute

    var title: String {
        switch self {
        case .plot:
            String(localized: "曲线", comment: "Plots tab title")
        case .statistics:
            String(localized: "统计", comment: "Statistics tab title")
        case .compute:
            String(localized: "计算", comment: "Compute tab title")
        }
    }
}

struct SplitDetailWorkspaceView: View {
    @Bindable var viewModel: DataViewModel
    @State private var selectedTab: SplitDetailTab = .plot

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                PlotAreaView(viewModel: viewModel)
                    .tag(SplitDetailTab.plot)
                    .tabItem {
                        Label(String(localized: "曲线", comment: "Plots tab item label"),
                              systemImage: "chart.xyaxis.line")
                    }

                StatisticsView(viewModel: viewModel)
                    .tag(SplitDetailTab.statistics)
                    .tabItem {
                        Label(String(localized: "统计", comment: "Statistics tab item label"),
                              systemImage: "chart.bar.doc.horizontal")
                    }

                SignalComputeSheet(viewModel: viewModel)
                    .tag(SplitDetailTab.compute)
                    .tabItem {
                        Label(String(localized: "计算", comment: "Compute tab item label"),
                              systemImage: "function")
                    }
            }
            .navigationTitle(selectedTab.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

#Preview {
    SplitDetailWorkspaceView(viewModel: DataViewModel())
        .workspaceLayout(.split)
}
