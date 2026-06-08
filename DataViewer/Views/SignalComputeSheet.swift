import SwiftUI

enum SignalComputeOperation: String, CaseIterable, Identifiable {
    case scale
    case deriv
    case integ
    case movmean
    case dejump
    case headingUnwrap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scale: return String(localized: "倍率", comment: "Scale operation title")
        case .deriv: return String(localized: "求导 d/dt", comment: "Derivative operation title")
        case .integ: return String(localized: "积分 ∫dt", comment: "Integration operation title")
        case .movmean: return String(localized: "滑动平均", comment: "Moving average operation title")
        case .dejump: return String(localized: "去跳点", comment: "Jump point removal operation title")
        case .headingUnwrap: return String(localized: "角度连续化", comment: "Heading angle unwrap operation title")
        }
    }

    var segmentedTitle: String {
        switch self {
        case .scale:
            String(localized: "倍率", comment: "Short scale operation label for segmented control")
        case .deriv:
            String(localized: "求导", comment: "Short derivative operation label for segmented control")
        case .integ:
            String(localized: "积分", comment: "Short integration operation label for segmented control")
        case .movmean:
            String(localized: "滑动平均", comment: "Short moving average operation label for segmented control")
        case .dejump:
            String(localized: "去跳点", comment: "Short jump removal operation label for picker")
        case .headingUnwrap:
            String(localized: "角度连续化", comment: "Short heading unwrap operation label for picker")
        }
    }

    static func availableOperations(hasHeadingAngleChannels: Bool) -> [SignalComputeOperation] {
        var operations: [SignalComputeOperation] = [.scale, .deriv, .integ, .movmean, .dejump]
        if hasHeadingAngleChannels {
            operations.append(.headingUnwrap)
        }
        return operations
    }
}

struct SignalComputeSheet: View {
    @Bindable var viewModel: DataViewModel

    @State private var operation: SignalComputeOperation = .scale
    @State private var selectedChannelID: UUID?
    @State private var multiplierText = "1"
    @State private var windowText = "10"
    @State private var jumpThresholdText = ""
    @State private var feedback: ComputeResultFeedback?
    @State private var feedbackDismissTask: Task<Void, Never>?
    @State private var successFeedbackTrigger = 0
    @State private var errorFeedbackTrigger = 0
    @State private var operationChangeTrigger = 0
    @State private var slideResetTrigger = 0
    @FocusState private var focusedNumericField: NumericInputField?

    private enum NumericInputField: Hashable {
        case multiplier
        case window
        case jumpThreshold
    }

    init(viewModel: DataViewModel) {
        self.viewModel = viewModel
        _selectedChannelID = State(
            initialValue: Self.defaultSelectedChannelID(in: viewModel)
        )
    }

    var body: some View {
        ScrollView {
            if showsComputeUnavailable {
                ContentUnavailableView(
                    computeUnavailableTitle,
                    systemImage: "function",
                    description: Text(computeUnavailableDescription)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
                    configurationPanel
                    if operation == .scale {
                        resetPanel
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if let feedback {
                    ComputeResultBannerView(feedback: feedback)
                        .padding(.horizontal, Constants.toolbarHorizontalInset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                SlideToConfirmControl(
                    label: String(localized: "滑动以应用", comment: "Slide to apply label"),
                    isEnabled: !isApplyDisabled,
                    resetTrigger: slideResetTrigger,
                    onConfirm: confirmApplyOperation
                )
                .padding(.horizontal, Constants.toolbarHorizontalInset)
                .padding(.vertical, Constants.toolbarVerticalInset)
                .liquidGlassToolbarBackground()
                .accessibilityIdentifier("signalComputeApplyBar")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: feedback?.id)
        .onChange(of: viewModel.computeSourceChannelChoices.map(\.id)) { _, _ in
            syncSelectedChannelID()
        }
        .onChange(of: viewModel.hasSelectedHeadingAngleChannels) { _, hasHeading in
            syncAvailableOperation(hasHeadingAngleChannels: hasHeading)
        }
        .onChange(of: operation) { _, _ in
            dismissFeedback()
            operationChangeTrigger += 1
            slideResetTrigger += 1
        }
        .onChange(of: isApplyDisabled) { _, disabled in
            if disabled {
                slideResetTrigger += 1
            }
        }
        .numericKeyboardDoneToolbar(isActive: focusedNumericField != nil) {
            focusedNumericField = nil
        }
        .sensoryFeedback(.selection, trigger: operationChangeTrigger)
        .sensoryFeedback(.success, trigger: successFeedbackTrigger)
        .sensoryFeedback(.error, trigger: errorFeedbackTrigger)
    }

    private var showsComputeUnavailable: Bool {
        viewModel.computeSourceChannelChoices.isEmpty
    }

    private var computeUnavailableTitle: String {
        String(localized: "暂无可用信号", comment: "No available signals")
    }

    private var computeUnavailableDescription: String {
        String(
            localized: "请先在候选或已选区选择信号",
            comment: "Signal selection hint"
        )
    }

    private func confirmApplyOperation() {
        applyOperation()
        slideResetTrigger += 1
    }

    private static func defaultSelectedChannelID(in viewModel: DataViewModel) -> UUID? {
        let choices = viewModel.computeSourceChannelChoices
        let preferred = viewModel.defaultComputeSourceChannelID()
        let validIDs = Set(choices.map(\.id))
        if let preferred, validIDs.contains(preferred) {
            return preferred
        }
        return choices.first?.id
    }

    private func syncSelectedChannelID() {
        let validIDs = Set(viewModel.computeSourceChannelChoices.map(\.id))
        if let selectedChannelID, validIDs.contains(selectedChannelID) {
            return
        }
        selectedChannelID = Self.defaultSelectedChannelID(in: viewModel)
    }

    private var availableOperations: [SignalComputeOperation] {
        SignalComputeOperation.availableOperations(
            hasHeadingAngleChannels: viewModel.hasSelectedHeadingAngleChannels
        )
    }

    private func syncAvailableOperation(hasHeadingAngleChannels: Bool) {
        let operations = SignalComputeOperation.availableOperations(
            hasHeadingAngleChannels: hasHeadingAngleChannels
        )
        if !operations.contains(operation) {
            operation = .scale
        }
    }

    private var isApplyDisabled: Bool {
        switch operation {
        case .dejump:
            return viewModel.jumpRemovalTargetChannelIDs().isEmpty
        case .headingUnwrap:
            return viewModel.selectedHeadingAngleChannelIDs().isEmpty
        default:
            return selectedChannelID == nil || viewModel.computeSourceChannelChoices.isEmpty
        }
    }

    private var configurationPanel: some View {
        VStack(alignment: .leading, spacing: Constants.controlSpacing) {
            Text(String(localized: "配置", comment: "Configuration section title"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: Constants.controlSpacing) {
                Text(String(localized: "运算类型", comment: "Operation type section title"))
                    .font(.headline)

                Picker(
                    String(localized: "运算类型", comment: "Operation type picker"),
                    selection: $operation
                ) {
                    ForEach(availableOperations) { item in
                        Text(item.segmentedTitle).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("signalComputeOperationPicker")
            }

            if operation == .dejump {
                dejumpTargetSummary
            } else if operation == .headingUnwrap {
                headingUnwrapTargetSummary
            } else {
                VStack(alignment: .leading, spacing: Constants.controlSpacingTight) {
                    Text(String(localized: "源信号", comment: "Source signal label"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker(String(localized: "源信号", comment: "Source signal picker"),
                           selection: $selectedChannelID) {
                        ForEach(viewModel.computeSourceChannelChoices) { descriptor in
                            Text(viewModel.plotSeriesName(for: descriptor))
                                .tag(Optional(descriptor.id))
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("signalComputeChannelPicker")
                }
            }

            switch operation {
            case .scale:
                scaleParameterFields
            case .movmean:
                movingAverageParameterFields
            case .dejump:
                dejumpParameterFields
            case .headingUnwrap:
                EmptyView()
            case .deriv, .integ:
                EmptyView()
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Constants.sectionSpacing)
        .padding(.vertical, Constants.standardPadding)
        .contentSurface(.editingPanel)
    }

    private var scaleParameterFields: some View {
        Group {
            VStack(alignment: .leading, spacing: Constants.controlSpacingTight) {
                Text(String(localized: "倍率乘数", comment: "Scale multiplier field label"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                panelTextField(
                    String(localized: "例如 3.6", comment: "Multiplier placeholder"),
                    text: $multiplierText,
                    accessibilityID: "signalComputeMultiplierField",
                    field: .multiplier
                )
                    .keyboardType(.decimalPad)
            }

            if let channelID = selectedChannelID {
                LabeledContent(String(localized: "当前倍率", comment: "Current scale value")) {
                    Text(formatScale(viewModel.effectiveScale(for: channelID)))
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
        }
    }

    private var movingAverageParameterFields: some View {
        VStack(alignment: .leading, spacing: Constants.controlSpacingTight) {
            Text(String(localized: "窗口采样点数", comment: "Moving average window size label"))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            panelTextField(
                String(localized: "例如 10", comment: "Window size placeholder"),
                text: $windowText,
                accessibilityID: "signalComputeWindowField",
                field: .window
            )
                .keyboardType(.numberPad)
        }
    }

    private var dejumpTargetSummary: some View {
        VStack(alignment: .leading, spacing: Constants.controlSpacingTight) {
            Text(String(localized: "目标信号", comment: "Jump removal target signals label"))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            let targets = viewModel.jumpRemovalTargetChannels()
            if targets.isEmpty {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "暂无已选信号", comment: "No selected raw signals for jump removal"))
                            .font(.subheadline)
                        Text(
                            String(
                                localized: "请先在已选信号区添加原始信号",
                                comment: "Jump removal signal selection hint"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("signalComputeDejumpEmptyHint")
            } else {
                Text(
                    String(
                        format: String(
                            localized: "将对 %lld 条已选信号去跳点",
                            comment: "Jump removal target count summary"
                        ),
                        targets.count
                    )
                )
                .font(.subheadline)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(targets) { descriptor in
                        Text(viewModel.plotSeriesName(for: descriptor))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityIdentifier("signalComputeDejumpTargetList")
            }
        }
    }

    private var headingUnwrapTargetSummary: some View {
        VStack(alignment: .leading, spacing: Constants.controlSpacingTight) {
            Text(String(localized: "目标信号", comment: "Heading unwrap target signals label"))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            let targets = viewModel.selectedHeadingAngleChannels()
            if targets.isEmpty {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "暂无已选角度信号", comment: "No selected heading angle signals"))
                            .font(.subheadline)
                        Text(
                            String(
                                localized: "请先在已选信号区添加含「航向角」或「航迹角」的原始信号",
                                comment: "Heading unwrap signal selection hint"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("signalComputeHeadingUnwrapEmptyHint")
            } else {
                Text(
                    String(
                        format: String(
                            localized: "将对 %lld 条角度信号应用角度连续",
                            comment: "Heading unwrap target count summary"
                        ),
                        targets.count
                    )
                )
                .font(.subheadline)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(targets) { descriptor in
                        Text(viewModel.plotSeriesName(for: descriptor))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityIdentifier("signalComputeHeadingUnwrapTargetList")
            }
        }
    }

    private var dejumpParameterFields: some View {
        VStack(alignment: .leading, spacing: Constants.controlSpacingTight) {
            Text(String(localized: "跳变阈值", comment: "Jump threshold field label"))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            panelTextField(
                String(localized: "留空为自动", comment: "Auto jump threshold placeholder"),
                text: $jumpThresholdText,
                accessibilityID: "signalComputeJumpThresholdField",
                field: .jumpThreshold
            )
            .keyboardType(.decimalPad)
        }
    }

    private func panelTextField(
        _ placeholder: String,
        text: Binding<String>,
        accessibilityID: String,
        field: NumericInputField
    ) -> some View {
        HStack(spacing: Constants.controlSpacingTight) {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: Constants.textFieldCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
                .focused($focusedNumericField, equals: field)
                .accessibilityIdentifier(accessibilityID)

            if focusedNumericField == field {
                numericKeyboardDoneButton(accessibilityIdentifier: "\(accessibilityID)Done") {
                    focusedNumericField = nil
                }
            }
        }
    }

    private var resetPanel: some View {
        VStack(alignment: .leading, spacing: Constants.controlSpacing) {
            Text(String(localized: "重置", comment: "Reset section title"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LiquidGlassButtonGroup {
                HStack(spacing: Constants.controlSpacingTight) {
                    Button(String(localized: "重置该通道", comment: "Reset channel scale button")) {
                        if let channelID = selectedChannelID {
                            viewModel.resetChannelScale(channelID: channelID)
                        }
                    }
                    .glassControl(.secondary, size: .compact)
                    .disabled(selectedChannelID == nil)
                    .accessibilityIdentifier("signalComputeResetChannelButton")

                    Button(String(localized: "全部重置", comment: "Reset all scales button"),
                           role: .destructive) {
                        viewModel.resetAllChannelScales()
                    }
                    .glassControl(.destructive, size: .compact)
                    .disabled(viewModel.channelValueScales.isEmpty)
                    .accessibilityIdentifier("signalComputeResetAllButton")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Constants.sectionSpacing)
        .padding(.vertical, Constants.standardPadding)
        .contentSurface(.editingPanel)
    }

    private func applyOperation() {
        dismissFeedback()

        if operation == .dejump {
            applyDejumpOperation()
            return
        }

        if operation == .headingUnwrap {
            applyHeadingUnwrapOperation()
            return
        }

        guard let channelID = selectedChannelID else { return }

        switch operation {
        case .scale:
            guard let multiplier = parseDouble(multiplierText) else {
                presentFeedback(
                    .error,
                    message: String(localized: "请输入有效数字", comment: "Invalid multiplier error")
                )
                return
            }
            viewModel.applyChannelScale(channelID: channelID, multiplier: multiplier)
            multiplierText = "1"
            presentFeedback(
                .success,
                message: String(localized: "倍率已应用", comment: "Scale applied success"),
                haptic: false
            )

        case .deriv:
            do {
                _ = try viewModel.registerDerivedChannel(parentID: channelID, op: .deriv)
                presentFeedback(
                    .success,
                    message: String(localized: "已加入候选", comment: "Added to candidates success"),
                    haptic: false
                )
            } catch {
                presentFeedback(.error, message: error.localizedDescription)
            }

        case .integ:
            do {
                _ = try viewModel.registerDerivedChannel(parentID: channelID, op: .integ)
                presentFeedback(
                    .success,
                    message: String(localized: "已加入候选", comment: "Added to candidates success"),
                    haptic: false
                )
            } catch {
                presentFeedback(.error, message: error.localizedDescription)
            }

        case .movmean:
            guard let window = parseInt(windowText), window >= 1 else {
                presentFeedback(
                    .error,
                    message: String(
                        localized: "窗口必须为 ≥ 1 的整数",
                        comment: "Invalid window size error"
                    )
                )
                return
            }
            do {
                _ = try viewModel.registerDerivedChannel(
                    parentID: channelID,
                    op: .movmean,
                    windowSamples: window
                )
                presentFeedback(
                    .success,
                    message: String(localized: "已加入候选", comment: "Added to candidates success"),
                    haptic: false
                )
            } catch {
                presentFeedback(.error, message: error.localizedDescription)
            }

        case .dejump, .headingUnwrap:
            break
        }
    }

    private func applyHeadingUnwrapOperation() {
        Task {
            let result = await viewModel.unwrapHeadingAngleInSelectedChannels()
            await MainActor.run {
                presentHeadingUnwrapResult(result)
            }
        }
    }

    private func presentHeadingUnwrapResult(_ result: HeadingUnwrapResult) {
        if result.processedCount == 0, !result.skippedUnavailable.isEmpty {
            presentFeedback(
                .error,
                message: String(
                    localized: "无法加载角度信号数据",
                    comment: "Heading unwrap data load failed"
                )
            )
            return
        }

        if result.processedCount == 0 {
            presentFeedback(
                .error,
                message: String(
                    localized: "没有可处理的角度信号",
                    comment: "No heading angle signals to unwrap"
                )
            )
            return
        }

        presentFeedback(
            .success,
            message: String(
                format: String(
                    localized: "已对 %lld 条角度信号应用角度连续",
                    comment: "Heading unwrap success"
                ),
                result.processedCount
            )
        )
    }

    private func applyDejumpOperation() {
        let manualThreshold: Double?
        switch parseOptionalThreshold(jumpThresholdText) {
        case .some(let value):
            manualThreshold = value
        case nil:
            presentFeedback(
                .error,
                message: String(
                    localized: "请输入有效正数阈值，或留空使用自动阈值",
                    comment: "Invalid jump threshold error"
                )
            )
            return
        }

        Task {
            let result = await viewModel.removeJumpPointsFromSelectedChannels(
                manualThreshold: manualThreshold
            )
            await MainActor.run {
                presentDejumpResult(result)
            }
        }
    }

    private func presentDejumpResult(_ result: JumpPointRemovalResult) {
        if result.processedCount == 0, !result.skippedUnavailable.isEmpty {
            presentFeedback(
                .error,
                message: String(
                    localized: "无法估算跳变阈值，请尝试手动输入",
                    comment: "Jump removal threshold estimation failed"
                )
            )
            return
        }

        if result.removedTotal == 0 {
            presentFeedback(
                .info,
                message: String(
                    format: String(
                        localized: "未发现跳点（%lld 条信号）",
                        comment: "No jump points removed success"
                    ),
                    result.processedCount
                )
            )
            return
        }

        presentFeedback(
            .success,
            message: String(
                format: String(
                    localized: "已剔除 %lld 个跳点（%lld 条信号）",
                    comment: "Jump removal success"
                ),
                result.removedTotal,
                result.processedCount
            )
        )
    }

    private func presentFeedback(
        _ kind: ComputeResultFeedbackKind,
        message: String,
        haptic: Bool = true
    ) {
        feedbackDismissTask?.cancel()
        let item = ComputeResultFeedback(kind: kind, message: message)
        feedback = item

        switch kind {
        case .success where haptic:
            successFeedbackTrigger += 1
        case .error:
            errorFeedbackTrigger += 1
        case .success, .info:
            break
        }

        feedbackDismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if feedback?.id == item.id {
                    feedback = nil
                }
            }
        }
    }

    private func dismissFeedback() {
        feedbackDismissTask?.cancel()
        feedback = nil
    }

    private func parseOptionalThreshold(_ text: String) -> Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Double(trimmed), value.isFinite, value > 0 else { return nil }
        return .some(value)
    }

    private func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite, value != 0 else {
            return nil
        }
        return value
    }

    private func parseInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value >= 1 else { return nil }
        return value
    }

    private func formatScale(_ scale: Double) -> String {
        String(format: "%.6g×", scale)
    }
}
