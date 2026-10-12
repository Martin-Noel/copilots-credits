import Foundation

/// Decides when to send a threshold notification: one per threshold per cycle.
public enum AlertPolicy {
    public static let defaultThresholds: [Double] = [0.8, 1.0]

    /// The highest threshold reached, if not already notified; otherwise nil.
    public static func thresholdToNotify(fraction: Double,
                                         alreadyNotified: Double,
                                         thresholds: [Double] = defaultThresholds) -> Double? {
        guard let crossed = thresholds.filter({ fraction >= $0 }).max(),
              crossed > alreadyNotified else { return nil }
        return crossed
    }
}
