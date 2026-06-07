import SwiftUI

struct SignalCandidateListView: View {
    @Bindable var viewModel: DataViewModel
    @Binding var isSelectionMode: Bool
    @State private var lastAddTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.channelBlockSpacing) {
            SignalListSectionHeader(
                title: String(localized: "候选信号", comment: "Candidate signals section header")
            )

            candidateList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sensoryFeedback(.success, trigger: lastAddTrigger)
    }

    @ViewBuilder
    private var candidateList: some View {
        if isSelectionMode {
            selectionList
        } else {
            browseList
        }
    }

    private var browseList: some View {
        List {
            candidateRows
        }
        .modifier(ChannelListStyleModifier())
        .channelListDensity()
        .accessibilityIdentifier("candidateList")
    }

    private var selectionList: some View {
        List(selection: $viewModel.selectedCandidateIDs) {
            candidateRows
        }
        .modifier(ChannelListStyleModifier())
        .channelListDensity()
        .environment(\.editMode, .constant(.active))
        .accessibilityIdentifier("candidateListSelectionMode")
    }

    @ViewBuilder
    private var candidateRows: some View {
        if groupedCandidates.keys.count == 1 {
            ForEach(viewModel.availableCandidates) { channel in
                candidateListRow(channel)
                    .tag(channel.id)
                    .channelListRowInsets()
            }
        } else {
            ForEach(groupedCandidates.keys.sorted(), id: \.self) { key in
                channelListSection(key) {
                    ForEach(groupedCandidates[key] ?? []) { channel in
                        candidateListRow(channel)
                            .tag(channel.id)
                            .channelListRowInsets()
                    }
                }
            }
        }
    }

    private var groupedCandidates: [String: [ChannelDescriptor]] {
        Dictionary(grouping: viewModel.availableCandidates) { channel in
            channel.containerName
        }
    }

    @ViewBuilder
    private func channelListSection<Content: View>(_ key: String, @ViewBuilder content: () -> Content) -> some View {
        Section {
            content()
        } header: {
            Text(key)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func candidateListRow(_ channel: ChannelDescriptor) -> some View {
        if isSelectionMode {
            ChannelRowView(channel: channel, viewModel: viewModel)
                .channelNameAccessory(channel.displayName)
        } else {
            Button {
                if viewModel.addCandidatesToPlot([channel.id]) {
                    lastAddTrigger += 1
                }
            } label: {
                ChannelRowView(channel: channel, viewModel: viewModel)
                    .channelNameAccessory(channel.displayName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(CandidateDragSourceModifier(channel: channel, viewModel: viewModel))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    if viewModel.addCandidatesToPlot([channel.id]) {
                        lastAddTrigger += 1
                    }
                } label: {
                    Label(String(localized: "添加", comment: "Add candidate signal swipe action"),
                          systemImage: "plus.circle.fill")
                }
                .tint(.accentColor)
            }
            .accessibilityAction(named: String(localized: "添加到曲线", comment: "Add to plot accessibility action")) {
                if viewModel.addCandidatesToPlot([channel.id]) {
                    lastAddTrigger += 1
                }
            }
        }
    }
}
