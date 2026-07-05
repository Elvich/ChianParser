import Foundation

protocol PowerManagementServiceProtocol: Sendable {
    nonisolated func startActivity(reason: String)
    nonisolated func endActivity()
}
