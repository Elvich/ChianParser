//
//  ExportServiceProtocol.swift
//  ChianParser
//

import Foundation

/// Abstracts exporting apartment data to external formats and revealing files in Finder.
protocol ExportServiceProtocol {
    func exportToCSV(apartments: [Apartment]) -> URL?
    func exportToJSON(apartments: [Apartment]) -> URL?
    func revealInFinder(_ url: URL)
}
