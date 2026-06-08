import SwiftUI

struct SlideToConfirmControl: View {
    let label: String
    var isEnabled: Bool = true
    var resetTrigger: Int = 0
    let onConfirm: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var confirmFeedbackTrigger = 0

    private let thumbSize: CGFloat = 44
    private let trackHeight: CGFloat = 52
    private let trackInset: CGFloat = 4
    private let confirmThreshold: CGFloat = 0.85

    var body: some View {
        GeometryReader { geometry in
            let maxOffset = max(geometry.size.width - thumbSize - trackInset * 2, 0)

            ZStack(alignment: .leading) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, thumbSize + trackInset)
                    .allowsHitTesting(false)

                thumb
                    .offset(x: dragOffset)
            }
            .padding(.horizontal, trackInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
            .highPriorityGesture(dragGesture(maxOffset: maxOffset))
        }
        .frame(height: trackHeight)
        .liquidGlassFloatingPanel(cornerRadius: trackHeight / 2)
        .opacity(isEnabled ? 1 : 0.45)
        .allowsHitTesting(isEnabled)
        .onChange(of: resetTrigger) { _, _ in
            resetThumb(animated: true)
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                resetThumb(animated: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(
            String(
                localized: "向右拖动滑块到底以确认",
                comment: "Slide to confirm accessibility hint"
            )
        )
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityAction(
            named: String(localized: "应用", comment: "Apply operation button")
        ) {
            guard isEnabled else { return }
            onConfirm()
            resetThumb(animated: false)
        }
        .accessibilityIdentifier("signalComputeApplyButton")
        .sensoryFeedback(.success, trigger: confirmFeedbackTrigger)
    }

    private var thumb: some View {
        ZStack {
            LiquidGlassProminentShapeBackground(shape: Circle())
                .frame(width: thumbSize, height: thumbSize)

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .allowsHitTesting(false)
        }
        .frame(width: thumbSize, height: thumbSize)
        .contentShape(Circle())
    }

    private func dragGesture(maxOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled, maxOffset > 0 else { return }
                dragOffset = min(max(value.translation.width, 0), maxOffset)
            }
            .onEnded { _ in
                guard isEnabled, maxOffset > 0 else {
                    resetThumb(animated: true)
                    return
                }

                if dragOffset / maxOffset >= confirmThreshold {
                    confirmFeedbackTrigger += 1
                    onConfirm()
                }
                resetThumb(animated: true)
            }
    }

    private func resetThumb(animated: Bool) {
        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                dragOffset = 0
            }
        } else {
            dragOffset = 0
        }
    }
}
