import SwiftUI

struct MarqueeText: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0

    private let segmentSpacing: CGFloat = 32
    private let scrollSpeed: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let containerWidth = proxy.size.width
            let shouldScroll = !reduceMotion
                && textWidth > containerWidth
                && containerWidth > 0

            ZStack(alignment: .leading) {
                if shouldScroll {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                        let cycle = textWidth + segmentSpacing
                        let duration = max(Double(cycle / scrollSpeed), 0.01)
                        let phase = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: duration) / duration
                        let offset = -CGFloat(phase) * cycle

                        HStack(spacing: segmentSpacing) {
                            label
                            label
                        }
                        .offset(x: offset)
                    }
                } else {
                    label
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: containerWidth, alignment: .leading)
            .clipped()
        }
        .frame(height: 16)
        .accessibilityLabel(text)
        .background(widthMeasurement)
    }

    private var label: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var widthMeasurement: some View {
        label
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: MarqueeTextWidthKey.self, value: geo.size.width)
                }
            )
            .hidden()
            .allowsHitTesting(false)
            .onPreferenceChange(MarqueeTextWidthKey.self) { width in
                if abs(textWidth - width) > 0.5 {
                    textWidth = width
                }
            }
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
