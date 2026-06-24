import Foundation

protocol PowerManagementServiceProtocol: AnyObject {
    func startActivity(reason: String)
    func endActivity()
}
