import Foundation

// @unchecked Sendable: internal state is protected by NSLock.
final class PowerManagementService: PowerManagementServiceProtocol, @unchecked Sendable {
    nonisolated init() {}

    private var token: NSObjectProtocol?
    private let lock = NSLock()

    /// Begins a system activity that prevents App Nap and idle system sleep.
    /// Safe to call from any thread. No-ops if an activity is already running.
    func startActivity(reason: String) {
        lock.lock()
        defer { lock.unlock() }
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: reason
        )
    }

    /// Ends the current activity and releases the token.
    /// Safe to call from any thread. No-ops if no activity is running.
    func endActivity() {
        lock.lock()
        defer { lock.unlock() }
        guard let t = token else { return }
        ProcessInfo.processInfo.endActivity(t)
        token = nil
    }
}
