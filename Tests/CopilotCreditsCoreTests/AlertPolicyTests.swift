import Foundation
import Testing
import CopilotCreditsCore

struct AlertCase: Sendable, CustomTestStringConvertible {
    let fraction: Double
    let alreadyNotified: Double
    let expected: Double?

    var testDescription: String {
        let result: String = expected.map { "\($0)" } ?? "nil"
        return "fraction \(fraction), already notified \(alreadyNotified) → \(result)"
    }
}

struct CustomAlertCase: Sendable, CustomTestStringConvertible {
    let fraction: Double
    let alreadyNotified: Double
    let thresholds: [Double]
    let expected: Double?

    var testDescription: String {
        let result: String = expected.map { "\($0)" } ?? "nil"
        return "thresholds \(thresholds), fraction \(fraction), already notified \(alreadyNotified) → \(result)"
    }
}

@Suite("AlertPolicy — notification thresholds")
struct AlertPolicyTests {

    @Test("Default thresholds = [0.8, 1.0]")
    func defaultThresholds() {
        #expect(AlertPolicy.defaultThresholds == [0.8, 1.0])
    }

    static let specTable: [AlertCase] = [
        AlertCase(fraction: 0.5, alreadyNotified: 0, expected: nil),
        AlertCase(fraction: 0.8, alreadyNotified: 0, expected: 0.8),
        AlertCase(fraction: 0.85, alreadyNotified: 0, expected: 0.8),
        AlertCase(fraction: 0.85, alreadyNotified: 0.8, expected: nil),
        AlertCase(fraction: 1.2, alreadyNotified: 0, expected: 1.0),
        AlertCase(fraction: 1.0, alreadyNotified: 0.8, expected: 1.0),
        AlertCase(fraction: 1.5, alreadyNotified: 1.0, expected: nil),
    ]

    @Test("Spec example table (implicit default thresholds)", arguments: AlertPolicyTests.specTable)
    func specTableImplicitDefaults(testCase: AlertCase) {
        let result: Double? = AlertPolicy.thresholdToNotify(fraction: testCase.fraction,
                                                            alreadyNotified: testCase.alreadyNotified)
        #expect(result == testCase.expected)
    }

    @Test("Spec example table (explicit default thresholds)", arguments: AlertPolicyTests.specTable)
    func specTableExplicitDefaults(testCase: AlertCase) {
        let result: Double? = AlertPolicy.thresholdToNotify(fraction: testCase.fraction,
                                                            alreadyNotified: testCase.alreadyNotified,
                                                            thresholds: AlertPolicy.defaultThresholds)
        #expect(result == testCase.expected)
    }

    static let extraDefaultCases: [AlertCase] = [
        // Just below the first threshold
        AlertCase(fraction: 0.7999, alreadyNotified: 0, expected: nil),
        // No usage at all
        AlertCase(fraction: 0, alreadyNotified: 0, expected: nil),
        // Just below 1.0 after having notified 0.8
        AlertCase(fraction: 0.9999, alreadyNotified: 0.8, expected: nil),
        // Exactly 1.0 with nothing notified yet: jump to the highest
        AlertCase(fraction: 1.0, alreadyNotified: 0, expected: 1.0),
        // Already notified at 1.0, still at 1.0
        AlertCase(fraction: 1.0, alreadyNotified: 1.0, expected: nil),
        // alreadyNotified higher than any reached threshold (e.g. new value went down)
        AlertCase(fraction: 0.85, alreadyNotified: 1.0, expected: nil),
    ]

    @Test("Extra cases with the default thresholds", arguments: AlertPolicyTests.extraDefaultCases)
    func extraDefaultCasesTest(testCase: AlertCase) {
        let result: Double? = AlertPolicy.thresholdToNotify(fraction: testCase.fraction,
                                                            alreadyNotified: testCase.alreadyNotified)
        #expect(result == testCase.expected)
    }

    static let unsorted: [Double] = [1.0, 0.5, 0.9, 0.75]

    static let customCases: [CustomAlertCase] = [
        CustomAlertCase(fraction: 0.4, alreadyNotified: 0, thresholds: AlertPolicyTests.unsorted, expected: nil),
        CustomAlertCase(fraction: 0.5, alreadyNotified: 0, thresholds: AlertPolicyTests.unsorted, expected: 0.5),
        CustomAlertCase(fraction: 0.6, alreadyNotified: 0, thresholds: AlertPolicyTests.unsorted, expected: 0.5),
        CustomAlertCase(fraction: 0.8, alreadyNotified: 0, thresholds: AlertPolicyTests.unsorted, expected: 0.75),
        CustomAlertCase(fraction: 0.8, alreadyNotified: 0.5, thresholds: AlertPolicyTests.unsorted, expected: 0.75),
        CustomAlertCase(fraction: 0.8, alreadyNotified: 0.75, thresholds: AlertPolicyTests.unsorted, expected: nil),
        CustomAlertCase(fraction: 0.95, alreadyNotified: 0, thresholds: AlertPolicyTests.unsorted, expected: 0.9),
        CustomAlertCase(fraction: 0.95, alreadyNotified: 0.9, thresholds: AlertPolicyTests.unsorted, expected: nil),
        CustomAlertCase(fraction: 1.0, alreadyNotified: 0.9, thresholds: AlertPolicyTests.unsorted, expected: 1.0),
        CustomAlertCase(fraction: 3.0, alreadyNotified: 0, thresholds: AlertPolicyTests.unsorted, expected: 1.0),
        CustomAlertCase(fraction: 3.0, alreadyNotified: 1.0, thresholds: AlertPolicyTests.unsorted, expected: nil),
        // Descending order
        CustomAlertCase(fraction: 0.92, alreadyNotified: 0, thresholds: [1.0, 0.9, 0.5], expected: 0.9),
        // Single threshold
        CustomAlertCase(fraction: 0.6, alreadyNotified: 0, thresholds: [0.6], expected: 0.6),
        CustomAlertCase(fraction: 0.59, alreadyNotified: 0, thresholds: [0.6], expected: nil),
        // Thresholds above 1 (overage alerts)
        CustomAlertCase(fraction: 1.3, alreadyNotified: 1.0, thresholds: [1.5, 1.0, 1.25], expected: 1.25),
        // Empty list: nothing can ever be reached
        CustomAlertCase(fraction: 5.0, alreadyNotified: 0, thresholds: [], expected: nil),
    ]

    @Test("Custom thresholds, not necessarily sorted", arguments: AlertPolicyTests.customCases)
    func customThresholds(testCase: CustomAlertCase) {
        let result: Double? = AlertPolicy.thresholdToNotify(fraction: testCase.fraction,
                                                            alreadyNotified: testCase.alreadyNotified,
                                                            thresholds: testCase.thresholds)
        #expect(result == testCase.expected)
    }

    @Test("The result does not depend on threshold order")
    func orderIndependence() {
        let orders: [[Double]] = [
            [0.5, 0.75, 0.9, 1.0],
            [1.0, 0.9, 0.75, 0.5],
            [0.9, 0.5, 1.0, 0.75],
        ]
        for fraction in [0.3, 0.5, 0.76, 0.91, 1.0, 1.4] {
            for already in [0.0, 0.5, 0.75, 0.9, 1.0] {
                let results: [Double?] = orders.map {
                    AlertPolicy.thresholdToNotify(fraction: fraction, alreadyNotified: already, thresholds: $0)
                }
                #expect(results[0] == results[1], "fraction \(fraction), already \(already)")
                #expect(results[0] == results[2], "fraction \(fraction), already \(already)")
            }
        }
    }
}
