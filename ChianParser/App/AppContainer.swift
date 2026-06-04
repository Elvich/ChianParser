//
//  AppContainer.swift
//  ChianParser
//
//  DI container: holds all service singletons and creates ViewModels via factory methods.
//

import Foundation
import SwiftData

@Observable
final class AppContainer {

    // MARK: - Services

    let selectorsManager: any SelectorsManagerProtocol
    let searchParser: any SearchParserProtocol
    let detailParser: any DetailParserProtocol
    let exportService: any ExportServiceProtocol
    let flipAnalyzer: any FlipAnalyzerProtocol

    // MARK: - Init

    init(
        selectorsManager: any SelectorsManagerProtocol = SelectorsManager(),
        exportService: any ExportServiceProtocol = ExportManager(),
        flipAnalyzer: any FlipAnalyzerProtocol = FlipAnalyzer()
    ) {
        self.selectorsManager = selectorsManager
        self.searchParser = CianDataExtractor(selectorsManager: selectorsManager)
        self.detailParser = CianDetailParser(selectorsManager: selectorsManager)
        self.exportService = exportService
        self.flipAnalyzer = flipAnalyzer
    }

    // MARK: - Factory Methods

    @MainActor
    func makeContentViewModel(modelContext: ModelContext) -> ContentViewModel {
        let parserActor = ParserActor(modelContainer: modelContext.container, selectorsManager: selectorsManager)
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
        DetailPageLoader(detailParser: detailParser)
    }
}
