import SwiftUI

struct PlotGroupingPanel: View {
    @Bindable var viewModel: DataViewModel
    @State private var isShowingRenameAlert = false
    @State private var renameGroupText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.controlSpacing) {
            GroupingPanelHeader(viewModel: viewModel)
            GroupingPanelBody(
                viewModel: viewModel,
                isShowingRenameAlert: $isShowingRenameAlert,
                renameGroupText: $renameGroupText
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Constants.panelPadding)
        .padding(.top, Constants.panelPadding)
        .padding(.bottom, Constants.panelPadding)
        .alert(String(localized: "重命名分组", comment: "Rename group alert title"),
               isPresented: $isShowingRenameAlert) {
            TextField(String(localized: "分组名称", comment: "Group name text field placeholder"),
                      text: $renameGroupText)
            Button(String(localized: "取消", comment: "Cancel button"), role: .cancel) {}
            Button(String(localized: "确定", comment: "Confirm button")) {
                viewModel.renameActiveGroup(to: renameGroupText)
            }
        } message: {
            Text(String(localized: "输入新的分组名称", comment: "Rename group alert message"))
        }
    }
}

private struct GroupingPanelHeader: View {
    @Bindable var viewModel: DataViewModel

    var body: some View {
        HStack {
            Text(String(localized: "分组", comment: "Plot grouping panel title"))
                .font(.headline)
            Spacer()
            Button {
                viewModel.createGroup()
            } label: {
                Label(String(localized: "新建", comment: "Create new group button"),
                      systemImage: "plus")
            }
            .glassControl(.secondary, size: .compact)
            .disabled(viewModel.selectedPlottedIDs.count < 2)
            .modifier(PlatformHelpModifier(text: String(localized: "选中至少两个已选信号后新建分组",
                                                         comment: "New group button help")))
        }
    }
}

private struct GroupingPanelBody: View {
    @Bindable var viewModel: DataViewModel
    @Binding var isShowingRenameAlert: Bool
    @Binding var renameGroupText: String

    private var activeGroupPickerSelection: Binding<UUID?> {
        Binding(
            get: {
                let validIDs = Set(viewModel.groupingEligibleGroups.map(\.id))
                if let active = viewModel.activeGroupID, validIDs.contains(active) {
                    return active
                }
                return viewModel.groupingEligibleGroups.first?.id
            },
            set: { viewModel.activeGroupID = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.controlSpacing) {
            if viewModel.groupingEligibleGroups.isEmpty {
                Text(String(localized: "暂无分组", comment: "No plot groups placeholder"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker(String(localized: "当前分组", comment: "Current group picker"),
                       selection: activeGroupPickerSelection) {
                    ForEach(viewModel.groupingEligibleGroups) { group in
                        Text(viewModel.plotGroupTitle(for: group)).tag(Optional(group.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LiquidGlassButtonGroup {
                HStack(spacing: Constants.controlSpacingTight) {
                    Button(String(localized: "重命名", comment: "Rename group button")) {
                        if let activeGroupID = viewModel.activeGroupID,
                           let group = viewModel.groupingEligibleGroups.first(where: { $0.id == activeGroupID }) {
                            renameGroupText = group.name
                            isShowingRenameAlert = true
                        }
                    }
                    .glassControl(.secondary, size: .compact)
                    .disabled(viewModel.activeGroupID == nil)
                    .accessibilityIdentifier("renameGroupButton")

                    Button(String(localized: "加入", comment: "Add signals to group button")) {
                        viewModel.assignSelectedPlottedToActiveGroup()
                    }
                    .glassControl(.secondary, size: .compact)
                    .disabled(viewModel.selectedPlottedIDs.isEmpty || viewModel.activeGroupID == nil || viewModel.groupingEligibleGroups.isEmpty)
                    .accessibilityIdentifier("assignToActiveGroupButton")
                }
            }
        }
    }
}
