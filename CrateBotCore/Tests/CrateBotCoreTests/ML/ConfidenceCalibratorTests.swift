import XCTest
@testable import CrateBotCore

final class ConfidenceCalibratorTests: XCTestCase {

    func testCalibrateWithDefaultTemperatureIsIdentity() {
        // Temperature 1.0 should pass through unchanged (minus smoothing)
        let calibrator = ConfidenceCalibrator(temperature: 1.0, smoothingFactor: 0.0)
        let result = calibrator.calibrate(0.75)
        XCTAssertEqual(result, 0.75, accuracy: 0.001)
    }

    func testCalibratePreservesOrdering() {
        let calibrator = ConfidenceCalibrator(temperature: 1.5, smoothingFactor: 0.1)
        let low = calibrator.calibrate(0.3)
        let mid = calibrator.calibrate(0.5)
        let high = calibrator.calibrate(0.8)
        XCTAssertLessThan(low, mid)
        XCTAssertLessThan(mid, high)
    }

    func testCalibrateHighTemperatureCompresses() {
        // High temperature should compress toward 0.5
        let calibrator = ConfidenceCalibrator(temperature: 2.0, smoothingFactor: 0.0)
        let result = calibrator.calibrate(0.9)
        XCTAssertLessThan(result, 0.9)
        XCTAssertGreaterThan(result, 0.5)
    }

    func testCalibrateLowTemperatureSharpens() {
        // Low temperature should sharpen (push away from 0.5)
        let calibrator = ConfidenceCalibrator(temperature: 0.5, smoothingFactor: 0.0)
        let result = calibrator.calibrate(0.7)
        XCTAssertGreaterThan(result, 0.7)
    }

    func testCalibrateClampsToBounds() {
        let calibrator = ConfidenceCalibrator(temperature: 0.3, smoothingFactor: 0.0)
        let high = calibrator.calibrate(1.0)
        let low = calibrator.calibrate(0.0)
        XCTAssertLessThanOrEqual(high, 1.0)
        XCTAssertGreaterThanOrEqual(low, 0.0)
    }

    func testCalibrateSmoothingReducesExtreme() {
        let calibrator = ConfidenceCalibrator(temperature: 1.0, smoothingFactor: 0.1)
        let result = calibrator.calibrate(1.0)
        // With smoothing 0.1: result * 0.9 + 0.05, so max is 0.95
        XCTAssertLessThanOrEqual(result, 0.95 + 0.001)
    }

    func testFitProducesReasonableTemperature() {
        var calibrator = ConfidenceCalibrator()
        // Well-calibrated predictions should produce temperature near 1.0
        let predictions: [Float] = [0.9, 0.8, 0.7, 0.2, 0.1, 0.15]
        let labels: [Bool] = [true, true, true, false, false, false]
        calibrator.fit(predictions: predictions, labels: labels)
        XCTAssertGreaterThanOrEqual(calibrator.temperature, 0.3)
        XCTAssertLessThanOrEqual(calibrator.temperature, 5.0)
    }
}
