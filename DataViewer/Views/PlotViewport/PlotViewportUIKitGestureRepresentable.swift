import SwiftUI

#if os(iOS)
import UIKit

struct PlotViewportUIKitGestureRepresentable: UIViewRepresentable {
    let target: PlotViewportTarget
    @Bindable var viewModel: DataViewModel
    var isEnabled: Bool

    func makeUIView(context: Context) -> PlotViewportGestureAnchorView {
        let view = PlotViewportGestureAnchorView()
        view.configure(target: target, viewModel: viewModel, isEnabled: isEnabled)
        return view
    }

    func updateUIView(_ uiView: PlotViewportGestureAnchorView, context: Context) {
        uiView.configure(target: target, viewModel: viewModel, isEnabled: isEnabled)
    }
}

final class PlotViewportGestureAnchorView: UIView {
    private var target: PlotViewportTarget = .mainPlot
    private weak var viewModel: DataViewModel?
    private var isEnabled = true
    private weak var gestureHostView: UIView?
    private var pinchRecognizer: UIPinchGestureRecognizer?
    private var panRecognizer: UIPanGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        attachRecognizersToHostIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachRecognizersToHostIfNeeded()
    }

    func configure(target: PlotViewportTarget, viewModel: DataViewModel, isEnabled: Bool) {
        self.target = target
        self.viewModel = viewModel
        self.isEnabled = isEnabled
        pinchRecognizer?.isEnabled = isEnabled
        panRecognizer?.isEnabled = isEnabled
    }

    private func attachRecognizersToHostIfNeeded() {
        guard superview != nil else {
            detachRecognizers()
            return
        }
        guard let host = resolveGestureHostView() else {
            detachRecognizers()
            return
        }
        guard gestureHostView !== host else { return }

        detachRecognizers()
        gestureHostView = host

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        pinch.cancelsTouchesInView = false
        host.addGestureRecognizer(pinch)
        pinchRecognizer = pinch

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        pan.cancelsTouchesInView = false
        host.addGestureRecognizer(pan)
        panRecognizer = pan
    }

    private func detachRecognizers() {
        if let pinchRecognizer, let view = pinchRecognizer.view {
            view.removeGestureRecognizer(pinchRecognizer)
        }
        if let panRecognizer, let view = panRecognizer.view {
            view.removeGestureRecognizer(panRecognizer)
        }
        pinchRecognizer = nil
        panRecognizer = nil
        gestureHostView = nil
    }

    private func resolveGestureHostView() -> UIView? {
        var ancestor: UIView? = self
        while let current = ancestor {
            for subview in current.subviews {
                if subview === self || isDescendant(of: subview) { continue }
                if let scrollView = Self.findFirstScrollView(in: subview) {
                    return scrollView
                }
            }
            ancestor = current.superview
        }
        return superview
    }

    private static func findFirstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = findFirstScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard isEnabled, let viewModel, let host = gestureHostView else { return }
        switch recognizer.state {
        case .began, .changed:
            break
        default:
            return
        }

        let delta = recognizer.scale - 1
        recognizer.scale = 1
        guard delta != 0 else { return }

        let location = recognizer.location(in: host)
        let width = max(host.bounds.width, 1)
        viewModel.applyMagnification(
            target: target,
            magnification: CGFloat(delta),
            anchorX: location.x,
            width: width
        )
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard isEnabled, let viewModel, let host = gestureHostView else { return }

        switch recognizer.state {
        case .began:
            recognizer.setTranslation(.zero, in: host)
            return
        case .changed:
            break
        default:
            return
        }

        let translation = recognizer.translation(in: host)
        recognizer.setTranslation(.zero, in: host)
        guard translation.x != 0 else { return }

        let width = max(host.bounds.width, 1)
        viewModel.applyPanGestureTranslation(
            target: target,
            deltaX: translation.x,
            width: width,
            panScale: PlotViewportConstants.touchPanScale
        )
    }
}

extension PlotViewportGestureAnchorView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panRecognizer,
              let pan = gestureRecognizer as? UIPanGestureRecognizer,
              let host = gestureHostView else {
            return true
        }
        let translation = pan.translation(in: host)
        if translation == .zero {
            let velocity = pan.velocity(in: host)
            return abs(velocity.x) >= abs(velocity.y)
        }
        return abs(translation.x) >= abs(translation.y)
    }
}
#endif
