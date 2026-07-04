//
//  AppContainer.swift
//  ChianParser
//
//  DI container: holds all service singletons and creates ViewModels via factory methods.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class AppContainer {

    // MARK: - Services

    let selectorsManager: any SelectorsManagerProtocol
    let searchParser: any SearchParserProtocol
    let detailParser: any DetailParserProtocol
    let exportService: any ExportServiceProtocol
    let flipAnalyzer: any FlipAnalyzerProtocol
    let llm: any LLMServiceProtocol
    let powerManager: any PowerManagementServiceProtocol
    let apartmentsProvider: any ApartmentsProviderProtocol
    let webSocketNodeService: WebSocketNodeService

    // MARK: - Init

    init(
        selectorsManager: any SelectorsManagerProtocol = SelectorsManager(),
        exportService: any ExportServiceProtocol = ExportManager(),
        flipAnalyzer: any FlipAnalyzerProtocol = FlipAnalyzer(),
        powerManager: (any PowerManagementServiceProtocol)? = nil,
        llm: (any LLMServiceProtocol)? = nil,
        apartmentsProvider: (any ApartmentsProviderProtocol)? = nil
    ) {
        self.selectorsManager = selectorsManager
        self.searchParser = CianDataExtractor(selectorsManager: selectorsManager)
        self.detailParser = CianDetailParser(selectorsManager: selectorsManager)
        self.exportService = exportService
        self.flipAnalyzer = flipAnalyzer
        self.powerManager = powerManager ?? PowerManagementService()
        self.llm = llm ?? LLMManager()
        self.apartmentsProvider = apartmentsProvider ?? RemoteApartmentsProvider() // Изменено на RemoteApartmentsProvider по запросу пользователя
        self.webSocketNodeService = WebSocketNodeService()
    }

    // MARK: - Factory Methods

    @MainActor
    func makeContentViewModel(modelContext: ModelContext) -> ContentViewModel {
        let parserActor = ParserActor(
            modelContainer: modelContext.container,
            selectorsManager: selectorsManager,
            powerManager: powerManager
        )
        return ContentViewModel(
            modelContext: modelContext,
            parserActor: parserActor,
            exportService: exportService,
            flipAnalyzer: flipAnalyzer,
            detailLoader: makeDetailPageLoader()
        )
    }

    @MainActor
    private func makeDetailPageLoader() -> DetailPageLoader {
        DetailPageLoader(detailParser: detailParser, powerManager: powerManager)
    }

    @MainActor
    func makeLLMChatViewModel() -> LLMChatViewModel {
        LLMChatViewModel(llm: llm)
    }
}
