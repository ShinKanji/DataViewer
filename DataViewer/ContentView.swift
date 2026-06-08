import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: DataViewModel
    @State private var contentSize: CGSize = .zero

    private var workspaceLayout: WorkspaceLayout {
        WorkspaceLayout.current(contentSize: contentSize)
    }

    var body: some View {
        Group {
            switch workspaceLayout {
            case .tabbed:
                tabbedRoot
            case .split:
                splitRoot
            }
        }
        .onGeometryChange(for: CGSize.self) { geometry in
            geometry.size
        } action: { newSize in
            contentSize = newSize
        }
        .workspaceLayout(workspaceLayout)
        .overlay {
            if viewModel.isUITestFixturesReady {
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityElement()
                    .accessibilityIdentifier("uiTestFixturesReady")
            }
        }
        .alert(String(localized: "错误", comment: "Error alert title"), isPresented: errorBinding) {
            Button(String(localized: "确定", comment: "Confirm button"), role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var tabbedRoot: some View {
        TabView {
            NavigationStack {
                ChannelSelectorView(viewModel: viewModel)
                    .navigationTitle(String(localized: "信号", comment: "Signals tab title"))
            }
            .tabItem {
                Label(String(localized: "信号", comment: "Signals tab item label"),
                      systemImage: "line.3.horizontal.decrease.circle")
            }

            NavigationStack {
                PlotAreaView(viewModel: viewModel)
                    .navigationTitle(String(localized: "曲线", comment: "Plots tab title"))
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label(String(localized: "曲线", comment: "Plots tab item label"),
                      systemImage: "chart.xyaxis.line")
            }

            NavigationStack {
                StatisticsView(viewModel: viewModel)
                    .navigationTitle(String(localized: "统计", comment: "Statistics tab title"))
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label(String(localized: "统计", comment: "Statistics tab item label"),
                      systemImage: "chart.bar.doc.horizontal")
            }

            NavigationStack {
                SignalComputeSheet(viewModel: viewModel)
                    .navigationTitle(String(localized: "计算", comment: "Compute tab title"))
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label(String(localized: "计算", comment: "Compute tab item label"),
                      systemImage: "function")
            }
        }
    }

    private var splitRoot: some View {
        DataViewerSplitView(viewModel: viewModel)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}

#Preview {
    ContentView(viewModel: DataViewModel())
}
