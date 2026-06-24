import Foundation

struct ApartmentAnalysis: Codable {
    let tags: [String]
    let condition: String
    let recommendations: String
}

enum ApartmentAnalysisError: LocalizedError {
    case invalidJSON
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidJSON:    return "Модель вернула невалидный JSON"
        case .emptyResponse:  return "Модель не вернула анализ"
        }
    }
}

extension ApartmentAnalysis {
    static func parse(from raw: String) throws -> ApartmentAnalysis {
        var json = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !json.isEmpty else { throw ApartmentAnalysisError.emptyResponse }

        // Strip ``` json ... ``` block if present
        if let match = json.firstMatch(of: /```(?:json)?\s*([\s\S]+?)```/) {
            json = String(match.output.1).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Extract the outermost { ... } in case there's surrounding prose
        if let startIdx = json.firstIndex(of: "{"),
           let endIdx = json.lastIndex(of: "}") {
            json = String(json[startIdx...endIdx])
        }

        guard let data = json.data(using: .utf8) else {
            throw ApartmentAnalysisError.invalidJSON
        }

        do {
            return try JSONDecoder().decode(ApartmentAnalysis.self, from: data)
        } catch {
            throw ApartmentAnalysisError.invalidJSON
        }
    }
}
