import Foundation
import Testing
@testable import DataViewer

struct SignalTransformTests {

    @Test func movingAverageBasic() {
        let values = [1.0, 2.0, 3.0, 4.0, 5.0]
        let result = SignalTransform.movingAverage(values: values, windowSamples: 3)
        #expect(result[0] == 1.0)
        #expect(result[1] == 1.5)
        #expect(result[2] == 2.0)
        #expect(result[3] == 3.0)
        #expect(result[4] == 4.0)
    }

    @Test func derivativeBasic() {
        let times = [0.0, 1.0, 2.0, 3.0]
        let values = [0.0, 2.0, 4.0, 6.0]
        let result = SignalTransform.derivative(times: times, values: values)
        #expect(result.count == 4)
        #expect(abs(result[0] - 2.0) < 1e-12)
        #expect(abs(result[1] - 2.0) < 1e-12)
        #expect(abs(result[2] - 2.0) < 1e-12)
        #expect(abs(result[3] - 2.0) < 1e-12)
    }

    @Test func integrateBasic() {
        let times = [0.0, 1.0, 2.0, 3.0]
        let values = [1.0, 1.0, 1.0, 1.0]
        let result = SignalTransform.integrate(times: times, values: values)
        #expect(result.count == 4)
        #expect(result[0] == 0.0)
        #expect(abs(result[1] - 1.0) < 1e-12)
        #expect(abs(result[2] - 2.0) < 1e-12)
        #expect(abs(result[3] - 3.0) < 1e-12)
    }

    @Test func removeJumpPointsBasic() {
        let values = [0.0, 0.0, 100.0, 0.0, 0.0]
        let result = SignalTransform.removeJumpPoints(values: values)
        #expect(result.removedCount == 1)
        #expect(result.thresholdUsed != nil)
        #expect(abs(result.values[2]) < 1e-9)
    }
}
