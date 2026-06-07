import Foundation
import UIKit

struct LoadingProgressState: Equatable {
    var phaseLabel: String
    var fraction: Double
}

@MainActor
final class LoadingProgressSimulator {
    private var phases: [LoadingPhase] = []
    private var currentPhaseIndex = -1
    private var sessionStartTime: Date?
    private var totalEstimatedDuration: TimeInterval = 0
    private var tickTask: Task<Void, Never>?
    private var reduceMotion = false
    private(set) var state: LoadingProgressState?

    var onStateChange: ((LoadingProgressState) -> Void)?

    nonisolated private static let normalCap = 0.95
    nonisolated private static let overtimeCap = 0.99
    nonisolated private static let fractionCap = 0.99
    nonisolated private static let progressEaseExponent = 1.0
    nonisolated private static let progressSpeedFactor = 1.25
    nonisolated private static let seriesLoadProgressSpeedFactor = progressSpeedFactor * 0.25
    nonisolated private static let seriesLoadCallbackProgressMultiplier = 0.5
    nonisolated private static let overtimeWindowFractionOfEstimate = 0.35

    var isActive: Bool { state != nil }

    static var systemPrefersReducedMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    nonisolated static func seriesLoadingLabel(loaded: Int, total: Int) -> String {
        ImportDurationEstimator.seriesLoadingLabel
    }

    nonisolated static func easedInProgress(_ linear: Double) -> Double {
        min(max(linear, 0), 1)
    }

    nonisolated static func weightedFraction(
        phases: [LoadingPhase],
        phaseIndex: Int,
        inPhaseProgress: Double
    ) -> Double {
        guard phaseIndex >= 0, phaseIndex < phases.count else { return 0 }
        let clamped = min(max(inPhaseProgress, 0), 1)
        let prior = phases.prefix(phaseIndex).reduce(0.0) { $0 + $1.weight }
        let current = phases[phaseIndex].weight * clamped
        return min(prior + current, fractionCap)
    }

    func begin(phases: [LoadingPhase], reduceMotion: Bool? = nil) {
        cancelTickTask()
        self.phases = phases
        self.currentPhaseIndex = -1
        self.totalEstimatedDuration = ImportDurationEstimator.totalEstimatedDuration(for: phases)
        self.sessionStartTime = Date()
        self.reduceMotion = reduceMotion ?? Self.systemPrefersReducedMotion
        let initialLabel = phases.first?.label ?? ImportDurationEstimator.importingFileLabel
        publishState(label: initialLabel, fraction: 0)
        startSessionTickTask()
    }

    func enterPhase(at index: Int, labelOverride: String? = nil) {
        guard index >= 0, index < phases.count else { return }
        currentPhaseIndex = index
        let label = labelOverride ?? phases[index].label
        let fraction: Double
        if reduceMotion {
            fraction = max(
                state?.fraction ?? 0,
                Self.weightedFraction(phases: phases, phaseIndex: index, inPhaseProgress: 0)
            )
        } else {
            fraction = max(state?.fraction ?? 0, simulatedFraction())
        }
        publishState(label: label, fraction: fraction)
    }

    func completePhase(at index: Int) {
        guard index >= 0, index < phases.count else { return }
        let weighted = Self.weightedFraction(phases: phases, phaseIndex: index, inPhaseProgress: 1)
        let fraction: Double
        if reduceMotion {
            fraction = weighted
        } else {
            fraction = max(state?.fraction ?? 0, simulatedFraction(), weighted)
        }
        publishState(label: phases[index].label, fraction: fraction)
    }

    func updateSeriesProgress(loaded: Int, total: Int) {
        guard total > 0,
              let index = phases.firstIndex(where: { $0.id == "seriesLoad" }) else { return }
        currentPhaseIndex = index
        let label = Self.seriesLoadingLabel(loaded: loaded, total: total)
        let linear = min(Double(loaded) / Double(total) * Self.seriesLoadCallbackProgressMultiplier, 1)
        let weighted = Self.weightedFraction(
            phases: phases,
            phaseIndex: index,
            inPhaseProgress: linear
        )
        let fraction = max(state?.fraction ?? 0, weighted, simulatedFraction())
        publishState(label: label, fraction: fraction)
    }

    func finish() {
        cancelTickTask()
        phases = []
        currentPhaseIndex = -1
        sessionStartTime = nil
        totalEstimatedDuration = 0
        state = nil
    }

    private func startSessionTickTask() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                let label = self.state?.phaseLabel ?? self.phases.first?.label ?? ImportDurationEstimator.importingFileLabel
                let fraction = max(self.state?.fraction ?? 0, self.simulatedFraction())
                self.publishState(label: label, fraction: fraction)
            }
        }
    }

    private func simulatedFraction() -> Double {
        guard let sessionStartTime else { return 0 }
        let speed = activeProgressSpeedFactor
        let elapsed = Date().timeIntervalSince(sessionStartTime) * speed
        let total = max(totalEstimatedDuration, 0.05)
        let linear = min(elapsed / total, 1)
        let eased = Self.easedInProgress(linear)
        if elapsed <= total {
            return min(eased * Self.normalCap, Self.normalCap)
        }
        let overtimeWindow = max(total * Self.overtimeWindowFractionOfEstimate, 0.2)
        let overtimeLinear = min((elapsed - total) / overtimeWindow, 1)
        let tail = Self.easedInProgress(overtimeLinear) * (Self.overtimeCap - Self.normalCap)
        return min(Self.normalCap + tail, Self.overtimeCap)
    }

    private var activeProgressSpeedFactor: Double {
        if phases.count == 1, phases.first?.id == "seriesLoad" {
            return Self.seriesLoadProgressSpeedFactor
        }
        guard currentPhaseIndex >= 0,
              currentPhaseIndex < phases.count,
              phases[currentPhaseIndex].id == "seriesLoad" else {
            return Self.progressSpeedFactor
        }
        return Self.seriesLoadProgressSpeedFactor
    }

    private func publishState(label: String, fraction: Double) {
        let newState = LoadingProgressState(phaseLabel: label, fraction: fraction)
        state = newState
        onStateChange?(newState)
    }

    private func cancelTickTask() {
        tickTask?.cancel()
        tickTask = nil
    }
}
