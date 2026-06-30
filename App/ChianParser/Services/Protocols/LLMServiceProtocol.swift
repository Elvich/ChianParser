import Foundation

@MainActor
protocol LLMServiceProtocol: AnyObject {
    var state: LLMState { get }
    func loadModel()
    func unloadModel()
    func generate(prompt: String) async throws -> String
    func generateStreaming(prompt: String) -> AsyncThrowingStream<String, Error>
    func analyzeApartment(description: String) async throws -> ApartmentAnalysis
}

extension LLMServiceProtocol {
    func unloadModel() {}
    func analyzeApartment(description: String) async throws -> ApartmentAnalysis {
        throw LLMError.modelNotLoaded
    }
}
