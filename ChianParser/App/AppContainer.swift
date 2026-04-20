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

    let searchParser: any SearchParserProtocol
    let detailParser: any DetailParserProtocol
    let exportService: any ExportServiceProtocol
    let flipAnalyzer: any FlipAnalyzerProtocol

    // MARK: - Init

    init(
        searchParser: any SearchParserProtocol = CianDataExtractor(),
        detailParser: any DetailParserProtocol = CianDetailParser(),
        exportService: any ExportServiceProtocol = ExportManager(),
        flipAnalyzer: any FlipAnalyzerProtocol = FlipAnalyzer()
    ) {
        self.searchParser = searchParser
        self.detailParser = detailParser
        self.exportService = exportService
        self.flipAnalyzer = flipAnalyzer
    }

    // MARK: - Factory Methods

    @MainActor
    func makeContentViewModel(modelContext: ModelContext) -> ContentViewModel {
        ContentViewModel(
            modelContext: modelContext,
            searchParser: searchParser,
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
