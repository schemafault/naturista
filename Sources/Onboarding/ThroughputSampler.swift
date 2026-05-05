import Foundation

// Rolling-window throughput averager for the onboarding download ETA.
// Returns nil rather than a number until we have at least 30 seconds of
// samples (so the ETA doesn't read "8 hours remaining" in the first three
// seconds), and returns nil again when the most recent sample is more
// than 5 seconds old (so a stalled download hides the ETA rather than
// freezing it on screen).
struct ThroughputSampler {
    private struct Sample {
        let timestamp: Date
        // Cumulative bytes (or units) downloaded across both rows since
        // the sampler was created. Monotonically increasing.
        let cumulative: Double
    }

    private var samples: [Sample] = []
    private let windowSeconds: TimeInterval = 30
    private let stallTimeoutSeconds: TimeInterval = 5
    private let minWindowForETA: TimeInterval = 5

    mutating func record(cumulative: Double, at now: Date = Date()) {
        samples.append(Sample(timestamp: now, cumulative: cumulative))
        let cutoff = now.addingTimeInterval(-windowSeconds)
        samples.removeAll { $0.timestamp < cutoff }
    }

    // ETA in seconds for the remaining bytes/units, or nil when we don't
    // have enough samples yet, the download is stalled, or we'd divide by
    // zero. Caller formats into a human-readable line.
    func etaSeconds(remaining: Double, now: Date = Date()) -> TimeInterval? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let elapsed = last.timestamp.timeIntervalSince(first.timestamp)
        guard elapsed >= minWindowForETA else { return nil }
        if now.timeIntervalSince(last.timestamp) > stallTimeoutSeconds { return nil }
        let delta = last.cumulative - first.cumulative
        guard delta > 0 else { return nil }
        let ratePerSecond = delta / elapsed
        guard ratePerSecond > 0 else { return nil }
        return remaining / ratePerSecond
    }

    // "About 14 min remaining at current speed." Returns nil when the
    // sampler isn't ready : caller hides the ETA line entirely.
    func formattedETA(remaining: Double, now: Date = Date()) -> String? {
        guard let seconds = etaSeconds(remaining: remaining, now: now), seconds.isFinite else { return nil }
        let minutes = max(1, Int((seconds / 60.0).rounded()))
        return "About \(minutes) min remaining at current speed."
    }
}
