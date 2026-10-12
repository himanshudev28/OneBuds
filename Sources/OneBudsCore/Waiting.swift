/// Polls `condition` on the main actor until it is true or `timeout` elapses.
/// Delegate callbacks keep arriving on the main run loop while this sleeps. Returns false if the
/// calling task is cancelled.
@MainActor
public func waitUntil(timeout: Duration, interval: Duration = .milliseconds(50), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now >= deadline || Task.isCancelled { return false }
        try? await Task.sleep(for: interval)
    }
    return true
}

extension Duration {
    /// Duration in seconds as a Double.
    public var seconds: Double {
        let (s, attoseconds) = components
        return Double(s) + Double(attoseconds) / 1e18
    }
}
