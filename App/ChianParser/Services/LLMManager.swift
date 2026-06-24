import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Hub

// MARK: - State

enum LLMState: Equatable {
    case idle
    case downloading(progress: Double)
    case loading
    case ready
    case generating
    case error(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var statusLabel: String {
        switch self {
        case .idle:                   return "Model not loaded"
        case .downloading(let p):     return "Downloading… \(Int(p * 100))%"
        case .loading:                return "Loading into memory…"
        case .ready:                  return "Ready"
        case .generating:             return "Generating…"
        case .error(let msg):         return "Error: \(msg)"
        }
    }
}

// MARK: - LLMManager

@MainActor
@Observable
final class LLMManager {

    // Gemma 4 E2B — 4-bit quantized, ~3 GB unified memory required on M-series.
    private static let modelID = "mlx-community/gemma-4-e2b-it-4bit"

    private static func chatParams() -> GenerateParameters {
        let temp = Float(UserDefaults.standard.object(forKey: "llmChatTemperature") as? Double ?? 0.7)
        let tokens = UserDefaults.standard.object(forKey: "llmMaxTokens") as? Int
        return GenerateParameters(maxTokens: tokens, temperature: temp, topP: 0.9)
    }

    private static func analysisParams() -> GenerateParameters {
        let temp = Float(UserDefaults.standard.object(forKey: "llmAnalysisTemperature") as? Double ?? 0.3)
        let tokens = UserDefaults.standard.object(forKey: "llmMaxTokens") as? Int
        return GenerateParameters(maxTokens: tokens, temperature: temp, topP: 0.9)
    }

    private(set) var state: LLMState = .idle
    private var container: ModelContainer?

    // MARK: - Load

    func loadModel() {
        switch state {
        case .idle, .error: break
        default: return
        }
        state = .downloading(progress: 0)
        Task { await performLoad() }
    }

    func unloadModel() {
        container = nil
        state = .idle
    }

    private func performLoad() async {
        let primary = UserDefaults.standard.string(forKey: "llmHFEndpoint") ?? "https://huggingface.co"
        // Auto-fallback: always try the mirror if the primary endpoint fails
        var endpoints = [primary]
        if primary != "https://hf-mirror.com" { endpoints.append("https://hf-mirror.com") }

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let config  = ModelConfiguration(id: Self.modelID)
        var lastError: Error?

        outer: for endpoint in endpoints {
            let hub = HubApi(downloadBase: caches, endpoint: endpoint)

            for attempt in 1...2 {
                do {
                    let loaded = try await LLMModelFactory.shared.loadContainer(
                        hub: hub,
                        configuration: config
                    ) { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.state = .downloading(progress: progress.fractionCompleted)
                        }
                    }
                    state = .loading
                    container = loaded
                    state = .ready
                    return
                } catch {
                    lastError = error
                    if attempt < 2 {
                        // Brief pause then retry same endpoint
                        state = .downloading(progress: 0)
                        try? await Task.sleep(for: .seconds(3))
                    }
                }
            }
            // Reset before trying the next endpoint
            state = .downloading(progress: 0)
            try? await Task.sleep(for: .seconds(1))
        }

        state = .error(Self.humanReadable(lastError ?? LLMError.modelNotLoaded))
    }

    // MARK: - Generate (single response)

    func generate(prompt: String) async throws -> String {
        guard let container, state.isReady else { throw LLMError.modelNotLoaded }
        state = .generating
        defer { state = .ready }

        let session = ChatSession(container, generateParameters: Self.chatParams())
        return try await session.respond(to: prompt)
    }

    // MARK: - Generate (streaming)

    func generateStreaming(prompt: String) -> AsyncThrowingStream<String, Error> {
        guard let container, state.isReady else {
            return AsyncThrowingStream { $0.finish(throwing: LLMError.modelNotLoaded) }
        }

        state = .generating

        // Build session and stream before leaving @MainActor context.
        let session = ChatSession(container, generateParameters: Self.chatParams())
        let tokenStream = session.streamResponse(to: prompt)

        return AsyncThrowingStream { continuation in
            Task {
                defer { Task { @MainActor in self.state = .ready } }
                do {
                    for try await chunk in tokenStream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Analyze Apartment

    func analyzeApartment(description: String) async throws -> ApartmentAnalysis {
        guard let container, state.isReady else { throw LLMError.modelNotLoaded }

        state = .generating
        defer { state = .ready }

        let systemPrompt = """
        Ты — аналитик недвижимости. Анализируй описание квартиры и отвечай СТРОГО только \
        JSON-объектом без каких-либо вступительных слов, пояснений или markdown-разметки.

        JSON должен содержать ровно три поля:
        1. "tags" — массив из 3-5 коротких строк на русском языке с ключевыми особенностями
        2. "condition" — ровно одно из значений: "Евроремонт", "Хороший ремонт", \
        "Косметический ремонт", "Требуется ремонт", "Бабушкин ремонт", "Новостройка", \
        "Черновая отделка"
        3. "recommendations" — 1-2 предложения на русском с советом для покупателя

        Пример:
        {"tags":["светлая","высокие потолки","тихий двор","без мебели"],"condition":"Требуется ремонт","recommendations":"Квартира подходит для флиппинга. Потребуются вложения около 1-2 млн рублей."}
        """

        let session = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: Self.analysisParams()
        )
        let raw = try await session.respond(to: "Описание квартиры:\n\(description)")
        return try ApartmentAnalysis.parse(from: raw)
    }

    // MARK: - Helpers

    private static func humanReadable(_ error: Error) -> String {
        let desc = error.localizedDescription.lowercased()
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "Нет интернета. Проверьте подключение."
            case .networkConnectionLost, .timedOut:
                return "Соединение прервано. Попробуйте использовать зеркало hf-mirror.com в настройках AI или включить VPN."
            default: break
            }
        }
        if desc.contains("memory") || desc.contains("alloc") || desc.contains("oom") {
            return "Недостаточно памяти. Gemma 4 E2B требует ~3 ГБ unified memory."
        }
        if desc.contains("404") || desc.contains("not found") {
            return "Модель не найдена на Hugging Face. Проверьте ID модели."
        }
        if desc.contains("connection") || desc.contains("network") || desc.contains("reset") {
            return "Ошибка сети. Попробуйте зеркало hf-mirror.com в настройках AI или включите VPN."
        }
        return error.localizedDescription
    }
}

// MARK: - Cache helpers

extension LLMManager {

    // defaultHubApi uses cachesDirectory as downloadBase.
    // HubApi stores at: downloadBase/models/{org}/{repo}
    private static let modelOrg  = "mlx-community"
    private static let modelRepo = "gemma-4-e2b-it-4bit"

    static var modelCacheURL: URL? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches")

        let candidates: [URL] = [
            // Primary: path used by defaultHubApi (swift-transformers 1.0)
            caches
                .appendingPathComponent("models")
                .appendingPathComponent(modelOrg)
                .appendingPathComponent(modelRepo),
            // Fallback: classic ~/.cache/huggingface/hub layout
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/huggingface/hub/models--\(modelOrg)--\(modelRepo)")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func modelCacheSizeBytes() -> Int64 {
        guard let url = modelCacheURL,
              let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else { return 0 }
        return enumerator.reduce(into: Int64(0)) { acc, item in
            guard let fileURL = item as? URL,
                  let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else { return }
            acc += Int64(size)
        }
    }

    static func deleteModelCache() throws {
        guard let url = modelCacheURL else { return }
        try FileManager.default.removeItem(at: url)
    }
}

// MARK: - Protocol conformance

extension LLMManager: LLMServiceProtocol {}

// MARK: - Errors

enum LLMError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        "Model is not loaded yet. Tap \"Load Model\" first."
    }
}
